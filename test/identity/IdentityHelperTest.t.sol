// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {EnclaveIdentityHelper, EnclaveId} from "../../src/helper/EnclaveIdentityHelper.sol";
import {IdentityConstants} from "./IdentityConstants.t.sol";

contract IdentityHelperTest is IdentityConstants, Test {
    EnclaveIdentityHelper enclaveIdentityLib;

    function setUp() public {
        enclaveIdentityLib = new EnclaveIdentityHelper();
    }

    function testIdentitySummary() public {
        (uint256 issueDate, uint256 nextUpdate, EnclaveId id) = enclaveIdentityLib.getIdentitySummary(string(identityStr));
        assertEq(issueDate, 1705288015);
        assertEq(nextUpdate, 1707880015);
        assertEq(uint256(id), 0);
    }

    // TODO: add more tests after full parser implementation is complete
}
