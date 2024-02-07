// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./VeraxPcsSetupBase.t.sol";
import {PckDaoPortal} from "../../src/verax/portals/PckDaoPortal.sol";

contract VeraxPckPortalTest is VeraxPcsSetupBase {
    PckDaoPortal pckPortal;

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

        address[] memory blank;
        pckPortal = new PckDaoPortal(blank, address(router), address(pcs), address(x509Lib), address(x509CrlLib));

        // register the portal
        portalRegistry.register(
            address(pckPortal),
            "Intel On Chain PCK and Platform TCBs Data Access Object Portal", // name
            "some-description", // description
            true, // isRevocable
            "some-owner" // ownerName
        );
        pckAttestationId = pckPortal.upsertPckCert(CA.PLATFORM, qeid, pceid, tcbm, pckDer);
        tcbmAttestationId = pckPortal.upsertPlatformTcbs(qeid, pceid, cpusvn, pcesvn, tcbm);

        vm.stopPrank();
    }

    function testPckAndTcbmAttestations() public {
        assertTrue(attestationRegistry.isRegistered(pckAttestationId));
        assertTrue(attestationRegistry.isRegistered(tcbmAttestationId));
    }

    function testGetCert() public {
        bytes memory fetchedCert = pckPortal.getCert(qeid, cpusvn, pcesvn, pceid);
        assertEq(keccak256(fetchedCert), keccak256(pckDer));

        (string[] memory tcbms, bytes[] memory certs) = pckPortal.getCerts(qeid, pceid);

        assertEq(keccak256(bytes(tcbms[0])), keccak256(bytes(tcbm)));
        assertEq(keccak256(certs[0]), keccak256(pckDer));
    }

    function testGetPlatformTcb() public {
        string memory fetchedTcbm = pckPortal.getPlatformTcbByIdAndSvns(qeid, pceid, cpusvn, pcesvn);
        assertEq(keccak256(bytes(fetchedTcbm)), keccak256(bytes(tcbm)));
    }

    function testPckIssuerChain() public {
        (bytes memory intermediateCert, bytes memory rootCert) = pckPortal.getPckCertChain(CA.PLATFORM);
        assertEq(keccak256(platformDer), keccak256(intermediateCert));
        assertEq(keccak256(rootDer), keccak256(rootCert));
    }
}
