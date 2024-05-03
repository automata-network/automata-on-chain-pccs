// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {FmspcTcbHelper, TCBLevelsObj, TCBStatus} from "../../src/helper/FmspcTcbHelper.sol";
import {TCBConstants} from "./TCBConstants.t.sol";

contract IdentityHelperTest is TCBConstants, Test {
    FmspcTcbHelper fmspcTcbLib;

    function setUp() public {
        fmspcTcbLib = new FmspcTcbHelper();
    }

    function testTcbStringBasicParser() public {
        (uint256 tcbType, string memory fmspc, uint256 version, uint256 issueDate, uint256 nextUpdate) =
            fmspcTcbLib.parseTcbString(string(tcbStr));
        assertEq(tcbType, 0);
        assertEq(keccak256(abi.encodePacked(bytes(fmspc))), keccak256(abi.encodePacked(bytes("00606a000000"))));
        assertEq(version, 3);
        assertEq(issueDate, 1705286687);
        assertEq(nextUpdate, 1707878687);
    }

    function testV3TcbLevelsParser() public {
        (uint256 version, TCBLevelsObj[] memory tcbLevels) = fmspcTcbLib.parseTcbLevels(string(tcbStr));
        assertEq(version, 3);

        // TODO: add test cases for the remaining tcblevels
        _assertTcbLevel(
            tcbLevels[0],
            [12, 12, 3, 3, 255, 255, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            13,
            1691539200,
            TCBStatus.TCB_SW_HARDENING_NEEDED
        );
    }

    function _assertTcbLevel(
        TCBLevelsObj memory tcbLevel,
        uint8[16] memory expectedCpuSvns,
        uint256 expectedPcesvn,
        uint256 expectedTimestamp,
        TCBStatus expectedStatus
    ) private {
        assertEq(tcbLevel.pcesvn, expectedPcesvn);
        assertEq(tcbLevel.tcbDateTimestamp, expectedTimestamp);
        assertEq(uint8(tcbLevel.status), uint8(expectedStatus));
        for (uint256 i = 0; i < 16; i++) {
            assertEq(tcbLevel.cpusvnsArr[i], expectedCpuSvns[i]);
        }
    }
}
