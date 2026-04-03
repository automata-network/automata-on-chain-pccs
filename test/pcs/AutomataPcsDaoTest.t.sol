// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../pcs/PCSSetupBase.t.sol";
import {AutomataDaoBase} from "../../src/automata_pccs/shared/AutomataDaoBase.sol";

contract AutomataPcsDaoTest is PCSSetupBase {
    function testPcsSetup() public readAsAuthorizedCaller {
        // validate RootCA attestations
        bytes32 key = pcs.PCS_KEY(CA.ROOT, false);
        bytes memory attestedData = pcs.getAttestedData(key);
        bytes32 collateralHash = pcs.getCollateralHash(key);
        (bytes memory tbs,) = x509Lib.getTbsAndSig(rootDer);
        bytes32 actualHash = keccak256(tbs);
        assertEq(actualHash, collateralHash);
        assertEq(keccak256(attestedData), keccak256(rootDer));

        // validate RootCRL attestations
        key = pcs.PCS_KEY(CA.ROOT, true);
        attestedData = pcs.getAttestedData(key);
        collateralHash = pcs.getCollateralHash(key);
        (tbs,) = x509CrlLib.getTbsAndSig(rootCrlDer);
        actualHash = keccak256(tbs);
        assertEq(actualHash, collateralHash);
        assertEq(keccak256(attestedData), keccak256(rootCrlDer));

        // validate SigningCA attestations
        key = pcs.PCS_KEY(CA.SIGNING, false);
        attestedData = pcs.getAttestedData(key);
        collateralHash = pcs.getCollateralHash(key);
        (tbs,) = x509CrlLib.getTbsAndSig(signingDer);
        actualHash = keccak256(tbs);
        assertEq(actualHash, collateralHash);
        assertEq(keccak256(attestedData), keccak256(signingDer));

        // validate PlatformCA attestations
        key = pcs.PCS_KEY(CA.PLATFORM, false);
        attestedData = pcs.getAttestedData(key);
        collateralHash = pcs.getCollateralHash(key);
        (tbs,) = x509CrlLib.getTbsAndSig(platformDer);
        actualHash = keccak256(tbs);
        assertEq(actualHash, collateralHash);
        assertEq(keccak256(attestedData), keccak256(platformDer));
    }

    function testPcsGetCertsAndRootCrl() public readAsAuthorizedCaller {
        (bytes memory rootCa, bytes memory rootCrl) = pcs.getCertificateById(CA.ROOT);
        (bytes memory platformCa,) = pcs.getCertificateById(CA.PLATFORM);

        assertEq(keccak256(rootCa), keccak256(rootDer));
        assertEq(keccak256(rootCrl), keccak256(rootCrlDer));
        assertEq(keccak256(platformCa), keccak256(platformDer));
    }

    function testUnauthorizedRead() public {
        (, address caller,) = vm.readCallers();
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(AutomataDaoBase.Unauthorized_Caller.selector, caller));
        pcs.getCertificateById(CA.ROOT);
    }

    function testCallFromAddressZero() public {
        vm.startPrank(address(0));

        (bytes memory rootCa, bytes memory rootCrl) = pcs.getCertificateById(CA.ROOT);
        (bytes memory platformCa,) = pcs.getCertificateById(CA.PLATFORM);

        assertEq(keccak256(rootCa), keccak256(rootDer));
        assertEq(keccak256(rootCrl), keccak256(rootCrlDer));
        assertEq(keccak256(platformCa), keccak256(platformDer));

        vm.stopPrank();
    }

    function testPausedCall() public {
        vm.prank(admin);
        pccsStorage.pauseCallerRestriction();

        (bytes memory rootCa, bytes memory rootCrl) = pcs.getCertificateById(CA.ROOT);
        (bytes memory platformCa,) = pcs.getCertificateById(CA.PLATFORM);

        assertEq(keccak256(rootCa), keccak256(rootDer));
        assertEq(keccak256(rootCrl), keccak256(rootCrlDer));
        assertEq(keccak256(platformCa), keccak256(platformDer));
    }

    function testDuplicateUpserts() public {
        // insert root CA
        vm.expectRevert(abi.encodeWithSelector(DaoBase.Duplicate_Collateral.selector));
        pcs.upsertPcsCertificates(CA.ROOT, rootDer);

        // insert root CRL
        vm.expectRevert(abi.encodeWithSelector(DaoBase.Duplicate_Collateral.selector));
        pcs.upsertRootCACrl(rootCrlDer);

        // insert Signing CA
        vm.expectRevert(abi.encodeWithSelector(DaoBase.Duplicate_Collateral.selector));
        pcs.upsertPcsCertificates(CA.SIGNING, signingDer);

        // insert Platform CA
        vm.expectRevert(abi.encodeWithSelector(DaoBase.Duplicate_Collateral.selector));
        pcs.upsertPcsCertificates(CA.PLATFORM, platformDer);
    }

    function testCollateralVersions() public {
        bytes32 rootCertKey = pcs.PCS_KEY(CA.ROOT, false);
        bytes32 rootCrlKey = pcs.PCS_KEY(CA.ROOT, true);
        bytes32 platformCertKey = pcs.PCS_KEY(CA.PLATFORM, false);
        (bool rootCertChanged, uint256 rootCertVersion) = pcs.hasChanged(rootCertKey, 0);
        (bool rootCrlChanged, uint256 rootCrlVersion) = pcs.hasChanged(rootCrlKey, 0);
        (bool platformChanged, uint256 platformVersion) = pcs.hasChanged(platformCertKey, 0);
        (bool rootCertChangedFromCurrent, uint256 rootCertCurrent) = pcs.hasChanged(rootCertKey, 1);

        assertEq(pcs.collateralVersion(rootCertKey), 1);
        assertEq(pcs.collateralVersion(rootCrlKey), 1);
        assertEq(pcs.collateralVersion(platformCertKey), 1);
        assertTrue(rootCertChanged);
        assertEq(rootCertVersion, 1);
        assertTrue(rootCrlChanged);
        assertEq(rootCrlVersion, 1);
        assertTrue(platformChanged);
        assertEq(platformVersion, 1);
        assertFalse(rootCertChangedFromCurrent);
        assertEq(rootCertCurrent, 1);
    }
}
