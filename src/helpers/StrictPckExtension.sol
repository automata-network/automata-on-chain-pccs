// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @dev Bounded DER parser used exclusively by the additive identity entrypoint.
/// The legacy X509/SGX parser is deliberately not changed.
library StrictPckExtension {
    error InvalidPckExtension();

    struct Identity {
        uint16 pcesvn;
        uint8[] cpusvns;
        bytes fmspc;
        bytes pceid;
        bytes16 ppid;
        bytes16 piid;
        bool piidPresent;
    }

    struct Node {
        uint8 tag;
        uint256 start;
        uint256 end;
    }

    function parse(bytes memory der, uint256 extensionPtr) internal pure returns (Identity memory result) {
        Node memory wrapper = node(der, uint80(extensionPtr), der.length);
        expect(wrapper.tag == 0xa3);
        Node memory extensions = node(der, wrapper.start, wrapper.end);
        expect(extensions.tag == 0x30 && extensions.end == wrapper.end);
        bool found;
        uint256 cursor = extensions.start;
        while (cursor < extensions.end) {
            Node memory extension = node(der, cursor, extensions.end);
            expect(extension.tag == 0x30);
            Node memory oid = node(der, extension.start, extension.end);
            expect(oid.tag == 0x06);
            Node memory value = node(der, oid.end, extension.end);
            if (value.tag == 0x01) {
                // DER omits the DEFAULT FALSE critical flag.
                expect(value.end - value.start == 1 && der[value.start] == 0xff);
                value = node(der, value.end, extension.end);
            }
            expect(value.tag == 0x04 && value.end == extension.end);
            if (matches(der, oid, hex"2a864886f84d010d01")) {
                expect(!found);
                found = true;
                Node memory sgx = node(der, value.start, value.end);
                expect(sgx.tag == 0x30 && sgx.end == value.end);
                result = parseSgx(der, sgx);
            }
            cursor = extension.end;
        }
        expect(found);
    }

    function parseSgx(bytes memory der, Node memory seq) private pure returns (Identity memory out) {
        uint256 seen;
        uint256 cursor = seq.start;
        while (cursor < seq.end) {
            (uint256 id, Node memory value, uint256 next) = field(der, cursor, seq.end, hex"2a864886f84d010d01");
            expect(id >= 1 && id <= 7 && seen & (1 << id) == 0);
            seen |= 1 << id;
            if (id == 1) {
                out.ppid = bytes16(octets(der, value, 16));
            } else if (id == 2) {
                (out.pcesvn, out.cpusvns) = parseTcb(der, value);
            } else if (id == 3) {
                out.pceid = octets(der, value, 2);
            } else if (id == 4) {
                out.fmspc = octets(der, value, 6);
            } else if (id == 5) {
                expect(number(der, value, 0x0a, 1) <= 1);
            } else if (id == 6) {
                out.piid = bytes16(octets(der, value, 16));
                out.piidPresent = true;
            } else {
                parseConfiguration(der, value);
            }
            cursor = next;
        }
        expect(seen & 0x3e == 0x3e); // PPID, TCB, PCEID, FMSPC, SGX Type.
    }

    function parseTcb(bytes memory der, Node memory seq) private pure returns (uint16 pcesvn, uint8[] memory svns) {
        expect(seq.tag == 0x30);
        svns = new uint8[](16);
        uint256 seen;
        uint256 cursor = seq.start;
        while (cursor < seq.end) {
            (uint256 id, Node memory value, uint256 next) = field(der, cursor, seq.end, hex"2a864886f84d010d0102");
            expect(id >= 1 && id <= 18 && seen & (1 << id) == 0);
            seen |= 1 << id;
            if (id <= 16) svns[id - 1] = uint8(number(der, value, 0x02, 255));
            else if (id == 17) pcesvn = uint16(number(der, value, 0x02, 65535));
            else octets(der, value, 16);
            cursor = next;
        }
        expect(seen == 0x7fffe);
    }

    function parseConfiguration(bytes memory der, Node memory seq) private pure {
        expect(seq.tag == 0x30);
        uint256 seen;
        uint256 cursor = seq.start;
        while (cursor < seq.end) {
            (uint256 id, Node memory value, uint256 next) = field(der, cursor, seq.end, hex"2a864886f84d010d0107");
            expect(id >= 1 && id <= 3 && seen & (1 << id) == 0);
            seen |= 1 << id;
            expect(value.tag == 0x01 && value.end - value.start == 1);
            expect(der[value.start] == 0x00 || der[value.start] == 0xff);
            cursor = next;
        }
        expect(seen == 0x0e);
    }

    function field(bytes memory der, uint256 cursor, uint256 end, bytes memory prefix)
        private
        pure
        returns (uint256 id, Node memory value, uint256 next)
    {
        Node memory seq = node(der, cursor, end);
        expect(seq.tag == 0x30);
        Node memory oid = node(der, seq.start, seq.end);
        expect(oid.tag == 0x06 && oid.end - oid.start == prefix.length + 1);
        for (uint256 i; i < prefix.length; ++i) {
            expect(der[oid.start + i] == prefix[i]);
        }
        id = uint8(der[oid.end - 1]);
        value = node(der, oid.end, seq.end);
        expect(value.end == seq.end);
        next = seq.end;
    }

    function node(bytes memory der, uint256 cursor, uint256 limit) private pure returns (Node memory out) {
        expect(limit <= der.length && cursor < limit && limit - cursor >= 2);
        out.tag = uint8(der[cursor++]);
        uint256 length = uint8(der[cursor++]);
        if (length >= 128) {
            uint256 count = length & 0x7f;
            expect(count > 0 && count <= 4 && count <= limit - cursor);
            expect(der[cursor] != 0);
            length = 0;
            for (uint256 i; i < count; ++i) {
                length = (length << 8) | uint8(der[cursor++]);
            }
            expect(length >= 128);
        }
        expect(length <= limit - cursor);
        out.start = cursor;
        out.end = cursor + length;
    }

    function number(bytes memory der, Node memory value, uint8 tag, uint256 max) private pure returns (uint256 n) {
        uint256 length = value.end - value.start;
        expect(value.tag == tag && length > 0 && length <= 3);
        expect(uint8(der[value.start]) & 0x80 == 0);
        if (length > 1 && der[value.start] == 0) expect(uint8(der[value.start + 1]) & 0x80 != 0);
        for (uint256 i = value.start; i < value.end; ++i) {
            n = (n << 8) | uint8(der[i]);
        }
        expect(n <= max);
    }

    function octets(bytes memory der, Node memory value, uint256 length) private pure returns (bytes memory result) {
        expect(value.tag == 0x04 && value.end - value.start == length);
        result = new bytes(length);
        for (uint256 i; i < length; ++i) {
            result[i] = der[value.start + i];
        }
    }

    function matches(bytes memory der, Node memory oid, bytes memory expected) private pure returns (bool) {
        if (oid.end - oid.start != expected.length) return false;
        for (uint256 i; i < expected.length; ++i) {
            if (der[oid.start + i] != expected[i]) return false;
        }
        return true;
    }

    function expect(bool condition) private pure {
        if (!condition) revert InvalidPckExtension();
    }
}
