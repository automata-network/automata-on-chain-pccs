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
        bytes32 actualHash = keccak256(rootDer);
        assertEq(actualHash, collateralHash);
        assertEq(keccak256(attestedData), collateralHash);

        // validate RootCRL attestations
        attestedData = pcs.getAttestedData(rootCrlAttestation);
        collateralHash = pcs.getCollateralHash(rootCrlAttestation);
        actualHash = keccak256(rootCrlDer);
        assertEq(actualHash, collateralHash);
        assertEq(keccak256(attestedData), collateralHash);

        // validate SigningCA attestations
        attestedData = pcs.getAttestedData(signingAttestation);
        collateralHash = pcs.getCollateralHash(signingAttestation);
        actualHash = keccak256(signingDer);
        assertEq(actualHash, collateralHash);
        assertEq(keccak256(attestedData), collateralHash);

        // validate PlatformCA attestations
        attestedData = pcs.getAttestedData(platformAttestation);
        collateralHash = pcs.getCollateralHash(platformAttestation);
        actualHash = keccak256(platformDer);
        assertEq(actualHash, collateralHash);
        assertEq(keccak256(attestedData), collateralHash);

        // validate PlatformCRL attestations
        attestedData = pcs.getAttestedData(platformCrlAttestation);
        collateralHash = pcs.getCollateralHash(platformCrlAttestation);
        actualHash = keccak256(pckCrlDer);
        assertEq(actualHash, collateralHash);
        assertEq(keccak256(attestedData), collateralHash);
    }
}
