// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {console2} from "forge-std/Test.sol";

import {PCSSetupBase} from "./PCSSetupBase.t.sol";
import {CA} from "../../src/Common.sol";
import {DaoBase} from "../../src/bases/DaoBase.sol";
import {PcsDaoV2} from "../../src/bases/PcsDaoV2.sol";
import {AutomataPcsDaoV2} from "../../src/automata_pccs/AutomataPcsDaoV2.sol";
import {AutomataPckDaoV2} from "../../src/automata_pccs/AutomataPckDaoV2.sol";
import {X509CRLHelper, X509CRLObj} from "../../src/helpers/X509CRLHelper.sol";
import {X509CRLHelperV2, X509CRLMetadata} from "../../src/helpers/X509CRLHelperV2.sol";

contract AutomataPcsDaoV2Test is PCSSetupBase {
    X509CRLHelperV2 internal crlV2;
    AutomataPcsDaoV2 internal pcsV2;
    AutomataPckDaoV2 internal pckV2;
    bytes internal crl57Previous;
    bytes internal crl57;
    bytes internal crl129;

    function setUp() public override {
        super.setUp();

        crl57Previous = vm.parseBytes(vm.readLine("test/assets/crl/platform-57-20260707.hex"));
        crl57 = vm.parseBytes(vm.readLine("test/assets/crl/platform-57-20260716.hex"));
        crl129 = vm.parseBytes(vm.readLine("test/assets/crl/platform-129-20260716.hex"));

        vm.startPrank(admin);
        crlV2 = new X509CRLHelperV2(admin);
        pcsV2 = new AutomataPcsDaoV2(address(pccsStorage), P256_VERIFIER, address(x509Lib), address(crlV2));
        pckV2 =
            new AutomataPckDaoV2(address(pccsStorage), P256_VERIFIER, address(pcsV2), address(x509Lib), address(crlV2));
        pccsStorage.grantDao(address(pcsV2));
        pccsStorage.grantDao(address(pckV2));
        crlV2.setAuthorizedIndexer(address(pcsV2), true);
        vm.stopPrank();

        vm.warp(1784289600); // 2026-07-17 12:00:00 UTC
    }

    function testDeploymentsBindV2ComponentsWithoutChangingAbi() public {
        assertEq(address(pcsV2.crlLib()), address(crlV2));
        assertEq(address(pcsV2.x509()), address(x509Lib));
        assertEq(address(pcsV2.P256_VERIFIER()), P256_VERIFIER);
        assertEq(address(pcsV2.resolver()), address(pccsStorage));
        assertEq(address(pckV2.crlLib()), address(crlV2));
        assertEq(address(pckV2.x509()), address(x509Lib));
        assertEq(address(pckV2.P256_VERIFIER()), P256_VERIFIER);
        assertEq(address(pckV2.resolver()), address(pccsStorage));
        assertEq(address(pckV2.Pcs()), address(pcsV2));

        bytes32 pcsProbe = keccak256("PCS_V2_STORAGE_PROBE");
        bytes32 pckProbe = keccak256("PCK_V2_STORAGE_PROBE");
        bytes32 pcsPointer = pccsStorage.collateralPointer(pcsProbe);
        bytes32 pckPointer = pccsStorage.collateralPointer(pckProbe);
        vm.prank(address(pcsV2));
        pccsStorage.attest(pcsProbe, hex"01", bytes32(0));
        vm.prank(address(pckV2));
        pccsStorage.attest(pckProbe, hex"02", bytes32(0));

        vm.prank(address(pcsV2));
        assertEq(pccsStorage.readAttestation(pcsPointer), hex"01");
        vm.prank(address(pckV2));
        assertEq(pccsStorage.readAttestation(pckPointer), hex"02");
    }

    function testRuntimeCodeHashValidationDetectsWrongBuildAndImmutable() public {
        X509CRLHelperV2 expectedCrl = new X509CRLHelperV2(admin);
        X509CRLHelper legacyCrl = new X509CRLHelper();
        assertEq(address(crlV2).codehash, address(expectedCrl).codehash);
        assertNotEq(address(crlV2).codehash, address(legacyCrl).codehash);

        AutomataPcsDaoV2 expectedPcs =
            new AutomataPcsDaoV2(address(pccsStorage), P256_VERIFIER, address(x509Lib), address(crlV2));
        AutomataPcsDaoV2 wrongPcs =
            new AutomataPcsDaoV2(address(pccsStorage), address(0xDEAD), address(x509Lib), address(crlV2));
        assertEq(address(pcsV2).codehash, address(expectedPcs).codehash);
        assertNotEq(address(pcsV2).codehash, address(wrongPcs).codehash);

        AutomataPckDaoV2 expectedPck =
            new AutomataPckDaoV2(address(pccsStorage), P256_VERIFIER, address(pcsV2), address(x509Lib), address(crlV2));
        AutomataPckDaoV2 wrongPck = new AutomataPckDaoV2(
            address(pccsStorage), address(0xDEAD), address(pcsV2), address(x509Lib), address(crlV2)
        );
        assertEq(address(pckV2).codehash, address(expectedPck).codehash);
        assertNotEq(address(pckV2).codehash, address(wrongPck).codehash);
    }

    function testNonInitialUpsert129Then57ShrinkAndRejectRollback() public {
        X509CRLMetadata memory parsed129 = crlV2.parseCRLMetadata(crl129);
        X509CRLMetadata memory parsed57 = crlV2.parseCRLMetadata(crl57);
        uint256 removedSerial = _findRemovedSerial(crl129, crl57);
        bytes32 hash129 = keccak256(crl129);
        bytes32 hash57 = keccak256(crl57);

        uint256 before129 = gasleft();
        pcsV2.upsertPckCrl(CA.PLATFORM, crl129);
        uint256 gas129 = before129 - gasleft();
        _assertStoredCrl(crl129);
        assertTrue(crlV2.indexedCrls(hash129), "upsert did not atomically index serials");
        assertTrue(crlV2.serialNumberIsRevoked(removedSerial, crl129));
        assertEq(parsed129.revokedCertificateCount, 129);

        uint256 before57 = gasleft();
        pcsV2.upsertPckCrl(CA.PLATFORM, crl57);
        uint256 gas57 = before57 - gasleft();
        _assertStoredCrl(crl57);
        assertTrue(crlV2.indexedCrls(hash57), "replacement did not atomically index serials");
        assertFalse(crlV2.serialNumberIsRevoked(removedSerial, crl57), "removed serial leaked into smaller CRL");
        assertEq(parsed57.revokedCertificateCount, 57);
        assertFalse(crlV2.serialNumberIsRevoked(removedSerial, crl57));

        vm.expectRevert(PcsDaoV2.Certificate_Out_Of_Date.selector);
        pcsV2.upsertPckCrl(CA.PLATFORM, crl129);
        _assertStoredCrl(crl57);

        console2.log("PcsDaoV2 129-entry upsert gas", gas129);
        console2.log("PcsDaoV2 57-entry replacement upsert gas", gas57);
    }

    function testIndexesCurrentCrlStoredByV1Atomically() public {
        pcs.upsertPckCrl(CA.PLATFORM, crl57);
        bytes32 derHash = keccak256(crl57);
        assertFalse(crlV2.indexedCrls(derHash));

        uint256 indexedCount = pcsV2.indexStoredCrl(CA.PLATFORM, derHash);
        assertEq(indexedCount, 57);
        assertTrue(crlV2.indexedCrls(derHash));
        _assertStoredCrl(crl57);
    }

    function testIndexesCurrentRootCrlStoredByV1Atomically() public {
        vm.warp(1711000000); // Within the real ROOT CRL validity window.
        bytes32 derHash = keccak256(rootCrlDer);
        assertFalse(crlV2.indexedCrls(derHash));

        uint256 indexedCount = pcsV2.indexStoredCrl(CA.ROOT, derHash);

        assertEq(indexedCount, 0);
        assertTrue(crlV2.indexedCrls(derHash));
    }

    function testRevokedLegacyPcsCannotReplaceIndexedCrlButV2Can() public {
        pcs.upsertPckCrl(CA.PLATFORM, crl129);
        pcsV2.indexStoredCrl(CA.PLATFORM, keccak256(crl129));
        assertTrue(crlV2.indexedCrls(keccak256(crl129)));

        vm.prank(admin);
        pccsStorage.revokeDao(address(pcs));

        vm.expectRevert(bytes("FORBIDDEN"));
        pcs.upsertPckCrl(CA.PLATFORM, crl57);
        _assertStoredCrl(crl129);

        pcsV2.upsertPckCrl(CA.PLATFORM, crl57);
        assertTrue(crlV2.indexedCrls(keccak256(crl57)));
        _assertStoredCrl(crl57);
    }

    function testPostRevocationReconcileIndexesCutoverRace() public {
        pcs.upsertPckCrl(CA.PLATFORM, crl129);
        pcsV2.indexStoredCrl(CA.PLATFORM, keccak256(crl129));

        // Models a valid V1 update landing after the pre-cutover index check
        // but before the legacy writer revocation transaction.
        pcs.upsertPckCrl(CA.PLATFORM, crl57);
        bytes32 racedDerHash = keccak256(crl57);
        assertFalse(crlV2.indexedCrls(racedDerHash));

        vm.prank(admin);
        pccsStorage.revokeDao(address(pcs));
        pcsV2.indexStoredCrl(CA.PLATFORM, racedDerHash);

        assertTrue(crlV2.indexedCrls(racedDerHash));
        _assertStoredCrl(crl57);
    }

    function testStoredCrlMigrationRejectsStaleExpectedHash() public {
        bytes32 hash129 = keccak256(crl129);
        bytes32 hash57 = keccak256(crl57);
        pcs.upsertPckCrl(CA.PLATFORM, crl129);
        pcsV2.upsertPckCrl(CA.PLATFORM, crl57);

        vm.expectRevert(abi.encodeWithSelector(PcsDaoV2.Crl_Hash_Mismatch.selector, hash129, hash57));
        pcsV2.indexStoredCrl(CA.PLATFORM, hash129);
        assertTrue(crlV2.indexedCrls(hash57));
    }

    function testV2UpsertCompletesIndexWithoutFollowUpTransaction() public {
        bytes32 derHash = keccak256(crl129);
        pcsV2.upsertPckCrl(CA.PLATFORM, crl129);
        assertTrue(crlV2.indexedCrls(derHash));
    }

    function testStoredCrlMigrationRejectsExpiredCrl() public {
        bytes32 derHash = keccak256(crl57);
        X509CRLMetadata memory metadata = crlV2.parseCRLMetadata(crl57);
        pcs.upsertPckCrl(CA.PLATFORM, crl57);

        vm.warp(metadata.validityNotAfter + 1);
        vm.expectRevert(abi.encodeWithSelector(PcsDaoV2.Crl_Expired.selector, CA.PLATFORM));
        pcsV2.indexStoredCrl(CA.PLATFORM, derHash);
        assertFalse(crlV2.indexedCrls(derHash));
    }

    function testRealSignedExactSetReissueReusesIndexAndGas() public {
        uint256 beforeInitial = gasleft();
        pcsV2.upsertPckCrl(CA.PLATFORM, crl57Previous);
        uint256 initialGas = beforeInitial - gasleft();
        bytes32 initialDerHash = keccak256(crl57Previous);
        bytes32 initialSetHash = crlV2.crlRevokedSetHashes(initialDerHash);

        uint256 beforeReissue = gasleft();
        pcsV2.upsertPckCrl(CA.PLATFORM, crl57);
        uint256 reissueGas = beforeReissue - gasleft();

        X509CRLObj memory beforeCrl = crlV2.parseCRLDER(crl57Previous);
        X509CRLObj memory afterCrl = crlV2.parseCRLDER(crl57);
        bytes32 reissuedDerHash = keccak256(crl57);
        assertEq(beforeCrl.serialNumbersRevoked, afterCrl.serialNumbersRevoked);
        assertNotEq(keccak256(beforeCrl.tbs), keccak256(afterCrl.tbs));
        assertTrue(crlV2.indexedCrls(initialDerHash));
        assertTrue(crlV2.indexedCrls(reissuedDerHash));
        assertEq(crlV2.crlRevokedSetHashes(reissuedDerHash), initialSetHash, "exact set index was not reused");
        _assertStoredCrl(crl57);

        console2.log("PcsDaoV2 real-signed 57-entry first-set upsert gas", initialGas);
        console2.log("PcsDaoV2 real-signed 57-entry exact-set reuse upsert gas", reissueGas);
    }

    function testSignatureOnlyReissueWithIdenticalTbsIsDuplicate() public {
        pcsV2.upsertPckCrl(CA.PLATFORM, crl57);
        bytes memory signatureOnlyChange = _copy(crl57);
        signatureOnlyChange[signatureOnlyChange.length - 1] ^= 0x01;

        vm.expectRevert(DaoBase.Duplicate_Collateral.selector);
        pcsV2.upsertPckCrl(CA.PLATFORM, signatureOnlyChange);
        _assertStoredCrl(crl57);
    }

    function testRejectsBadSignature() public {
        bytes memory malformed = _copy(crl57);
        malformed[malformed.length - 1] ^= 0x01;

        vm.expectRevert(PcsDaoV2.Invalid_Signature.selector);
        pcsV2.upsertPckCrl(CA.PLATFORM, malformed);
        assertFalse(crlV2.indexedCrls(keccak256(malformed)), "reverted upsert left a cache entry");
        assertEq(crlV2.crlRevokedSetHashes(keccak256(malformed)), bytes32(0), "reverted upsert left a set binding");
    }

    function testRejectsWrongIssuer() public {
        bytes memory malformed = _copy(crl57);
        _replaceFirst(malformed, bytes("Intel SGX PCK Platform CA"), bytes("Intel SGX PCK Xlatform CA"));

        vm.expectRevert(PcsDaoV2.Invalid_Issuer_Name.selector);
        pcsV2.upsertPckCrl(CA.PLATFORM, malformed);
    }

    function testRejectsWrongAuthorityKeyIdentifier() public {
        bytes memory malformed = _copy(crl57);
        bytes memory akid = crlV2.getAuthorityKeyIdentifier(malformed);
        bytes memory replacement = _copy(akid);
        replacement[replacement.length - 1] ^= 0x01;
        _replaceFirst(malformed, akid, replacement);

        vm.expectRevert(PcsDaoV2.Invalid_Authority_Key_Identifier.selector);
        pcsV2.upsertPckCrl(CA.PLATFORM, malformed);
    }

    function testRejectsExpiredCrl() public {
        X509CRLMetadata memory metadata = crlV2.parseCRLMetadata(crl57);
        vm.warp(metadata.validityNotAfter + 1);

        vm.expectRevert(abi.encodeWithSelector(PcsDaoV2.Crl_Expired.selector, CA.PLATFORM));
        pcsV2.upsertPckCrl(CA.PLATFORM, crl57);
    }

    function testRejectsMalformedCrlBeforeStateChange() public {
        bytes memory malformed = bytes.concat(crl57, hex"00");
        vm.expectRevert(X509CRLHelperV2.Invalid_DER.selector);
        pcsV2.upsertPckCrl(CA.PLATFORM, malformed);

        bytes32 key = pcsV2.PCS_KEY(CA.PLATFORM, true);
        bytes32 pointer = pccsStorage.collateralHashPointer(key);
        vm.prank(address(pcsV2));
        assertEq(pccsStorage.readAttestation(pointer).length, 0);
    }

    function _assertStoredCrl(bytes memory expected) private {
        vm.prank(admin);
        (, bytes memory actual) = pcsV2.getCertificateById(CA.PLATFORM);
        assertEq(actual, expected);
    }

    function _replaceFirst(bytes memory input, bytes memory needle, bytes memory replacement) private pure {
        require(needle.length == replacement.length && needle.length > 0, "invalid replacement");
        for (uint256 i = 0; i + needle.length <= input.length; i++) {
            bool matches = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (input[i + j] != needle[j]) {
                    matches = false;
                    break;
                }
            }
            if (matches) {
                for (uint256 j = 0; j < replacement.length; j++) {
                    input[i + j] = replacement[j];
                }
                return;
            }
        }
        revert("needle not found");
    }

    function _copy(bytes memory input) private pure returns (bytes memory output) {
        output = new bytes(input.length);
        for (uint256 i = 0; i < input.length; i++) {
            output[i] = input[i];
        }
    }

    function _findRemovedSerial(bytes memory larger, bytes memory smaller) private view returns (uint256 removed) {
        X509CRLObj memory largerCrl = crlV2.parseCRLDER(larger);
        X509CRLObj memory smallerCrl = crlV2.parseCRLDER(smaller);
        for (uint256 i = 0; i < largerCrl.serialNumbersRevoked.length; i++) {
            bool found;
            for (uint256 j = 0; j < smallerCrl.serialNumbersRevoked.length; j++) {
                if (largerCrl.serialNumbersRevoked[i] == smallerCrl.serialNumbersRevoked[j]) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                return largerCrl.serialNumbersRevoked[i];
            }
        }
        revert("no removed serial");
    }
}
