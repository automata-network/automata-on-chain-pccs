// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../pcs/PCSSetupBase.t.sol";
import {TCBConstants} from "./TCBConstants.t.sol";
import {DaoBase} from "../../src/bases/DaoBase.sol";
import {AutomataFmspcTcbDaoVersioned} from "../../src/automata_pccs/versioned/AutomataFmspcTcbDaoVersioned.sol";

contract AutomataFmspcTcbDaoVersionedTest is PCSSetupBase, TCBConstants {

    bytes32 existingAttestationId;
    AutomataFmspcTcbDaoVersioned fmspcTcbDaoVersioned;
    address user = address(0x69);

    function setUp() public override {
        super.setUp();

        TcbInfoJsonObj memory tcbInfoObj =
            TcbInfoJsonObj({tcbInfoStr: string(sgx_v2_tcbStr), signature: sgx_v2_signature});

        existingAttestationId = fmspcTcbDao.upsertFmspcTcb(tcbInfoObj);

        vm.warp(1748939700); // pinned June 3rd, 2025, 8:35am GMT

        // replace TCB Signing CA
        bytes memory signing = hex"3082028d30820232a00302010202147e3882d5fb55294a40498e458403e91491bdf455300a06082a8648ce3d0403023068311a301806035504030c11496e74656c2053475820526f6f74204341311a3018060355040a0c11496e74656c20436f72706f726174696f6e3114301206035504070c0b53616e746120436c617261310b300906035504080c024341310b3009060355040613025553301e170d3235303530363039323530305a170d3332303530363039323530305a306c311e301c06035504030c15496e74656c2053475820544342205369676e696e67311a3018060355040a0c11496e74656c20436f72706f726174696f6e3114301206035504070c0b53616e746120436c617261310b300906035504080c024341310b30090603550406130255533059301306072a8648ce3d020106082a8648ce3d0301070342000443451bcc73c9d5917caf766e61af3fe98087dd4f13257b261e851897799dd13d6811fb47713803bb9bae587fccddc2e31be9a28b86962acc6daf96da58eeca96a381b53081b2301f0603551d2304183016801422650cd65a9d3489f383b49552bf501b392706ac30520603551d1f044b30493047a045a043864168747470733a2f2f6365727469666963617465732e7472757374656473657276696365732e696e74656c2e636f6d2f496e74656c534758526f6f7443412e646572301d0603551d0e041604147e3882d5fb55294a40498e458403e91491bdf455300e0603551d0f0101ff0404030206c0300c0603551d130101ff04023000300a06082a8648ce3d0403020349003046022100dd9a646e028dea08ef130b522824c213028384c38765804047cd2cf54ee3124c022100a553a8e92de7df9ca343b79b7842fafe456f4d058d859c81ebb71228ce50ba39";
        pcs.upsertPcsCertificates(CA.SIGNING, signing);
    
        fmspcTcbDaoVersioned = new AutomataFmspcTcbDaoVersioned(
            address(pccsStorage),
            P256_VERIFIER,
            address(pcs),
            address(fmspcTcbLib),
            address(x509Lib),
            address(x509CrlLib),
            admin,
            19 // TCB_EVALUATION_NUMBER
        );

        vm.startPrank(admin);

        pccsStorage.grantDao(address(fmspcTcbDaoVersioned));

        fmspcTcbDaoVersioned.grantRoles(
            user, fmspcTcbDaoVersioned.ATTESTER_ROLE()
        );

        vm.stopPrank();
    }

    function test_FmspcTcbVersionedWithSGX() public {
        string memory tcbInfoStr = "{\"version\":2,\"issueDate\":\"2025-06-03T07:32:24Z\",\"nextUpdate\":\"2025-07-03T07:32:24Z\",\"fmspc\":\"00A067110000\",\"pceId\":\"0000\",\"tcbType\":0,\"tcbEvaluationDataNumber\":19,\"tcbLevels\":[{\"tcb\":{\"sgxtcbcomp01svn\":13,\"sgxtcbcomp02svn\":13,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":12,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":13},\"tcbDate\":\"2025-05-14T00:00:00Z\",\"tcbStatus\":\"SWHardeningNeeded\"},{\"tcb\":{\"sgxtcbcomp01svn\":13,\"sgxtcbcomp02svn\":13,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":0,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":13},\"tcbDate\":\"2025-05-14T00:00:00Z\",\"tcbStatus\":\"ConfigurationAndSWHardeningNeeded\"},{\"tcb\":{\"sgxtcbcomp01svn\":11,\"sgxtcbcomp02svn\":11,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":12,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":13},\"tcbDate\":\"2024-11-13T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"sgxtcbcomp01svn\":11,\"sgxtcbcomp02svn\":11,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":0,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":13},\"tcbDate\":\"2024-11-13T00:00:00Z\",\"tcbStatus\":\"OutOfDateConfigurationNeeded\"},{\"tcb\":{\"sgxtcbcomp01svn\":10,\"sgxtcbcomp02svn\":10,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":12,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":13},\"tcbDate\":\"2023-02-15T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"sgxtcbcomp01svn\":10,\"sgxtcbcomp02svn\":10,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":0,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":13},\"tcbDate\":\"2023-02-15T00:00:00Z\",\"tcbStatus\":\"OutOfDateConfigurationNeeded\"},{\"tcb\":{\"sgxtcbcomp01svn\":9,\"sgxtcbcomp02svn\":9,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":12,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":13},\"tcbDate\":\"2022-11-09T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"sgxtcbcomp01svn\":9,\"sgxtcbcomp02svn\":9,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":0,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":13},\"tcbDate\":\"2022-11-09T00:00:00Z\",\"tcbStatus\":\"OutOfDateConfigurationNeeded\"},{\"tcb\":{\"sgxtcbcomp01svn\":5,\"sgxtcbcomp02svn\":5,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":4,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":11},\"tcbDate\":\"2021-11-10T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"sgxtcbcomp01svn\":5,\"sgxtcbcomp02svn\":5,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":4,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":10},\"tcbDate\":\"2020-11-11T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"sgxtcbcomp01svn\":5,\"sgxtcbcomp02svn\":5,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":0,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":11},\"tcbDate\":\"2021-11-10T00:00:00Z\",\"tcbStatus\":\"OutOfDateConfigurationNeeded\"},{\"tcb\":{\"sgxtcbcomp01svn\":5,\"sgxtcbcomp02svn\":5,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":0,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":10},\"tcbDate\":\"2020-11-11T00:00:00Z\",\"tcbStatus\":\"OutOfDateConfigurationNeeded\"},{\"tcb\":{\"sgxtcbcomp01svn\":5,\"sgxtcbcomp02svn\":5,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":0,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":5},\"tcbDate\":\"2018-01-04T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"}]}";
        bytes memory sig = hex"827fd577ed3abf8c5566306ae06ca1ce33ef9b16259dc1e3f87b7ee381f77d73b874b6bf38ef82199b8f266d6aeb01adcf28318fecb153f01931becb88b61561";

        TcbInfoJsonObj memory tcbInfoObj =
            TcbInfoJsonObj({tcbInfoStr: tcbInfoStr, signature: sig});

        vm.expectRevert(0x82b42900); // Unauthorized()
        fmspcTcbDaoVersioned.upsertFmspcTcb(tcbInfoObj);

        vm.prank(user);
        bytes32 attestationId = fmspcTcbDaoVersioned.upsertFmspcTcb(tcbInfoObj);
        assertTrue(attestationId != existingAttestationId);

        vm.startPrank(admin);

        TcbInfoJsonObj memory fetchedTcbInfoObjFromVersioned =
            fmspcTcbDaoVersioned.getTcbInfo(0, "00A067110000", 2);

        assertEq(fetchedTcbInfoObjFromVersioned.tcbInfoStr, tcbInfoStr);
        assertEq(fetchedTcbInfoObjFromVersioned.signature, sig);

        TcbInfoJsonObj memory fetchedTcbInfoObjFromCommunity =
            fmspcTcbDao.getTcbInfo(0, "00A067110000", 2);

        assertNotEq(
            fetchedTcbInfoObjFromCommunity.tcbInfoStr,
            tcbInfoStr
        ); // should not be the same as the versioned one
        assertNotEq0(
            fetchedTcbInfoObjFromCommunity.signature,
            sig
        );

        vm.stopPrank();
    }
    
    function test_FmspcTcbIncorrectEvaluationNumber() public {
        string memory tcbInfoStr = "{\"version\":2,\"issueDate\":\"2025-06-03T08:00:18Z\",\"nextUpdate\":\"2025-07-03T08:00:18Z\",\"fmspc\":\"00A067110000\",\"pceId\":\"0000\",\"tcbType\":0,\"tcbEvaluationDataNumber\":17,\"tcbLevels\":[{\"tcb\":{\"sgxtcbcomp01svn\":11,\"sgxtcbcomp02svn\":11,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":12,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":13},\"tcbDate\":\"2024-03-13T00:00:00Z\",\"tcbStatus\":\"SWHardeningNeeded\"},{\"tcb\":{\"sgxtcbcomp01svn\":11,\"sgxtcbcomp02svn\":11,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":0,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":13},\"tcbDate\":\"2024-03-13T00:00:00Z\",\"tcbStatus\":\"ConfigurationAndSWHardeningNeeded\"},{\"tcb\":{\"sgxtcbcomp01svn\":10,\"sgxtcbcomp02svn\":10,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":12,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":13},\"tcbDate\":\"2023-02-15T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"sgxtcbcomp01svn\":10,\"sgxtcbcomp02svn\":10,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":0,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":13},\"tcbDate\":\"2023-02-15T00:00:00Z\",\"tcbStatus\":\"OutOfDateConfigurationNeeded\"},{\"tcb\":{\"sgxtcbcomp01svn\":9,\"sgxtcbcomp02svn\":9,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":12,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":13},\"tcbDate\":\"2022-11-09T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"sgxtcbcomp01svn\":9,\"sgxtcbcomp02svn\":9,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":0,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":13},\"tcbDate\":\"2022-11-09T00:00:00Z\",\"tcbStatus\":\"OutOfDateConfigurationNeeded\"},{\"tcb\":{\"sgxtcbcomp01svn\":5,\"sgxtcbcomp02svn\":5,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":4,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":11},\"tcbDate\":\"2021-11-10T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"sgxtcbcomp01svn\":5,\"sgxtcbcomp02svn\":5,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":4,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":10},\"tcbDate\":\"2020-11-11T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"sgxtcbcomp01svn\":5,\"sgxtcbcomp02svn\":5,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":0,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":11},\"tcbDate\":\"2021-11-10T00:00:00Z\",\"tcbStatus\":\"OutOfDateConfigurationNeeded\"},{\"tcb\":{\"sgxtcbcomp01svn\":5,\"sgxtcbcomp02svn\":5,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":0,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":10},\"tcbDate\":\"2020-11-11T00:00:00Z\",\"tcbStatus\":\"OutOfDateConfigurationNeeded\"},{\"tcb\":{\"sgxtcbcomp01svn\":5,\"sgxtcbcomp02svn\":5,\"sgxtcbcomp03svn\":2,\"sgxtcbcomp04svn\":2,\"sgxtcbcomp05svn\":255,\"sgxtcbcomp06svn\":1,\"sgxtcbcomp07svn\":0,\"sgxtcbcomp08svn\":0,\"sgxtcbcomp09svn\":0,\"sgxtcbcomp10svn\":0,\"sgxtcbcomp11svn\":0,\"sgxtcbcomp12svn\":0,\"sgxtcbcomp13svn\":0,\"sgxtcbcomp14svn\":0,\"sgxtcbcomp15svn\":0,\"sgxtcbcomp16svn\":0,\"pcesvn\":5},\"tcbDate\":\"2018-01-04T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"}]}";
        bytes memory sig = hex"89a37db30d8dbfbe7baff66827b8ced0080a8e32d1c288648b968a3f1277f587e11595451f2cc3ac5751cc764ea3d2399aa9a28e5a8d5867b6a2384967368352";

        TcbInfoJsonObj memory tcbInfoObj =
            TcbInfoJsonObj({tcbInfoStr: tcbInfoStr, signature: sig});

        vm.prank(user);
        vm.expectRevert(AutomataFmspcTcbDaoVersioned.Invalid_Tcb_Evaluation_Data_Number.selector);
        fmspcTcbDaoVersioned.upsertFmspcTcb(tcbInfoObj);
    }
}