// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../pcs/PCSSetupBase.t.sol";
import {AutomataPckDao} from "../../src/automata_pccs/AutomataPckDao.sol";

contract AutomataPckDaoTest is PCSSetupBase {
    // TEMP: placeholder only, circle back on this to verify the inputs
    string constant qeid = "ad04024c9dfb382baf51ca3e5d6cb6e6";
    string constant pceid = "0000";
    string constant tcbm = "0c0c0303ffff010000000000000000000d00";
    string constant cpusvn = "0c0c100fffff01000000000000000000";
    string constant pcesvn = "0e00";

    bytes32 pckAttestationId;
    bytes32 tcbmAttestationId;

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);

        pckAttestationId = pck.upsertPckCert(CA.PLATFORM, qeid, pceid, tcbm, pckDer);
        tcbmAttestationId = pck.upsertPlatformTcbs(qeid, pceid, cpusvn, pcesvn, tcbm);

        vm.stopPrank();
    }

    function testGetCert() public {
        bytes memory fetchedCert = pck.getCert(qeid, cpusvn, pcesvn, pceid);
        bytes32 fetchedCollateralHash = pck.getCollateralHash(pckAttestationId);
        (bytes memory tbs,) = x509Lib.getTbsAndSig(pckDer);
        assertEq(fetchedCollateralHash, keccak256(tbs));
        assertEq(keccak256(fetchedCert), keccak256(pckDer));

        (string[] memory tcbms, bytes[] memory certs) = pck.getCerts(qeid, pceid);

        assertEq(keccak256(bytes(tcbms[0])), keccak256(bytes(tcbm)));
        assertEq(keccak256(certs[0]), keccak256(pckDer));
    }

    function testGetPlatformTcb() public {
        string memory fetchedTcbm = pck.getPlatformTcbByIdAndSvns(qeid, pceid, cpusvn, pcesvn);
        assertEq(keccak256(bytes(fetchedTcbm)), keccak256(bytes(tcbm)));
    }

    function testPckIssuerChain() public {
        (bytes memory intermediateCert, bytes memory rootCert) = pck.getPckCertChain(CA.PLATFORM);
        assertEq(keccak256(platformDer), keccak256(intermediateCert));
        assertEq(keccak256(rootDer), keccak256(rootCert));
    }
}
