// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../pcs/PCSSetupBase.t.sol";
import "./IdentityConstants.t.sol";
import {AutomataEnclaveIdentityDao} from "../../src/automata_pccs/AutomataEnclaveIdentityDao.sol";

contract AutomataEnclaveIdentityDaoTest is PCSSetupBase, IdentityConstants {
    function setUp() public override {
        super.setUp();
    }

    function testAttestEnclaveIdentity() public {
        uint256 id = 0; // QE
        uint256 version = 3;

        EnclaveIdentityJsonObj memory enclaveIdentityObj =
            EnclaveIdentityJsonObj({identityStr: string(identityStr), signature: signature});

        bytes32 attestationId = enclaveIdDao.upsertEnclaveIdentity(id, version, enclaveIdentityObj);
        assertEq(pccsStorage.collateralPointer(enclaveIdDao.ENCLAVE_ID_KEY(id, version)), attestationId);

        vm.prank(admin);
        EnclaveIdentityJsonObj memory fetched = enclaveIdDao.getEnclaveIdentity(id, version);
        assertEq(fetched.signature, enclaveIdentityObj.signature);
        assertEq(keccak256(bytes(fetched.identityStr)), keccak256(bytes(enclaveIdentityObj.identityStr)));
    }

    function testAndCompareEnclaveIdentity() public {
        uint256 id = 2; // TD_QE
        uint256 version = 4;
        bytes32 key = enclaveIdDao.ENCLAVE_ID_KEY(id, version);

        string memory id_td_qe_0 = "{\"id\":\"TD_QE\",\"version\":2,\"issueDate\":\"2025-02-12T13:30:37Z\",\"nextUpdate\":\"2025-03-14T13:30:37Z\",\"tcbEvaluationDataNumber\":17,\"miscselect\":\"00000000\",\"miscselectMask\":\"FFFFFFFF\",\"attributes\":\"11000000000000000000000000000000\",\"attributesMask\":\"FBFFFFFFFFFFFFFF0000000000000000\",\"mrsigner\":\"DC9E2A7C6F948F17474E34A7FC43ED030F7C1563F1BABDDF6340C82E0E54A8C5\",\"isvprodid\":2,\"tcbLevels\":[{\"tcb\":{\"isvsvn\":4},\"tcbDate\":\"2024-03-13T00:00:00Z\",\"tcbStatus\":\"UpToDate\"}]}";
        bytes memory sig_0 = hex"fc2aea2edcda1ded58eec3b563c3e999717843d1762a9232edee4e94d95056b632b26cc24184282c9733525e8dd02e3aaae4460d79b4a2691c71ce3a32413937";

        string memory id_td_qe_1 = "{\"id\":\"TD_QE\",\"version\":2,\"issueDate\":\"2025-02-12T21:35:31Z\",\"nextUpdate\":\"2025-03-14T21:35:31Z\",\"tcbEvaluationDataNumber\":17,\"miscselect\":\"00000000\",\"miscselectMask\":\"FFFFFFFF\",\"attributes\":\"11000000000000000000000000000000\",\"attributesMask\":\"FBFFFFFFFFFFFFFF0000000000000000\",\"mrsigner\":\"DC9E2A7C6F948F17474E34A7FC43ED030F7C1563F1BABDDF6340C82E0E54A8C5\",\"isvprodid\":2,\"tcbLevels\":[{\"tcb\":{\"isvsvn\":4},\"tcbDate\":\"2024-03-13T00:00:00Z\",\"tcbStatus\":\"UpToDate\"}]}";
        bytes memory sig_1 = hex"4db9874b30c7d2e6b5a9fe6531c4e2cbf0e704176618a93cbfb0f7ae34781810a85bee2f0f89f69ba4d33a95f5929257cafc80b6a63678bbe1f6174c2ec51f83";

        EnclaveIdentityJsonObj memory idObj0 =
            EnclaveIdentityJsonObj({identityStr: id_td_qe_0, signature: sig_0});

        EnclaveIdentityJsonObj memory idObj1 =
            EnclaveIdentityJsonObj({identityStr: id_td_qe_1, signature: sig_1});

        vm.warp(1739367300);
        enclaveIdDao.upsertEnclaveIdentity(id, version, idObj0);
        bytes32 collateralHash0 = enclaveIdDao.getCollateralHash(key);
        assertEq(collateralHash0, sha256(bytes(id_td_qe_0)));
        bytes32 contentHash0 = enclaveIdDao.getIdentityContentHash(key);

        vm.warp(1739396400);
        enclaveIdDao.upsertEnclaveIdentity(id, version, idObj1);
        bytes32 collateralHash1 = enclaveIdDao.getCollateralHash(key);
        assertEq(collateralHash1, sha256(bytes(id_td_qe_1)));
        bytes32 contentHash1 = enclaveIdDao.getIdentityContentHash(key);

        assertFalse(collateralHash0 == collateralHash1);
        assertEq(contentHash0, contentHash1);
    }

    function testTcbIssuerChain() public readAsAuthorizedCaller {
        (bytes memory fetchedSigning, bytes memory fetchedRoot) = enclaveIdDao.getEnclaveIdentityIssuerChain();
        assertEq(keccak256(signingDer), keccak256(fetchedSigning));
        assertEq(keccak256(rootDer), keccak256(fetchedRoot));
    }
}
