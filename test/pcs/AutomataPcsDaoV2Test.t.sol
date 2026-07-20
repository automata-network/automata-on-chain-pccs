// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {console2} from "forge-std/Test.sol";

import {PCSSetupBase} from "./PCSSetupBase.t.sol";
import {CA} from "../../src/Common.sol";
import {DaoBase} from "../../src/bases/DaoBase.sol";
import {PcsDaoV2} from "../../src/bases/PcsDaoV2.sol";
import {AutomataPcsDaoV2} from "../../src/automata_pccs/AutomataPcsDaoV2.sol";
import {AutomataPckDaoV2} from "../../src/automata_pccs/AutomataPckDaoV2.sol";
import {X509CRLObj} from "../../src/helpers/X509CRLHelper.sol";
import {X509CRLHelperV2, X509CRLMetadata} from "../../src/helpers/X509CRLHelperV2.sol";

contract AutomataPcsDaoV2Test is PCSSetupBase {
    X509CRLHelperV2 internal crlV2;
    AutomataPcsDaoV2 internal pcsV2;
    AutomataPckDaoV2 internal pckV2;
    bytes internal crl57;
    bytes internal crl129;

    function setUp() public override {
        super.setUp();

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
        assertEq(address(pckV2.crlLib()), address(crlV2));
        assertEq(address(pckV2.Pcs()), address(pcsV2));
        assertEq(address(pcsV2.resolver()), address(pccsStorage));
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
        assertTrue(pcsV2.authenticatedCrls(CA.PLATFORM, hash129));
        assertFalse(pcsV2.authenticatedCrls(CA.PROCESSOR, hash129), "authentication was not CA-scoped");
        assertFalse(crlV2.indexedCrls(hash129), "upsert eagerly indexed serials");
        assertTrue(crlV2.serialNumberIsRevoked(removedSerial, crl129));
        assertEq(parsed129.revokedCertificateCount, 129);
        _completeStoredIndex(CA.PLATFORM, hash129, 50);
        assertTrue(crlV2.indexedCrls(hash129));

        uint256 before57 = gasleft();
        pcsV2.upsertPckCrl(CA.PLATFORM, crl57);
        uint256 gas57 = before57 - gasleft();
        _assertStoredCrl(crl57);
        assertTrue(pcsV2.authenticatedCrls(CA.PLATFORM, hash57));
        assertFalse(crlV2.indexedCrls(hash57), "replacement eagerly indexed serials");
        assertFalse(crlV2.serialNumberIsRevoked(removedSerial, crl57), "removed serial leaked into smaller CRL");
        assertEq(parsed57.revokedCertificateCount, 57);
        _completeStoredIndex(CA.PLATFORM, hash57, 50);
        assertTrue(crlV2.indexedCrls(hash57));
        assertFalse(crlV2.serialNumberIsRevoked(removedSerial, crl57));

        vm.expectRevert(PcsDaoV2.Certificate_Out_Of_Date.selector);
        pcsV2.upsertPckCrl(CA.PLATFORM, crl129);
        _assertStoredCrl(crl57);

        console2.log("PcsDaoV2 129-entry upsert gas", gas129);
        console2.log("PcsDaoV2 57-entry replacement upsert gas", gas57);
    }

    function testIndexesCurrentCrlStoredByLegacyDao() public {
        pcs.upsertPckCrl(CA.PLATFORM, crl57);
        bytes32 derHash = keccak256(crl57);
        assertFalse(crlV2.indexedCrls(derHash));
        assertFalse(pcsV2.authenticatedCrls(CA.PLATFORM, derHash));

        (uint256 indexedCount, bool complete) = pcsV2.indexStoredCrlBatch(CA.PLATFORM, derHash, 50);
        assertEq(indexedCount, 50);
        assertFalse(complete);
        assertTrue(pcsV2.authenticatedCrls(CA.PLATFORM, derHash));
        assertFalse(crlV2.indexedCrls(derHash));

        // Once the legacy CRL has been authenticated, subsequent batches must
        // not repeat parseCRLMetadata's full revoked-list validation.
        vm.mockCallRevert(
            address(crlV2),
            abi.encodeWithSelector(X509CRLHelperV2.parseCRLMetadata.selector, crl57),
            bytes("unexpected metadata reparse")
        );
        (indexedCount, complete) = pcsV2.indexStoredCrlBatch(CA.PLATFORM, derHash, 50);
        vm.clearMockedCalls();
        assertEq(indexedCount, 57);
        assertTrue(complete);
        assertTrue(crlV2.indexedCrls(derHash));
        _assertStoredCrl(crl57);
    }

    function testStaleBatchCannotContinueAfterCrlChanges() public {
        bytes32 hash129 = keccak256(crl129);
        bytes32 hash57 = keccak256(crl57);
        pcsV2.upsertPckCrl(CA.PLATFORM, crl129);

        (uint256 indexedCount, bool complete) = pcsV2.indexStoredCrlBatch(CA.PLATFORM, hash129, 50);
        assertEq(indexedCount, 50);
        assertFalse(complete);

        pcsV2.upsertPckCrl(CA.PLATFORM, crl57);

        vm.expectRevert(abi.encodeWithSelector(PcsDaoV2.Crl_Hash_Mismatch.selector, hash129, hash57));
        pcsV2.indexStoredCrlBatch(CA.PLATFORM, hash129, 50);

        (,, indexedCount, complete) = crlV2.getIndexProgress(hash129);
        assertEq(indexedCount, 50);
        assertFalse(complete);
        assertFalse(crlV2.indexedCrls(hash57));
    }

    function testV2UpsertAuthenticationSkipsMetadataReparseFromFirstBatch() public {
        bytes32 derHash = keccak256(crl129);
        pcsV2.upsertPckCrl(CA.PLATFORM, crl129);
        assertTrue(pcsV2.authenticatedCrls(CA.PLATFORM, derHash));

        vm.mockCallRevert(
            address(crlV2),
            abi.encodeWithSelector(X509CRLHelperV2.parseCRLMetadata.selector, crl129),
            bytes("unexpected metadata reparse")
        );
        uint256 beforeBatch1 = gasleft();
        (uint256 indexedCount, bool complete) = pcsV2.indexStoredCrlBatch(CA.PLATFORM, derHash, 50);
        uint256 batch1Gas = beforeBatch1 - gasleft();
        assertEq(indexedCount, 50);
        assertFalse(complete);

        uint256 beforeBatch2 = gasleft();
        (indexedCount, complete) = pcsV2.indexStoredCrlBatch(CA.PLATFORM, derHash, 50);
        uint256 batch2Gas = beforeBatch2 - gasleft();
        assertEq(indexedCount, 100);
        assertFalse(complete);

        uint256 beforeBatch3 = gasleft();
        (indexedCount, complete) = pcsV2.indexStoredCrlBatch(CA.PLATFORM, derHash, 50);
        uint256 batch3Gas = beforeBatch3 - gasleft();
        vm.clearMockedCalls();

        assertEq(indexedCount, 129);
        assertTrue(complete);
        assertLt(batch1Gas, 14_000_000);
        assertLt(batch2Gas, 14_000_000);
        assertLt(batch3Gas, 14_000_000);

        console2.log("PcsDaoV2 cached 129 index batch 1 gas", batch1Gas);
        console2.log("PcsDaoV2 cached 129 index batch 2 gas", batch2Gas);
        console2.log("PcsDaoV2 cached 129 index batch 3 gas", batch3Gas);
    }

    function testCachedAuthenticationIsInvalidatedByIssuerOrRootCrlChanges() public {
        bytes32 derHash = keccak256(crl129);
        pcsV2.upsertPckCrl(CA.PLATFORM, crl129);
        assertTrue(pcsV2.authenticatedCrls(CA.PLATFORM, derHash));

        bytes32 issuerKey = pcsV2.PCS_KEY(CA.PLATFORM, false);
        bytes32 originalIssuerHash = pcsV2.getCollateralHash(issuerKey);
        vm.prank(address(pcsV2));
        pccsStorage.attest(issuerKey, bytes("replacement issuer"), bytes32(uint256(1)));
        assertFalse(pcsV2.authenticatedCrls(CA.PLATFORM, derHash));

        // Restore the original issuer through the normal validated fixture, then
        // prove a ROOT CRL dependency change also invalidates the cache.
        vm.prank(address(pcsV2));
        pccsStorage.attest(issuerKey, platformDer, originalIssuerHash);
        pcsV2.upsertPckCrl(CA.PLATFORM, crl57);
        bytes32 hash57 = keccak256(crl57);
        assertTrue(pcsV2.authenticatedCrls(CA.PLATFORM, hash57));

        bytes32 rootCrlKey = pcsV2.PCS_KEY(CA.ROOT, true);
        vm.prank(address(pcsV2));
        pccsStorage.attest(rootCrlKey, bytes("replacement root crl"), bytes32(uint256(2)));
        assertFalse(pcsV2.authenticatedCrls(CA.PLATFORM, hash57));
    }

    function testCachedAuthenticationDoesNotBypassCrlExpiry() public {
        bytes32 derHash = keccak256(crl57);
        X509CRLMetadata memory metadata = crlV2.parseCRLMetadata(crl57);
        pcsV2.upsertPckCrl(CA.PLATFORM, crl57);
        assertTrue(pcsV2.authenticatedCrls(CA.PLATFORM, derHash));

        vm.warp(metadata.validityNotAfter + 1);
        vm.expectRevert(abi.encodeWithSelector(PcsDaoV2.Crl_Expired.selector, CA.PLATFORM));
        pcsV2.indexStoredCrlBatch(CA.PLATFORM, derHash, 50);
    }

    function testReissuedDatesWithSameRevokedContentIsNotDuplicate() public {
        pcsV2.upsertPckCrl(CA.PLATFORM, crl57);
        bytes memory reissued = _copy(crl57);
        _replaceFirst(reissued, bytes("260716114338Z"), bytes("260717114338Z"));
        _replaceFirst(reissued, bytes("260815114338Z"), bytes("260816114338Z"));

        // The fixture signature no longer matches after changing the signed
        // dates. Mock only the P-256 primitive so this test isolates duplicate
        // and rollback behavior for a newly signed equivalent CRL.
        vm.mockCall(P256_VERIFIER, bytes(""), abi.encode(true));
        pcsV2.upsertPckCrl(CA.PLATFORM, reissued);

        X509CRLObj memory beforeCrl = crlV2.parseCRLDER(crl57);
        X509CRLObj memory afterCrl = crlV2.parseCRLDER(reissued);
        assertEq(beforeCrl.serialNumbersRevoked, afterCrl.serialNumbersRevoked);
        assertNotEq(keccak256(beforeCrl.tbs), keccak256(afterCrl.tbs));
        _assertStoredCrl(reissued);
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
        assertFalse(pcsV2.authenticatedCrls(CA.PLATFORM, keccak256(malformed)));
        assertFalse(crlV2.indexedCrls(keccak256(malformed)), "reverted upsert left a cache entry");
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
        assertFalse(pcsV2.authenticatedCrls(CA.PLATFORM, keccak256(malformed)));

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

    function _completeStoredIndex(CA ca, bytes32 derHash, uint256 batchSize) private {
        bool complete;
        for (uint256 i = 0; i < 32 && !complete; i++) {
            (, complete) = pcsV2.indexStoredCrlBatch(ca, derHash, batchSize);
        }
        assertTrue(complete, "stored CRL index did not complete");
    }
}
