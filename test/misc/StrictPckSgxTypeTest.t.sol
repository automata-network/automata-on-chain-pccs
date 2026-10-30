// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {StrictPckExtension} from "../../src/helpers/StrictPckExtension.sol";

contract SgxTypeParserHarness {
    function parse(bytes memory der) external pure returns (StrictPckExtension.Identity memory) {
        return StrictPckExtension.parse(der, 0);
    }
}

contract StrictPckSgxTypeTest is Test {
    SgxTypeParserHarness parser = new SgxTypeParserHarness();
    bytes constant PREFIX = hex"2a864886f84d010d01";

    function tlv(bytes1 tag, bytes memory value) internal pure returns (bytes memory) {
        bytes memory length = value.length < 128
            ? abi.encodePacked(uint8(value.length))
            : value.length < 256
                ? abi.encodePacked(hex"81", uint8(value.length))
                : abi.encodePacked(hex"82", uint16(value.length));
        return bytes.concat(tag, length, value);
    }

    function field(bytes memory prefix, uint8 id, bytes memory value) internal pure returns (bytes memory) {
        return tlv(0x30, bytes.concat(tlv(0x06, bytes.concat(prefix, bytes1(id))), value));
    }

    function extension(bytes memory sgxType) internal pure returns (bytes memory) {
        bytes memory tcb;
        for (uint8 i = 1; i <= 17; ++i) {
            tcb = bytes.concat(tcb, field(bytes.concat(PREFIX, hex"02"), i, hex"020101"));
        }
        tcb = bytes.concat(tcb, field(bytes.concat(PREFIX, hex"02"), 18, tlv(0x04, new bytes(16))));
        bytes memory config = bytes.concat(
            field(bytes.concat(PREFIX, hex"07"), 1, hex"0101ff"),
            field(bytes.concat(PREFIX, hex"07"), 2, hex"010100"),
            field(bytes.concat(PREFIX, hex"07"), 3, hex"0101ff")
        );
        bytes memory fields = bytes.concat(
            field(PREFIX, 1, tlv(0x04, new bytes(16))),
            field(PREFIX, 2, tlv(0x30, tcb)),
            field(PREFIX, 3, hex"04020001"),
            field(PREFIX, 4, hex"0406010203040506"),
            field(PREFIX, 5, sgxType),
            field(PREFIX, 6, tlv(0x04, hex"01020304050607080910111213141516")),
            field(PREFIX, 7, tlv(0x30, config))
        );
        return tlv(0xa3, tlv(0x30, tlv(0x30, bytes.concat(tlv(0x06, PREFIX), tlv(0x04, tlv(0x30, fields))))));
    }

    function testKnownSgxTypesPreserveTcbAndPlatformIdentity() public {
        for (uint8 value; value <= 2; ++value) {
            StrictPckExtension.Identity memory identity = parser.parse(extension(abi.encodePacked(hex"0a01", value)));
            assertEq(identity.pcesvn, 1);
            assertEq(identity.cpusvns.length, 16);
            for (uint256 i; i < 16; ++i) {
                assertEq(identity.cpusvns[i], 1);
            }
            assertEq(identity.fmspc, hex"010203040506");
            assertEq(identity.pceid, hex"0001");
            assertTrue(identity.piidPresent);
            assertEq(identity.piid, bytes16(hex"01020304050607080910111213141516"));
        }
    }

    function testRejectsUnknownSgxType() public {
        bytes memory der = extension(hex"0a0103");
        vm.expectRevert(StrictPckExtension.InvalidPckExtension.selector);
        parser.parse(der);
    }

    function testRejectsIntegerInsteadOfEnumerated() public {
        bytes memory der = extension(hex"020102");
        vm.expectRevert(StrictPckExtension.InvalidPckExtension.selector);
        parser.parse(der);
    }
}
