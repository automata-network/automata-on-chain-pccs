// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {EnclaveIdentityHelper, EnclaveId, IdentityObj} from "../../src/helper/EnclaveIdentityHelper.sol";
import {IdentityConstants} from "./IdentityConstants.t.sol";

contract IdentityHelperTest is IdentityConstants, Test {
    EnclaveIdentityHelper enclaveIdentityLib;

    function setUp() public {
        enclaveIdentityLib = new EnclaveIdentityHelper();
    }

    function testIdentitySummary() public {
        (uint256 issueDate, uint256 nextUpdate, EnclaveId id) =
            enclaveIdentityLib.getIdentitySummary(string(identityStr));
        assertEq(issueDate, 1705288015);
        assertEq(nextUpdate, 1707880015);
        assertEq(uint256(id), 0);
    }

    function testIdentityParser() public {
        IdentityObj memory identity = enclaveIdentityLib.parseIdentityString(string(identityStr));
        assertEq(identity.version, 2);
        assertEq(identity.tcbEvaluationDataNumber, 16);
        assertEq(identity.miscselect, bytes4(0));
        assertEq(identity.miscselectMask, bytes4(0xFFFFFFFF));
        assertEq(identity.attributes, bytes16(0x11000000000000000000000000000000));
        assertEq(identity.attributesMask, bytes16(0xFBFFFFFFFFFFFFFF0000000000000000));
        assertEq(identity.mrsigner, bytes32(0x8C4F5775D796503E96137F77C68A829A0056AC8DED70140B081B094490C57BFF));
        assertEq(identity.isvprodid, 1);
        assertEq(keccak256(bytes(identity.rawTcbLevelsObjStr)), 0x26cfff8f7e3f0c1fc3d7beb72ab8bc2ca2d0d776b1db4749b34f2fc1d259110e);
    }
}
