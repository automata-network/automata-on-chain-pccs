// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../VeraxTestBase.t.sol";
import {PcsDaoPortal} from "../../src/verax/portals/PcsDaoPortal.sol";
import {PCSConstants} from "./PCSConstants.t.sol";
import {CA} from "../../src/Common.sol";

import {Attestation} from "@consensys/linea-attestation-registry-contracts/types/Structs.sol";

import "forge-std/console.sol";

abstract contract VeraxPcsSetupBase is VeraxTestBase, PCSConstants {
    PcsDaoPortal pcs;
    bytes32 rootAttestation;
    bytes32 rootCrlAttestation;
    bytes32 signingAttestation;
    bytes32 platformAttestation;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(admin);
        // Set Up PCSDaoPortal
        address[] memory blank;
        pcs = new PcsDaoPortal(blank, address(router), address(x509Lib), address(x509CrlLib));

        // register the portal
        portalRegistry.register(
            address(pcs),
            "Intel On Chain PCS Data Access Object Portal", // name
            "some-description", // description
            true, // isRevocable
            "some-owner" // ownerName
        );
        vm.stopPrank();

        // insert root CA
        rootAttestation = pcs.upsertPcsCertificates(CA.ROOT, rootDer);

        // // insert root CRL
        // rootCrlAttestation = pcs.upsertRootCACrl(rootCrlDer);

        // insert Signing CA
        signingAttestation = pcs.upsertPcsCertificates(CA.SIGNING, signingDer);

        // insert Platform CA
        platformAttestation = pcs.upsertPcsCertificates(CA.PLATFORM, platformDer);
    }

    function testPcsSetup() public {
        assertTrue(portalRegistry.isRegistered(address(pcs)));

        // validate RootCA attestations
        assertTrue(attestationRegistry.isRegistered(rootAttestation));
        Attestation memory rootCaAttestation = attestationRegistry.getAttestation(rootAttestation);
        bytes32 expectedHash = keccak256(rootDer);
        bytes32 actualHash = keccak256(rootCaAttestation.attestationData);
        assertEq(actualHash, expectedHash);

        // // validate RootCA attestations
        // assertTrue(attestationRegistry.isRegistered(rootCrlAttestation));
        // Attestation memory rootCrl = attestationRegistry.getAttestation(rootCrlAttestation);
        // expectedHash = keccak256(rootCrlDer);
        // actualHash = keccak256(rootCrl.attestationData);
        // assertEq(actualHash, expectedHash);

        // validate SigningCA attestations
        assertTrue(attestationRegistry.isRegistered(signingAttestation));
        Attestation memory signingCaAttestation = attestationRegistry.getAttestation(signingAttestation);
        expectedHash = keccak256(signingDer);
        actualHash = keccak256(signingCaAttestation.attestationData);
        assertEq(actualHash, expectedHash);

        // validate PlatformCA attestations
        assertTrue(attestationRegistry.isRegistered(platformAttestation));
        Attestation memory platformCaAttestation = attestationRegistry.getAttestation(platformAttestation);
        expectedHash = keccak256(platformDer);
        actualHash = keccak256(platformCaAttestation.attestationData);
        assertEq(actualHash, expectedHash);
    }
}
