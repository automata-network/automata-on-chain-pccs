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
}
