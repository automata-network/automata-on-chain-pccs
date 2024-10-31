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
        bytes memory attestedData = pccsStorage.readAttestation(rootAttestation);
        bytes32 collateralHash = abi.decode(pccsStorage.readAttestation(bytes32(uint256(rootAttestation) + 1)), (bytes32));

        (bytes memory tbs,) = x509Lib.getTbsAndSig(rootDer);
        bytes32 actualHash = keccak256(tbs);
        assertEq(actualHash, collateralHash);
        assertEq(keccak256(attestedData), keccak256(rootDer));

        // validate RootCRL attestations
        attestedData = pccsStorage.readAttestation(rootCrlAttestation);
        collateralHash = abi.decode(pccsStorage.readAttestation(bytes32(uint256(rootCrlAttestation) + 1)), (bytes32));
        (tbs,) = x509CrlLib.getTbsAndSig(rootCrlDer);
        actualHash = keccak256(tbs);
        assertEq(actualHash, collateralHash);
        assertEq(keccak256(attestedData), keccak256(rootCrlDer));

        // validate SigningCA attestations
        attestedData = pccsStorage.readAttestation(signingAttestation);
        collateralHash = abi.decode(pccsStorage.readAttestation(bytes32(uint256(signingAttestation) + 1)), (bytes32));
        (tbs,) = x509CrlLib.getTbsAndSig(signingDer);
        actualHash = keccak256(tbs);
        assertEq(actualHash, collateralHash);
        assertEq(keccak256(attestedData), keccak256(signingDer));

        // validate PlatformCA attestations
        attestedData = pccsStorage.readAttestation(platformAttestation);
        collateralHash = abi.decode(pccsStorage.readAttestation(bytes32(uint256(platformAttestation) + 1)), (bytes32));
        (tbs,) = x509CrlLib.getTbsAndSig(platformDer);
        actualHash = keccak256(tbs);
        assertEq(actualHash, collateralHash);
        assertEq(keccak256(attestedData), keccak256(platformDer));

        // validate PlatformCRL attestations
        attestedData = pccsStorage.readAttestation(platformCrlAttestation);
        collateralHash = abi.decode(pccsStorage.readAttestation(bytes32(uint256(platformCrlAttestation) + 1)), (bytes32));
        (tbs,) = x509CrlLib.getTbsAndSig(pckCrlDer);
        actualHash = keccak256(tbs);
        assertEq(actualHash, collateralHash);
        assertEq(keccak256(attestedData), keccak256(pckCrlDer));
    }
}
