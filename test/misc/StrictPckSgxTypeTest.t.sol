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

    function configuration() internal pure returns (bytes memory) {
        return tlv(
            0x30,
            bytes.concat(
                field(bytes.concat(PREFIX, hex"07"), 1, hex"0101ff"),
                field(bytes.concat(PREFIX, hex"07"), 2, hex"010100"),
                field(bytes.concat(PREFIX, hex"07"), 3, hex"0101ff")
            )
        );
    }

    function extension(bytes memory sgxType) internal pure returns (bytes memory) {
        return extension(sgxType, true, configuration());
    }

    function extension(bytes memory sgxType, bool piidPresent, bytes memory config)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory tcb;
        for (uint8 i = 1; i <= 17; ++i) {
            tcb = bytes.concat(tcb, field(bytes.concat(PREFIX, hex"02"), i, hex"020101"));
        }
        tcb = bytes.concat(tcb, field(bytes.concat(PREFIX, hex"02"), 18, tlv(0x04, new bytes(16))));
        bytes memory fields = bytes.concat(
            field(PREFIX, 1, tlv(0x04, new bytes(16))),
            field(PREFIX, 2, tlv(0x30, tcb)),
            field(PREFIX, 3, hex"04020001"),
            field(PREFIX, 4, hex"0406010203040506"),
            field(PREFIX, 5, sgxType),
            piidPresent ? field(PREFIX, 6, tlv(0x04, hex"01020304050607080910111213141516")) : bytes(""),
            config.length != 0 ? field(PREFIX, 7, config) : bytes("")
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

    function testPiidAndConfigurationMustAppearTogetherForEveryKnownType() public {
        for (uint8 value; value <= 2; ++value) {
            bytes memory sgxType = abi.encodePacked(hex"0a01", value);
            StrictPckExtension.Identity memory absent = parser.parse(extension(sgxType, false, bytes("")));
            assertFalse(absent.piidPresent);
            bytes memory missingConfig = extension(sgxType, true, bytes(""));
            vm.expectRevert(StrictPckExtension.InvalidPckExtension.selector);
            parser.parse(missingConfig);
            bytes memory missingPiid = extension(sgxType, false, configuration());
            vm.expectRevert(StrictPckExtension.InvalidPckExtension.selector);
            parser.parse(missingPiid);
        }
    }

    function testAllFalseConfigurationIsPresent() public {
        bytes memory flags;
        for (uint8 i = 1; i <= 3; ++i) {
            flags = bytes.concat(flags, field(bytes.concat(PREFIX, hex"07"), i, hex"010100"));
        }
        assertTrue(parser.parse(extension(hex"0a0102", true, tlv(0x30, flags))).piidPresent);
    }

    function testRejectsMalformedConfigurationWithPiidPresent() public {
        bytes memory prefix = bytes.concat(PREFIX, hex"07");
        bytes memory first = field(prefix, 1, hex"010100");
        bytes memory second = field(prefix, 2, hex"010100");
        bytes memory third = field(prefix, 3, hex"010100");
        bytes[7] memory invalid = [
            bytes(hex"3000"),
            tlv(0x30, bytes.concat(first, second)),
            tlv(0x30, bytes.concat(first, second, third, third)),
            tlv(0x30, bytes.concat(first, second, field(prefix, 3, hex"020100"))),
            tlv(0x30, bytes.concat(first, second, field(prefix, 3, hex"010101"))),
            tlv(0x30, bytes.concat(first, second, third, field(prefix, 4, hex"010100"))),
            tlv(0x31, bytes.concat(first, second, third))
        ];
        for (uint256 i; i < invalid.length; ++i) {
            bytes memory der = extension(hex"0a0102", true, invalid[i]);
            vm.expectRevert(StrictPckExtension.InvalidPckExtension.selector);
            parser.parse(der);
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
