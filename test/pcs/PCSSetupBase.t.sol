// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../TestSetupBase.t.sol";

import {PCSConstants} from "./PCSConstants.t.sol";
import {CA} from "../../src/Common.sol";

abstract contract PCSSetupBase is TestSetupBase, PCSConstants {
    bytes32 rootAttestation;
    bytes32 rootCrlAttestation;
    bytes32 signingAttestation;
    bytes32 platformAttestation;
    bytes32 platformCrlAttestation;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(admin);

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

        vm.stopPrank();
    }

    function testPcsSetup() public {
        // validate RootCA attestations
        bytes memory attestedData = pcs.getAttestedData(rootAttestation);
        bytes32 collateralHash = pcs.getCollateralHash(rootAttestation);

        (bytes memory tbs,) = x509Lib.getTbsAndSig(rootDer);
        bytes32 actualHash = keccak256(tbs);
        assertEq(actualHash, collateralHash);
        assertEq(keccak256(attestedData), keccak256(rootDer));

        // validate RootCRL attestations
        attestedData = pcs.getAttestedData(rootCrlAttestation);
        collateralHash = pcs.getCollateralHash(rootCrlAttestation);
        (tbs,) = x509CrlLib.getTbsAndSig(rootCrlDer);
        actualHash = keccak256(tbs);
        assertEq(actualHash, collateralHash);
        assertEq(keccak256(attestedData), keccak256(rootCrlDer));

        // validate SigningCA attestations
        attestedData = pcs.getAttestedData(signingAttestation);
        collateralHash = pcs.getCollateralHash(signingAttestation);
        (tbs,) = x509CrlLib.getTbsAndSig(signingDer);
        actualHash = keccak256(tbs);
        assertEq(actualHash, collateralHash);
        assertEq(keccak256(attestedData), keccak256(signingDer));

        // validate PlatformCA attestations
        attestedData = pcs.getAttestedData(platformAttestation);
        collateralHash = pcs.getCollateralHash(platformAttestation);
        (tbs,) = x509CrlLib.getTbsAndSig(platformDer);
        actualHash = keccak256(tbs);
        assertEq(actualHash, collateralHash);
        assertEq(keccak256(attestedData), keccak256(platformDer));

        // validate PlatformCRL attestations
        attestedData = pcs.getAttestedData(platformCrlAttestation);
        collateralHash = pcs.getCollateralHash(platformCrlAttestation);
        (tbs,) = x509CrlLib.getTbsAndSig(pckCrlDer);
        actualHash = keccak256(tbs);
        assertEq(actualHash, collateralHash);
        assertEq(keccak256(attestedData), keccak256(pckCrlDer));
    }
}
