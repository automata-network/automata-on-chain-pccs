// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {FmspcTcbHelper} from "../../src/helper/FmspcTcbHelper.sol";
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

    // TODO: add more tests after full parser implementation is complete
}
