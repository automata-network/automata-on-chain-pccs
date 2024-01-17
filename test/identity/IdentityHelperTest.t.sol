// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {EnclaveIdentityHelper} from "../../src/helper/EnclaveIdentityHelper.sol";
import {IdentityConstants} from "./IdentityConstants.t.sol";

contract IdentityHelperTest is IdentityConstants, Test {
    EnclaveIdentityHelper enclaveIdentityLib;

    function setUp() public {
        enclaveIdentityLib = new EnclaveIdentityHelper();
    }

    function testIssueDateAndNextUpdate() public {
        (uint256 issueDate, uint256 nextUpdate) = enclaveIdentityLib.getIssueAndNextUpdateDates(string(identityStr));
        assertEq(issueDate, 1705288015);
        assertEq(nextUpdate, 1707880015);
    }

    // TODO: add more tests after full parser implementation is complete
}