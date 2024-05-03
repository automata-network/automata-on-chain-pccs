// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../VeraxTestBase.t.sol";
import {PCSConstants} from "./PCSConstants.t.sol";

import {PcsDaoPortal} from "../../src/verax/portals/PcsDaoPortal.sol";
import {CA} from "../../src/Common.sol";

import {Attestation} from "@consensys/linea-attestation-registry-contracts/types/Structs.sol";

import "forge-std/console.sol";

abstract contract VeraxPcsSetupBase is VeraxTestBase, PCSConstants {
    PcsDaoPortal pcs;
    bytes32 rootAttestation;
    bytes32 rootCrlAttestation;
    bytes32 signingAttestation;
    bytes32 platformAttestation;
    bytes32 platformCrlAttestation;

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

        // insert root CRL
        rootCrlAttestation = pcs.upsertRootCACrl(rootCrlDer);

        // insert Signing CA
        signingAttestation = pcs.upsertPcsCertificates(CA.SIGNING, signingDer);

        // insert Platform CA
        platformAttestation = pcs.upsertPcsCertificates(CA.PLATFORM, platformDer);

        // insert PCK CRL
        platformCrlAttestation = pcs.upsertPckCrl(CA.PLATFORM, pckCrlDer);
    }

    function testPcsSetup() public {
        assertTrue(portalRegistry.isRegistered(address(pcs)));
        bytes memory tbs;

        // validate RootCA attestations
        (tbs,) = x509Lib.getTbsAndSig(rootDer);
        assertTrue(attestationRegistry.isRegistered(rootAttestation));
        Attestation memory rootCaAttestation = attestationRegistry.getAttestation(rootAttestation);
        bytes32 expectedHash = keccak256(abi.encode(keccak256(tbs), rootDer));
        bytes32 actualHash = keccak256(rootCaAttestation.attestationData);
        assertEq(actualHash, expectedHash);


        // validate RootCA attestations
        (tbs,) = x509CrlLib.getTbsAndSig(rootCrlDer);
        assertTrue(attestationRegistry.isRegistered(rootCrlAttestation));
        Attestation memory rootCrl = attestationRegistry.getAttestation(rootCrlAttestation);
        expectedHash = keccak256(abi.encode(keccak256(tbs), rootCrlDer));
        actualHash = keccak256(rootCrl.attestationData);
        assertEq(actualHash, expectedHash);

        // validate SigningCA attestations
        (tbs,) = x509Lib.getTbsAndSig(signingDer);
        assertTrue(attestationRegistry.isRegistered(signingAttestation));
        Attestation memory signingCaAttestation = attestationRegistry.getAttestation(signingAttestation);
        expectedHash = keccak256(abi.encode(keccak256(tbs), signingDer));
        actualHash = keccak256(signingCaAttestation.attestationData);
        assertEq(actualHash, expectedHash);

        // validate PlatformCA attestations
        (tbs,) = x509Lib.getTbsAndSig(platformDer);
        assertTrue(attestationRegistry.isRegistered(platformAttestation));
        Attestation memory platformCaAttestation = attestationRegistry.getAttestation(platformAttestation);
        expectedHash = keccak256(abi.encode(keccak256(tbs), platformDer));
        actualHash = keccak256(platformCaAttestation.attestationData);
        assertEq(actualHash, expectedHash);

        // validate PlatformCRL attestations
        (tbs,) = x509CrlLib.getTbsAndSig(pckCrlDer);
        assertTrue(attestationRegistry.isRegistered(platformCrlAttestation));
        Attestation memory platformCrl = attestationRegistry.getAttestation(platformCrlAttestation);
        expectedHash = keccak256(abi.encode(keccak256(tbs), pckCrlDer));
        actualHash = keccak256(platformCrl.attestationData);
        assertEq(actualHash, expectedHash);
    }
}
