// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../pcs/PCSSetupBase.t.sol";
import {AutomataTcbEvalDao} from "../../src/automata_pccs/AutomataTcbEvalDao.sol";
import "src/helpers/TcbEvalHelper.sol";

contract AutomataTcbEvalDaoTest is PCSSetupBase {
    AutomataTcbEvalDao public tcbEvalDao;
    TcbEvalHelper public tcbEvalHelper;

    function setUp() public override {
        super.setUp();

        tcbEvalHelper = new TcbEvalHelper();

        tcbEvalDao = new AutomataTcbEvalDao(
            address(pccsStorage),
            P256_VERIFIER,
            address(pcs),
            address(tcbEvalHelper),
            address(x509Lib),
            address(x509CrlLib)
        );

        vm.warp(1748832300); // June 2nd, 2025, 02:45:00 GMT

        bytes memory signing = hex"3082028d30820232a00302010202147e3882d5fb55294a40498e458403e91491bdf455300a06082a8648ce3d0403023068311a301806035504030c11496e74656c2053475820526f6f74204341311a3018060355040a0c11496e74656c20436f72706f726174696f6e3114301206035504070c0b53616e746120436c617261310b300906035504080c024341310b3009060355040613025553301e170d3235303530363039323530305a170d3332303530363039323530305a306c311e301c06035504030c15496e74656c2053475820544342205369676e696e67311a3018060355040a0c11496e74656c20436f72706f726174696f6e3114301206035504070c0b53616e746120436c617261310b300906035504080c024341310b30090603550406130255533059301306072a8648ce3d020106082a8648ce3d0301070342000443451bcc73c9d5917caf766e61af3fe98087dd4f13257b261e851897799dd13d6811fb47713803bb9bae587fccddc2e31be9a28b86962acc6daf96da58eeca96a381b53081b2301f0603551d2304183016801422650cd65a9d3489f383b49552bf501b392706ac30520603551d1f044b30493047a045a043864168747470733a2f2f6365727469666963617465732e7472757374656473657276696365732e696e74656c2e636f6d2f496e74656c534758526f6f7443412e646572301d0603551d0e041604147e3882d5fb55294a40498e458403e91491bdf455300e0603551d0f0101ff0404030206c0300c0603551d130101ff04023000300a06082a8648ce3d0403020349003046022100dd9a646e028dea08ef130b522824c213028384c38765804047cd2cf54ee3124c022100a553a8e92de7df9ca343b79b7842fafe456f4d058d859c81ebb71228ce50ba39";
        pcs.upsertPcsCertificates(CA.SIGNING, signing);

        vm.prank(admin);
        pccsStorage.grantDao(address(tcbEvalDao));
    }

    function testUpsertTcbEvaluationDataNumbers() public {
        string memory tcbEvaluationDataStr = "{\"id\":\"SGX\",\"version\":1,\"issueDate\":\"2025-06-02T02:43:30Z\",\"nextUpdate\":\"2025-07-02T02:43:30Z\",\"tcbEvalNumbers\":[{\"tcbEvaluationDataNumber\":19,\"tcbRecoveryEventDate\":\"2025-05-13T00:00:00Z\",\"tcbDate\":\"2025-05-14T00:00:00Z\"},{\"tcbEvaluationDataNumber\":18,\"tcbRecoveryEventDate\":\"2024-11-12T00:00:00Z\",\"tcbDate\":\"2024-11-13T00:00:00Z\"},{\"tcbEvaluationDataNumber\":17,\"tcbRecoveryEventDate\":\"2024-03-12T00:00:00Z\",\"tcbDate\":\"2024-03-13T00:00:00Z\"}]}";
        bytes memory sig = hex"a74e6819789f232632ddacd0857f6bebe6e8d4fc93a6ad34188d6d601aa24adcedb1547feca0ce10b1d4c096e9c66207eda65fbb4ef7d41542dfa21704b6099a";

        TcbEvalJsonObj memory tcbEvalJsonObj = TcbEvalJsonObj({
            tcbEvaluationDataNumbers: tcbEvaluationDataStr,
            signature: sig
        });

        bytes32 attestationId = tcbEvalDao.upsertTcbEvaluationData(tcbEvalJsonObj);
        assertEq(
            pccsStorage.collateralPointer(tcbEvalDao.TCB_EVAL_KEY(TcbId.SGX)),
            attestationId
        );

        vm.startPrank(admin);
        
        TcbEvalJsonObj memory fetched = tcbEvalDao.getTcbEvaluationObject(TcbId.SGX);
        assertEq(fetched.tcbEvaluationDataNumbers, tcbEvalJsonObj.tcbEvaluationDataNumbers);
        assertEq(fetched.signature, tcbEvalJsonObj.signature);


        // test loading all tcb evaluation numbers
        uint256[] memory tcbEvalNumbers = tcbEvalDao.getTcbEvaluationDataNumbers(TcbId.SGX);
        assertEq(tcbEvalNumbers.length, 3);
        assertEq(tcbEvalNumbers[0], 19);
        assertEq(tcbEvalNumbers[1], 18);
        assertEq(tcbEvalNumbers[2], 17);

        // test early
        uint32 earlyTcbEvaluation = tcbEvalDao.early(TcbId.SGX);
        assertEq(earlyTcbEvaluation, 19);

        // test standard
        uint32 standardTcbEvaluation = tcbEvalDao.standard(TcbId.SGX);
        assertEq(standardTcbEvaluation, 17);
    }
}