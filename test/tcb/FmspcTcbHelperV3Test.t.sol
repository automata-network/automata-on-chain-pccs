// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../../src/helpers/FmspcTcbHelper.sol";
import "../../src/helpers/FmspcTcbHelperV3.sol";
import "./TCBConstants.t.sol";

/// @notice Byte-exact round-trip tests for FmspcTcbHelperV3.serializeTcbLevel.
/// For each of the three embedded fixtures (sgx v2, sgx v3, tdx v3) we:
/// 1) Parse the inner tcbInfo with FmspcTcbHelper to obtain TCBLevelsObj[] and packed bytes
/// 2) Walk the raw tcbInfo string with a depth-1 brace scanner to find per-level byte ranges
/// 3) Extract sgxComponentsTemplate (and tdxComponentsTemplate when present) from level[0]
/// 4) Call FmspcTcbHelperV3.serializeTcbLevel(...) and assert byte-exact equality with the raw level slice
contract FmspcTcbHelperV3Test is TCBConstants, Test {
    FmspcTcbHelper fmspcTcbLib;
    FmspcTcbHelperV3 fmspcTcbLibV3;

    function setUp() public {
        fmspcTcbLib = new FmspcTcbHelper();
        fmspcTcbLibV3 = new FmspcTcbHelperV3();
    }

    function testRoundTripSgxV3() public {
        bytes memory raw = bytes(sgx_v3_tcbStr);
        _assertAllLevelsRoundTrip(raw, 3 /* schemaVersion */, TcbId.SGX);
    }

    function testRoundTripTdxV3() public {
        bytes memory raw = bytes(tdx_tcbStr);
        _assertAllLevelsRoundTrip(raw, 3, TcbId.TDX);
    }

    function testRoundTripSgxV2() public {
        bytes memory raw = sgx_v2_tcbStr;
        _assertAllLevelsRoundTrip(raw, 2, TcbId.SGX);
    }

    function _parseAndRanges(bytes memory raw)
        internal
        view
        returns (TcbInfoBasic memory basic, TcbInfoRanges memory ranges)
    {
        (basic, , , ) = fmspcTcbLib.parseTcbString(string(raw));
        (uint32 a, uint32 b, uint32 c, uint32 d,,) = fmspcTcbLibV3.findArrayBounds(raw);
        ranges = TcbInfoRanges(a, b, c, d);
    }

    function testRoundTripTdxIdentities() public {
        bytes memory raw = bytes(tdx_tcbStr);
        (, TcbInfoRanges memory ranges) = _parseAndRanges(raw);
        // Extract identity raw substrings via depth-1 brace scan
        (uint32[] memory idStarts, uint32[] memory idEnds) =
            _scanArrayItems(raw, ranges.tdxModuleIdentitiesArrayStart, ranges.tdxModuleIdentitiesArrayEnd);
        assertGt(idStarts.length, 0);

        // Use v1 helper to parse + repack identities
        bytes memory identitiesJson = _bytesSlice(
            raw,
            ranges.tdxModuleIdentitiesArrayStart,
            ranges.tdxModuleIdentitiesArrayEnd - ranges.tdxModuleIdentitiesArrayStart
        );
        // tdxModuleString is unused for identities parsing; pass a minimal valid tdxModule object
        bytes memory minimalTdxModule = bytes(
            "{\"mrsigner\":\"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\",\"attributes\":\"0000000000000000\",\"attributesMask\":\"FFFFFFFFFFFFFFFF\"}"
        );
        (, TDXModuleIdentity[] memory identities) =
            fmspcTcbLib.parseTcbTdxModules(string(minimalTdxModule), string(identitiesJson));
        assertEq(identities.length, idStarts.length);

        for (uint256 i = 0; i < identities.length; i++) {
            bytes memory packed = fmspcTcbLib.tdxModuleIdentityToBytes(identities[i]);
            (bytes memory mrSignerHex, bytes memory attrHex, bytes memory attrMaskHex) =
                _extractIdentityHexFields(raw, idStarts[i], idEnds[i]);
            bytes20[] memory nestedDates = _extractNestedTcbDates(raw, idStarts[i], idEnds[i]);

            bytes memory serialized = fmspcTcbLibV3.serializeTdxModuleIdentity(
                packed,
                mrSignerHex,
                attrHex,
                attrMaskHex,
                nestedDates
            );

            bytes memory expected = _bytesSlice(raw, idStarts[i], idEnds[i] - idStarts[i]);
            if (keccak256(serialized) != keccak256(expected)) {
                emit log_named_uint("identity index", i);
                emit log_named_bytes("serialized", serialized);
                emit log_named_bytes("expected  ", expected);
            }
            assertEq(keccak256(serialized), keccak256(expected), "identity round-trip mismatch");
        }
    }

    function testFindArrayBoundsMarksOuterArrays() public {
        bytes memory raw = bytes(tdx_tcbStr);
        (TcbInfoBasic memory basic, TcbInfoRanges memory ranges) = _parseAndRanges(raw);

        assertEq(uint8(basic.id), uint8(TcbId.TDX));
        assertEq(uint256(basic.version), 3);
        // The outer tcbLevels array must begin with '[' and end one past its matching ']'.
        assertEq(uint8(raw[ranges.tcbLevelsArrayStart]), uint8(bytes1("[")));
        assertEq(uint8(raw[ranges.tcbLevelsArrayEnd - 1]), uint8(bytes1("]")));
        // tdxModuleIdentities is also a top-level array in v3+TDX.
        assertGt(ranges.tdxModuleIdentitiesArrayEnd, ranges.tdxModuleIdentitiesArrayStart);
        assertEq(uint8(raw[ranges.tdxModuleIdentitiesArrayStart]), uint8(bytes1("[")));
        assertEq(uint8(raw[ranges.tdxModuleIdentitiesArrayEnd - 1]), uint8(bytes1("]")));
        // The outer occurrence must come AFTER the nested tcbLevels keys inside tdxModuleIdentities.
        // (Sanity: outer tcbLevels in tdx_tcbStr appears after tdxModuleIdentities array in source order.)
        assertGt(ranges.tcbLevelsArrayStart, ranges.tdxModuleIdentitiesArrayEnd);
    }

    /* -------- helpers -------- */

    function _assertAllLevelsRoundTrip(bytes memory raw, uint8 schemaVersion, TcbId id) internal {
        (TcbInfoBasic memory basic, TcbInfoRanges memory ranges) = _parseAndRanges(raw);
        assertEq(uint256(basic.version), uint256(schemaVersion), "fixture version mismatch");
        assertEq(uint8(basic.id), uint8(id), "fixture id mismatch");

        // Extract per-level (start, end) inside the tcbLevels array via depth-1 brace scan.
        (uint32[] memory levelStarts, uint32[] memory levelEnds) =
            _scanArrayItems(raw, ranges.tcbLevelsArrayStart, ranges.tcbLevelsArrayEnd);
        assertGt(levelStarts.length, 0, "no levels found");

        // For v3, pull the components templates out of level[0].
        bytes memory sgxTpl;
        bytes memory tdxTpl;
        bool hasTdx = (schemaVersion == 3 && id == TcbId.TDX);
        if (schemaVersion == 3) {
            sgxTpl = _extractComponentsTemplate(raw, levelStarts[0], levelEnds[0], "\"sgxtcbcomponents\":");
        }
        if (hasTdx) {
            tdxTpl = _extractComponentsTemplate(raw, levelStarts[0], levelEnds[0], "\"tdxtcbcomponents\":");
        }

        // Parse all levels via v1 helper to obtain TCBLevelsObj[] in order.
        // _value style: the v1 helper takes the tcbLevels JSON string. Slice it from raw.
        bytes memory tcbLevelsJson =
            _bytesSlice(raw, ranges.tcbLevelsArrayStart, ranges.tcbLevelsArrayEnd - ranges.tcbLevelsArrayStart);
        TCBLevelsObj[] memory levels = fmspcTcbLib.parseTcbLevels(uint256(schemaVersion), string(tcbLevelsJson));
        assertEq(levels.length, levelStarts.length, "parsed level count != scanned count");

        for (uint256 i = 0; i < levels.length; i++) {
            bytes memory packed = fmspcTcbLib.tcbLevelsObjToBytes(levels[i]);
            bytes20 rawDate = _extractRawTcbDate(raw, levelStarts[i], levelEnds[i]);

            bytes memory serialized = fmspcTcbLibV3.serializeTcbLevel(
                packed,
                rawDate,
                schemaVersion,
                hasTdx,
                sgxTpl,
                tdxTpl
            );

            bytes memory expected = _bytesSlice(raw, levelStarts[i], levelEnds[i] - levelStarts[i]);
            if (keccak256(serialized) != keccak256(expected)) {
                emit log_named_uint("level index", i);
                emit log_named_bytes("serialized", serialized);
                emit log_named_bytes("expected  ", expected);
            }
            assertEq(keccak256(serialized), keccak256(expected), "level round-trip mismatch");
        }
    }

    /// @dev Depth-1 brace scanner. Given an array `[ {...}, {...}, ... ]` spanning [arrStart, arrEnd),
    /// returns per-item (startOfOpenBrace, positionAfterCloseBrace).
    function _scanArrayItems(bytes memory raw, uint32 arrStart, uint32 arrEnd)
        internal
        pure
        returns (uint32[] memory starts, uint32[] memory ends)
    {
        require(raw[arrStart] == "[", "not array");
        // First pass: count items.
        uint32 count;
        {
            uint32 depth;
            for (uint32 p = arrStart + 1; p < arrEnd - 1; p++) {
                bytes1 c = raw[p];
                if (c == "{") {
                    if (depth == 0) count++;
                    depth++;
                } else if (c == "}") {
                    require(depth > 0, "unbalanced brace");
                    depth--;
                } else if (c == '"') {
                    // skip over string literal (no \" expected in Intel TCBInfo)
                    p++;
                    while (p < arrEnd - 1 && raw[p] != '"') {
                        if (raw[p] == "\\") p++;
                        p++;
                    }
                }
            }
        }
        starts = new uint32[](count);
        ends = new uint32[](count);
        // Second pass: capture per-item bounds.
        uint32 idx;
        uint32 depth2;
        uint32 currentStart;
        for (uint32 p = arrStart + 1; p < arrEnd - 1; p++) {
            bytes1 c = raw[p];
            if (c == "{") {
                if (depth2 == 0) currentStart = p;
                depth2++;
            } else if (c == "}") {
                depth2--;
                if (depth2 == 0) {
                    starts[idx] = currentStart;
                    ends[idx] = p + 1;
                    idx++;
                }
            } else if (c == '"') {
                p++;
                while (p < arrEnd - 1 && raw[p] != '"') {
                    if (raw[p] == "\\") p++;
                    p++;
                }
            }
        }
    }

    /// @dev Extract the value of `key:[...]` inside a level's bytes. Key includes the surrounding quotes
    /// and trailing colon, e.g. `"sgxtcbcomponents":`. Returns the array INCLUDING its outer brackets.
    function _extractComponentsTemplate(bytes memory raw, uint32 levelStart, uint32 levelEnd, bytes memory key)
        internal
        pure
        returns (bytes memory)
    {
        // Find `key` in raw[levelStart..levelEnd]
        uint32 keyLen = uint32(key.length);
        uint32 hit = type(uint32).max;
        for (uint32 p = levelStart; p + keyLen <= levelEnd; p++) {
            bool m = true;
            for (uint32 j = 0; j < keyLen; j++) {
                if (raw[p + j] != key[j]) {
                    m = false;
                    break;
                }
            }
            if (m) {
                hit = p;
                break;
            }
        }
        require(hit != type(uint32).max, "key not found");
        uint32 arrStart = hit + keyLen;
        require(raw[arrStart] == "[", "key not array");
        uint32 depth;
        uint32 p2 = arrStart;
        while (p2 < levelEnd) {
            bytes1 c = raw[p2];
            if (c == "[") depth++;
            else if (c == "]") {
                depth--;
                if (depth == 0) {
                    return _bytesSlice(raw, arrStart, (p2 + 1) - arrStart);
                }
            } else if (c == '"') {
                p2++;
                while (p2 < levelEnd && raw[p2] != '"') {
                    if (raw[p2] == "\\") p2++;
                    p2++;
                }
            }
            p2++;
        }
        revert("template extraction failed");
    }

    /// @dev Extract the 20-byte ISO timestamp value following `"tcbDate":"` inside a level.
    function _extractRawTcbDate(bytes memory raw, uint32 levelStart, uint32 levelEnd)
        internal
        pure
        returns (bytes20 rawDate)
    {
        bytes memory key = bytes("\"tcbDate\":\"");
        uint32 keyLen = uint32(key.length);
        for (uint32 p = levelStart; p + keyLen + 20 < levelEnd; p++) {
            bool m = true;
            for (uint32 j = 0; j < keyLen; j++) {
                if (raw[p + j] != key[j]) {
                    m = false;
                    break;
                }
            }
            if (m) {
                uint32 dateStart = p + keyLen;
                for (uint32 k = 0; k < 20; k++) {
                    rawDate |= bytes20(uint160(uint8(raw[dateStart + k])) << uint160(8 * (19 - k)));
                }
                return rawDate;
            }
        }
        revert("tcbDate not found");
    }

    /// @dev Extract the ASCII hex values of mrsigner, attributes, attributesMask from a TDXModuleIdentity raw substring.
    function _extractIdentityHexFields(bytes memory raw, uint32 idStart, uint32 idEnd)
        internal
        pure
        returns (bytes memory mrSignerHex, bytes memory attrHex, bytes memory attrMaskHex)
    {
        mrSignerHex = _extractStringValue(raw, idStart, idEnd, bytes("\"mrsigner\":\""), 96);
        attrHex = _extractStringValue(raw, idStart, idEnd, bytes("\"attributes\":\""), 16);
        attrMaskHex = _extractStringValue(raw, idStart, idEnd, bytes("\"attributesMask\":\""), 16);
    }

    function _extractStringValue(
        bytes memory raw,
        uint32 start,
        uint32 end,
        bytes memory key,
        uint32 expectedLength
    ) internal pure returns (bytes memory val) {
        uint32 keyLen = uint32(key.length);
        for (uint32 p = start; p + keyLen + expectedLength < end; p++) {
            bool m = true;
            for (uint32 j = 0; j < keyLen; j++) {
                if (raw[p + j] != key[j]) {
                    m = false;
                    break;
                }
            }
            if (m) {
                return _bytesSlice(raw, p + keyLen, expectedLength);
            }
        }
        revert("key not found");
    }

    function _extractNestedTcbDates(bytes memory raw, uint32 idStart, uint32 idEnd)
        internal
        pure
        returns (bytes20[] memory dates)
    {
        // Find "tcbLevels":[ inside the identity, then scan top-level {...} items inside the array.
        bytes memory key = bytes("\"tcbLevels\":");
        uint32 keyLen = uint32(key.length);
        uint32 hit = type(uint32).max;
        for (uint32 p = idStart; p + keyLen < idEnd; p++) {
            bool m = true;
            for (uint32 j = 0; j < keyLen; j++) {
                if (raw[p + j] != key[j]) {
                    m = false;
                    break;
                }
            }
            if (m) {
                hit = p;
                break;
            }
        }
        require(hit != type(uint32).max, "nested tcbLevels not found");
        uint32 arrStart = hit + keyLen;
        require(raw[arrStart] == "[", "nested not array");
        // find matching ']'
        uint32 depth;
        uint32 arrEnd = arrStart;
        for (uint32 p = arrStart; p < idEnd; p++) {
            bytes1 c = raw[p];
            if (c == "[") depth++;
            else if (c == "]") {
                depth--;
                if (depth == 0) {
                    arrEnd = p + 1;
                    break;
                }
            } else if (c == '"') {
                p++;
                while (p < idEnd && raw[p] != '"') {
                    if (raw[p] == "\\") p++;
                    p++;
                }
            }
        }
        (uint32[] memory levelStarts, uint32[] memory levelEnds) = _scanArrayItems(raw, arrStart, arrEnd);
        dates = new bytes20[](levelStarts.length);
        for (uint256 i = 0; i < levelStarts.length; i++) {
            dates[i] = _extractRawTcbDate(raw, levelStarts[i], levelEnds[i]);
        }
    }

    function _bytesSlice(bytes memory src, uint256 offset, uint256 length) internal pure returns (bytes memory) {
        bytes memory dst = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            dst[i] = src[offset + i];
        }
        return dst;
    }
}
