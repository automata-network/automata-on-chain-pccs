// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {EnclaveIdentityHelper, EnclaveId, IdentityObj} from "../../src/helpers/EnclaveIdentityHelper.sol";
import {IdentityConstants} from "./IdentityConstants.t.sol";

contract IdentityHelperTest is IdentityConstants, Test {
    EnclaveIdentityHelper enclaveIdentityLib;

    function setUp() public {
        enclaveIdentityLib = new EnclaveIdentityHelper();
    }

    function testIdentityContentHash() public {
        string memory id0 = "{\"id\":\"QE\",\"version\":2,\"issueDate\":\"2025-02-12T12:33:04Z\",\"nextUpdate\":\"2025-03-14T12:33:04Z\",\"tcbEvaluationDataNumber\":17,\"miscselect\":\"00000000\",\"miscselectMask\":\"FFFFFFFF\",\"attributes\":\"11000000000000000000000000000000\",\"attributesMask\":\"FBFFFFFFFFFFFFFF0000000000000000\",\"mrsigner\":\"8C4F5775D796503E96137F77C68A829A0056AC8DED70140B081B094490C57BFF\",\"isvprodid\":1,\"tcbLevels\":[{\"tcb\":{\"isvsvn\":8},\"tcbDate\":\"2024-03-13T00:00:00Z\",\"tcbStatus\":\"UpToDate\"},{\"tcb\":{\"isvsvn\":6},\"tcbDate\":\"2021-11-10T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"isvsvn\":5},\"tcbDate\":\"2020-11-11T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"isvsvn\":4},\"tcbDate\":\"2019-11-13T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"isvsvn\":2},\"tcbDate\":\"2019-05-15T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"isvsvn\":1},\"tcbDate\":\"2018-08-15T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"}]}";
        string memory id1 = "{\"id\":\"QE\",\"version\":2,\"issueDate\":\"2025-02-12T13:33:05Z\",\"nextUpdate\":\"2025-03-14T13:33:05Z\",\"tcbEvaluationDataNumber\":17,\"miscselect\":\"00000000\",\"miscselectMask\":\"FFFFFFFF\",\"attributes\":\"11000000000000000000000000000000\",\"attributesMask\":\"FBFFFFFFFFFFFFFF0000000000000000\",\"mrsigner\":\"8C4F5775D796503E96137F77C68A829A0056AC8DED70140B081B094490C57BFF\",\"isvprodid\":1,\"tcbLevels\":[{\"tcb\":{\"isvsvn\":8},\"tcbDate\":\"2024-03-13T00:00:00Z\",\"tcbStatus\":\"UpToDate\"},{\"tcb\":{\"isvsvn\":6},\"tcbDate\":\"2021-11-10T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"isvsvn\":5},\"tcbDate\":\"2020-11-11T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"isvsvn\":4},\"tcbDate\":\"2019-11-13T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"isvsvn\":2},\"tcbDate\":\"2019-05-15T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"isvsvn\":1},\"tcbDate\":\"2018-08-15T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"}]}";

        (IdentityObj memory identity0, string memory identityTcbStr0)
            = enclaveIdentityLib.parseIdentityString(id0);

        (IdentityObj memory identity1, string memory identityTcbStr1)
            = enclaveIdentityLib.parseIdentityString(id1);

        bytes32 contentHash0 = enclaveIdentityLib.getIdentityContentHash(identity0, identityTcbStr0);
        bytes32 contentHash1 = enclaveIdentityLib.getIdentityContentHash(identity1, identityTcbStr1);

        assertEq(contentHash0, contentHash1);
    }

    function testIdentityParser() public {
        (IdentityObj memory identity, ) = enclaveIdentityLib.parseIdentityString(string(identityStr));
        assertEq(identity.version, 2);
        assertEq(identity.tcbEvaluationDataNumber, 16);
        assertEq(identity.miscselect, bytes4(0));
        assertEq(identity.miscselectMask, bytes4(0xFFFFFFFF));
        assertEq(identity.attributes, bytes16(0x11000000000000000000000000000000));
        assertEq(identity.attributesMask, bytes16(0xFBFFFFFFFFFFFFFF0000000000000000));
        assertEq(identity.mrsigner, bytes32(0x8C4F5775D796503E96137F77C68A829A0056AC8DED70140B081B094490C57BFF));
        assertEq(identity.isvprodid, 1);
    }
}
