// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/StdJson.sol";

import "../pcs/PCSSetupBase.t.sol";
import "./IdentityConstants.t.sol";
import {AutomataEnclaveIdentityDao} from "../../src/automata_pccs/AutomataEnclaveIdentityDao.sol";
import {AutomataEnclaveIdentityDaoVersioned} from "../../src/automata_pccs/versioned/AutomataEnclaveIdentityDaoVersioned.sol";
import {DaoBase} from "../../src/bases/DaoBase.sol";

contract AutomataEnclaveIdentityDaoVersionedTest is PCSSetupBase, IdentityConstants {
    
    bytes32 existingAttestationId;
    address user = address(0x69);
    AutomataEnclaveIdentityDaoVersioned enclaveIdDaoVersioned;

    function setUp() public override {
        super.setUp();

        // upsert an existing enclave identity to the community maintained dao
        EnclaveIdentityJsonObj memory enclaveIdentityObj =
            EnclaveIdentityJsonObj({identityStr: string(identityStr), signature: signature});

        existingAttestationId = enclaveIdDao.upsertEnclaveIdentity(0, 3, enclaveIdentityObj);

        vm.warp(1748939700); // pinned June 3rd, 2025, 8:35am GMT

        // replace TCB Signing CA
        bytes memory signing = hex"3082028d30820232a00302010202147e3882d5fb55294a40498e458403e91491bdf455300a06082a8648ce3d0403023068311a301806035504030c11496e74656c2053475820526f6f74204341311a3018060355040a0c11496e74656c20436f72706f726174696f6e3114301206035504070c0b53616e746120436c617261310b300906035504080c024341310b3009060355040613025553301e170d3235303530363039323530305a170d3332303530363039323530305a306c311e301c06035504030c15496e74656c2053475820544342205369676e696e67311a3018060355040a0c11496e74656c20436f72706f726174696f6e3114301206035504070c0b53616e746120436c617261310b300906035504080c024341310b30090603550406130255533059301306072a8648ce3d020106082a8648ce3d0301070342000443451bcc73c9d5917caf766e61af3fe98087dd4f13257b261e851897799dd13d6811fb47713803bb9bae587fccddc2e31be9a28b86962acc6daf96da58eeca96a381b53081b2301f0603551d2304183016801422650cd65a9d3489f383b49552bf501b392706ac30520603551d1f044b30493047a045a043864168747470733a2f2f6365727469666963617465732e7472757374656473657276696365732e696e74656c2e636f6d2f496e74656c534758526f6f7443412e646572301d0603551d0e041604147e3882d5fb55294a40498e458403e91491bdf455300e0603551d0f0101ff0404030206c0300c0603551d130101ff04023000300a06082a8648ce3d0403020349003046022100dd9a646e028dea08ef130b522824c213028384c38765804047cd2cf54ee3124c022100a553a8e92de7df9ca343b79b7842fafe456f4d058d859c81ebb71228ce50ba39";
        pcs.upsertPcsCertificates(CA.SIGNING, signing);

        enclaveIdDaoVersioned =
            new AutomataEnclaveIdentityDaoVersioned(
                address(pccsStorage),
                P256_VERIFIER,
                address(pcs),
                address(enclaveIdentityLib),
                address(x509Lib),
                address(x509CrlLib),
                admin,
                19 // TCB_EVALUATION_NUMBER
            );

        vm.startPrank(admin);

        // grant versioned dao access to the storage
        pccsStorage.grantDao(address(enclaveIdDaoVersioned));

        // grant ATTESTATION_ROLE to the user
        enclaveIdDaoVersioned.grantRoles(
            user, enclaveIdDaoVersioned.ATTESTER_ROLE()
        );

        vm.stopPrank();
    }

    function test_EnclaveIdentityVersioned() public {
        string memory identity = "{\"id\":\"QE\",\"version\":2,\"issueDate\":\"2025-06-03T05:48:09Z\",\"nextUpdate\":\"2025-07-03T05:48:09Z\",\"tcbEvaluationDataNumber\":19,\"miscselect\":\"00000000\",\"miscselectMask\":\"FFFFFFFF\",\"attributes\":\"11000000000000000000000000000000\",\"attributesMask\":\"FBFFFFFFFFFFFFFF0000000000000000\",\"mrsigner\":\"8C4F5775D796503E96137F77C68A829A0056AC8DED70140B081B094490C57BFF\",\"isvprodid\":1,\"tcbLevels\":[{\"tcb\":{\"isvsvn\":8},\"tcbDate\":\"2025-05-14T00:00:00Z\",\"tcbStatus\":\"UpToDate\"},{\"tcb\":{\"isvsvn\":6},\"tcbDate\":\"2021-11-10T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"isvsvn\":5},\"tcbDate\":\"2020-11-11T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"isvsvn\":4},\"tcbDate\":\"2019-11-13T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"isvsvn\":2},\"tcbDate\":\"2019-05-15T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"isvsvn\":1},\"tcbDate\":\"2018-08-15T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"}]}";
        bytes memory sig = hex"5e40bbdd933db575c9ed65cd0432817e8334732ecd72acaa2b0031a07fecdc629310c8125e76c3157cfb2609eeb8b2e74913492fdffbb174e602756a030f6874";

        EnclaveIdentityJsonObj memory enclaveIdentityObj =
            EnclaveIdentityJsonObj({identityStr: identity, signature: sig});

        // upsert an enclave identity to the versioned dao
        vm.expectRevert(0x82b42900); // Unauthorized()
        enclaveIdDaoVersioned.upsertEnclaveIdentity(
            0, 3, enclaveIdentityObj
        );

        vm.prank(user);
        bytes32 attestationId = enclaveIdDaoVersioned.upsertEnclaveIdentity(
            0, 3, enclaveIdentityObj
        );

        assertTrue(attestationId != existingAttestationId);

        vm.prank(admin);
        EnclaveIdentityJsonObj memory retrievedEnclaveIdentityObjFromVersioned =
            enclaveIdDaoVersioned.getEnclaveIdentity(0, 3);
        assertEq(
            retrievedEnclaveIdentityObjFromVersioned.identityStr,
            identity,
            "Retrieved identity string does not match the expected value"
        );
        assertEq(
            retrievedEnclaveIdentityObjFromVersioned.signature,
            sig,
            "Retrieved signature does not match the expected value"
        );

        vm.prank(admin);
        // it should not override collaterals maintained by the community dao
        EnclaveIdentityJsonObj memory retrievedEnclaveIdentityObjFromCommunity =
            enclaveIdDao.getEnclaveIdentity(0, 3);

        assertNotEq(
            retrievedEnclaveIdentityObjFromCommunity.identityStr,
            identity,
            "Retrieved identity string from community dao should not match the versioned dao"
        );
        assertNotEq0(
            retrievedEnclaveIdentityObjFromCommunity.signature,
            sig,
            "Retrieved signature from community dao should not match the versioned dao"
        );
    }

    function test_EnclaveIdIncorrectEvaluationNumber() public {
        string memory identity = "{\"id\":\"QE\",\"version\":2,\"issueDate\":\"2025-06-03T07:45:17Z\",\"nextUpdate\":\"2025-07-03T07:45:17Z\",\"tcbEvaluationDataNumber\":17,\"miscselect\":\"00000000\",\"miscselectMask\":\"FFFFFFFF\",\"attributes\":\"11000000000000000000000000000000\",\"attributesMask\":\"FBFFFFFFFFFFFFFF0000000000000000\",\"mrsigner\":\"8C4F5775D796503E96137F77C68A829A0056AC8DED70140B081B094490C57BFF\",\"isvprodid\":1,\"tcbLevels\":[{\"tcb\":{\"isvsvn\":8},\"tcbDate\":\"2024-03-13T00:00:00Z\",\"tcbStatus\":\"UpToDate\"},{\"tcb\":{\"isvsvn\":6},\"tcbDate\":\"2021-11-10T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"isvsvn\":5},\"tcbDate\":\"2020-11-11T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"isvsvn\":4},\"tcbDate\":\"2019-11-13T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"isvsvn\":2},\"tcbDate\":\"2019-05-15T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"isvsvn\":1},\"tcbDate\":\"2018-08-15T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"}]}";
        bytes memory sig = hex"bdf3163e4f35870d8a1ed3e9bff8e9ddc53da6dd15d35ccade5e53ff20708dc9d271445958af9d7b02ae5022215122d40d7ea6741d67c31dd0a931e93569ef48";

        EnclaveIdentityJsonObj memory enclaveIdentityObj =
            EnclaveIdentityJsonObj({identityStr: identity, signature: sig});

        vm.prank(user);
        vm.expectRevert(AutomataEnclaveIdentityDaoVersioned.Invalid_Tcb_Evaluation_Data_Number.selector);
        enclaveIdDaoVersioned.upsertEnclaveIdentity(
            0, 20, enclaveIdentityObj
        );
    }
}
