// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./VeraxPcsSetupBase.t.sol";
import {PckDaoPortal} from "../../src/verax/portals/PckDaoPortal.sol";

contract VeraxPckPortalTest is VeraxPcsSetupBase {
    PckDaoPortal pckPortal;

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);

        address[] memory blank;
        pckPortal = new PckDaoPortal(blank, address(router), address(pcs), address(x509Lib), address(x509CrlLib));

        // register the portal
        portalRegistry.register(
            address(pckPortal),
            "Intel On Chain PCK Data Access Object Portal", // name
            "some-description", // description
            true, // isRevocable
            "some-owner" // ownerName
        );

        vm.stopPrank();
    }

    function testAttestPck() public {
        // TEMP: placeholder only, circle back on this to verify the inputs
        string memory qeid = "";
        string memory pceid = "0000";
        string memory cpusvn = "";
        string memory pcesvn = "";

        bytes32 pckAttestationId = pckPortal.upsertPckCert(CA.PLATFORM, qeid, pceid, cpusvn, pcesvn, pckDer);

        assertTrue(attestationRegistry.isRegistered(pckAttestationId));

        bytes memory fetched = pckPortal.getCert(qeid, pceid, cpusvn, pcesvn);
        assertEq(keccak256(pckDer), keccak256(fetched));
    }

    function testPckIssuerChain() public {
        (bytes memory intermediateCert, bytes memory rootCert) = pckPortal.getPckCertChain(CA.PLATFORM);
        assertEq(keccak256(platformDer), keccak256(intermediateCert));
        assertEq(keccak256(rootDer), keccak256(rootCert));
    }
}
