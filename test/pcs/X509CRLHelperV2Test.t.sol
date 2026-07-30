// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console2} from "forge-std/Test.sol";

import {X509CRLHelper, X509CRLObj} from "../../src/helpers/X509CRLHelper.sol";
import {X509CRLHelperV2, X509CRLMetadata} from "../../src/helpers/X509CRLHelperV2.sol";
import {PCSConstants} from "./PCSConstants.t.sol";

contract X509CRLHelperV2Test is Test, PCSConstants {
    X509CRLHelper internal legacy;
    X509CRLHelperV2 internal v2;
    bytes internal crl57;
    bytes internal crl129;

    function setUp() public {
        legacy = new X509CRLHelper();
        v2 = new X509CRLHelperV2(address(this));
        v2.setAuthorizedIndexer(address(this), true);
        crl57 = vm.parseBytes(vm.readLine("test/assets/crl/platform-57-20260716.hex"));
        crl129 = vm.parseBytes(vm.readLine("test/assets/crl/platform-129-20260716.hex"));
    }

    function testMetadataAndEveryRevokedSerial57() public {
        _assertMetadataAndEveryRevokedSerial(crl57, 57);
    }

    function testMetadataAndEveryRevokedSerial129() public {
        _assertMetadataAndEveryRevokedSerial(crl129, 129);
    }

    function testMetadataAcceptsRealRootCrlProfile() public {
        X509CRLMetadata memory metadata = v2.parseCRLMetadata(rootCrlDer);

        assertEq(metadata.revokedCertificateCount, 0);
        assertGt(metadata.authorityKeyIdentifier.length, 0);
    }

    function testMetadataAcceptsRealPckCrlReasonExtensions() public {
        X509CRLObj memory parsed = legacy.parseCRLDER(pckCrlDer);
        X509CRLMetadata memory metadata = v2.parseCRLMetadata(pckCrlDer);

        assertGt(parsed.serialNumbersRevoked.length, 0);
        assertEq(metadata.revokedCertificateCount, parsed.serialNumbersRevoked.length);
    }

    function testFirstMiddleLastAndMissingSerials() public {
        X509CRLObj memory parsed = legacy.parseCRLDER(crl129);
        uint256 length = parsed.serialNumbersRevoked.length;
        _completeIndex(crl129);

        assertTrue(v2.serialNumberIsRevoked(parsed.serialNumbersRevoked[0], crl129), "first serial");
        assertTrue(v2.serialNumberIsRevoked(parsed.serialNumbersRevoked[length / 2], crl129), "middle serial");
        assertTrue(v2.serialNumberIsRevoked(parsed.serialNumbersRevoked[length - 1], crl129), "last serial");
        assertFalse(v2.serialNumberIsRevoked(type(uint256).max, crl129), "missing serial");
    }

    function testManyNonRevokedSerialsAndLegacyDifferential() public {
        _completeIndex(crl129);
        for (uint256 i = 0; i < 256; i++) {
            uint256 candidate = uint256(keccak256(abi.encode("non-revoked", i)));
            bool actual = v2.serialNumberIsRevoked(candidate, crl129);
            assertFalse(actual, "unexpected generated collision");

            // A bounded V1 comparison proves equivalent negative semantics
            // without making the test quadratic in the legacy implementation.
            if (i < 4) {
                assertEq(actual, legacy.serialNumberIsRevoked(candidate, crl129));
            }
        }
    }

    function testRejectsTruncatedDer() public {
        bytes memory truncated = _slice(crl129, 0, crl129.length - 1);
        vm.expectRevert(X509CRLHelperV2.Invalid_DER.selector);
        v2.serialNumberIsRevoked(type(uint256).max, truncated);
    }

    function testRejectsTrailingBytes() public {
        bytes memory trailing = bytes.concat(crl129, hex"00");
        vm.expectRevert(X509CRLHelperV2.Invalid_DER.selector);
        v2.parseCRLMetadata(trailing);
    }

    function testOnlyAuthorizedIndexerCanPopulateCache() public {
        address unauthorized = address(0xBEEF);
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(X509CRLHelperV2.Unauthorized_Indexer.selector, unauthorized));
        v2.parseAndIndexCRLMetadata(crl57);
        assertFalse(v2.indexedCrls(keccak256(crl57)));
    }

    function testOneShotIndexReusesExactRevokedSetAcrossReissue() public {
        X509CRLMetadata memory initial = v2.parseAndIndexCRLMetadata(crl57);
        bytes32 initialDerHash = keccak256(crl57);
        bytes32 setHash = v2.crlRevokedSetHashes(initialDerHash);
        assertTrue(v2.indexedCrls(initialDerHash));
        assertTrue(v2.indexedRevokedSets(setHash));
        assertEq(v2.revokedSetCounts(setHash), 57);

        bytes memory reissued = _copy(crl57);
        _replaceFirst(reissued, bytes("260716114338Z"), bytes("260717114338Z"));
        _replaceFirst(reissued, bytes("260815114338Z"), bytes("260816114338Z"));
        X509CRLMetadata memory reused = v2.parseAndIndexCRLMetadata(reissued);
        bytes32 reissuedDerHash = keccak256(reissued);

        assertEq(initial.revokedCertificateCount, 57);
        assertEq(reused.revokedCertificateCount, 57);
        assertNotEq(initial.tbsHash, reused.tbsHash);
        assertEq(v2.crlRevokedSetHashes(reissuedDerHash), setHash);
        assertTrue(v2.indexedCrls(reissuedDerHash));

        X509CRLObj memory parsed = legacy.parseCRLDER(reissued);
        assertTrue(v2.serialNumberIsRevoked(parsed.serialNumbersRevoked[0], reissued));
        assertTrue(v2.serialNumberIsRevoked(parsed.serialNumbersRevoked[56], reissued));
        assertFalse(v2.serialNumberIsRevoked(type(uint256).max, reissued));
    }

    function testIndexesTwoHundredSerialsAtomically() public {
        bytes memory der = _syntheticCrlWithSerialCount(200);
        bytes32 derHash = keccak256(der);
        X509CRLMetadata memory metadata = v2.parseAndIndexCRLMetadata(der);

        assertEq(metadata.revokedCertificateCount, 200);
        assertTrue(v2.indexedCrls(derHash));
        assertTrue(v2.serialNumberIsRevoked(1, der));
        assertTrue(v2.serialNumberIsRevoked(100, der));
        assertTrue(v2.serialNumberIsRevoked(200, der));
        assertFalse(v2.serialNumberIsRevoked(201, der));
    }

    function testRejectsInvalidRootTag() public {
        bytes memory malformed = _copy(crl57);
        malformed[0] = 0x31;
        vm.expectRevert(X509CRLHelperV2.Invalid_DER.selector);
        v2.parseCRLMetadata(malformed);
    }

    function testRejectsNegativeSerial() public {
        bytes memory malformed = _syntheticCrl(hex"80");
        vm.expectRevert(X509CRLHelperV2.Invalid_DER.selector);
        v2.serialNumberIsRevoked(1, malformed);
    }

    function testRejectsSerialLongerThanUint256() public {
        bytes memory tooLong = new bytes(33);
        tooLong[0] = 0x01;
        bytes memory malformed = _syntheticCrl(tooLong);
        vm.expectRevert(X509CRLHelperV2.Invalid_Serial_Number.selector);
        v2.serialNumberIsRevoked(1, malformed);
    }

    function testRejectsNonCanonicalSerial() public {
        bytes memory malformed = _syntheticCrl(hex"0001");
        vm.expectRevert(X509CRLHelperV2.Invalid_DER.selector);
        v2.serialNumberIsRevoked(1, malformed);
    }

    function testAcceptsCanonicalSyntheticSerial() public {
        bytes memory valid = _syntheticCrl(hex"01");
        assertTrue(v2.serialNumberIsRevoked(1, valid));
        assertFalse(v2.serialNumberIsRevoked(2, valid));
    }

    function testRejectsInvalidMonth() public {
        _assertRejectsInvalidTime(bytes("260716114338Z"), bytes("269916114338Z"));
    }

    function testRejectsInvalidDay() public {
        _assertRejectsInvalidTime(bytes("260716114338Z"), bytes("260732114338Z"));
    }

    function testRejectsInvalidNonLeapDay() public {
        _assertRejectsInvalidTime(bytes("260716114338Z"), bytes("250229114338Z"));
    }

    function testAcceptsValidLeapDay() public view {
        bytes memory valid = _copy(crl57);
        _replaceFirst(valid, bytes("260716114338Z"), bytes("240229114338Z"));
        v2.parseCRLMetadata(valid);
    }

    function testRejectsInvalidHour() public {
        _assertRejectsInvalidTime(bytes("260716114338Z"), bytes("260716244338Z"));
    }

    function testRejectsInvalidMinute() public {
        _assertRejectsInvalidTime(bytes("260716114338Z"), bytes("260716116038Z"));
    }

    function testRejectsInvalidSecond() public {
        _assertRejectsInvalidTime(bytes("260716114338Z"), bytes("260716114360Z"));
    }

    function testRejectsInvalidGeneralizedTimeCalendar() public {
        bytes memory issuer = hex"3011310f300d06035504030c06497373756572";
        bytes memory invalidThisUpdate = hex"180f32303236393931373030303030305a";
        bytes memory validNextUpdate = hex"180f32303236303831363030303030305a";
        bytes memory der = _syntheticCrlWithIssuerEntriesAndTimes(
            issuer, _syntheticRevokedEntry(1), invalidThisUpdate, validNextUpdate
        );

        vm.expectRevert(X509CRLHelperV2.Invalid_DER.selector);
        v2.parseCRLMetadata(der);
    }

    function testRejectsMalformedIssuerFieldAfterCommonName() public {
        bytes memory malformedIssuer =
            bytes.concat(hex"30", hex"1e", hex"310f300d06035504030c06497373756572", hex"320b3009060355040613025553");
        bytes memory der = _syntheticCrlWithIssuerAndEntries(malformedIssuer, _syntheticRevokedEntry(1));

        vm.expectRevert(X509CRLHelperV2.Invalid_DER.selector);
        v2.parseCRLMetadata(der);
    }

    function testFallbackValidatesEntriesAfterMatchingSerial() public {
        bytes memory entries = bytes.concat(_syntheticRevokedEntry(1), hex"310f020102170d3236303731373030303030305a");
        bytes memory malformed = _syntheticCrlWithEntries(entries);

        vm.expectRevert(X509CRLHelperV2.Invalid_DER.selector);
        v2.serialNumberIsRevoked(1, malformed);
    }

    function testAcceptsUnknownNonCriticalCrlExtension() public {
        bytes memory extensions = bytes.concat(_defaultCrlExtensionItems(), _extension(hex"2a0304", false, hex"0500"));
        X509CRLMetadata memory metadata = v2.parseCRLMetadata(_syntheticCrlWithCrlExtensions(extensions));

        assertEq(metadata.revokedCertificateCount, 1);
        assertEq(metadata.authorityKeyIdentifier, hex"0102");
    }

    function testRejectsUnknownCriticalCrlExtension() public {
        bytes memory extensions = bytes.concat(_defaultCrlExtensionItems(), _extension(hex"2a0304", true, hex"0500"));

        vm.expectRevert(X509CRLHelperV2.Unsupported_Critical_Extension.selector);
        v2.parseCRLMetadata(_syntheticCrlWithCrlExtensions(extensions));
    }

    function testRejectsDeltaCrlIndicator() public {
        for (uint256 critical = 0; critical < 2; critical++) {
            bytes memory extensions =
                bytes.concat(_defaultCrlExtensionItems(), _extension(hex"551d1b", critical == 1, hex"020101"));

            vm.expectRevert(X509CRLHelperV2.Unsupported_CRL_Extension.selector);
            v2.parseCRLMetadata(_syntheticCrlWithCrlExtensions(extensions));
        }
    }

    function testRejectsIssuingDistributionPoint() public {
        for (uint256 critical = 0; critical < 2; critical++) {
            bytes memory extensions =
                bytes.concat(_defaultCrlExtensionItems(), _extension(hex"551d1c", critical == 1, hex"3000"));

            vm.expectRevert(X509CRLHelperV2.Unsupported_CRL_Extension.selector);
            v2.parseCRLMetadata(_syntheticCrlWithCrlExtensions(extensions));
        }
    }

    function testRejectsDuplicateAuthorityKeyIdentifier() public {
        bytes memory extensions = bytes.concat(_defaultCrlExtensionItems(), _authorityKeyIdentifierExtension());

        vm.expectRevert(X509CRLHelperV2.Duplicate_CRL_Extension.selector);
        v2.parseCRLMetadata(_syntheticCrlWithCrlExtensions(extensions));
    }

    function testRejectsDuplicateCrlNumber() public {
        bytes memory extensions = bytes.concat(_defaultCrlExtensionItems(), _crlNumberExtension());

        vm.expectRevert(X509CRLHelperV2.Duplicate_CRL_Extension.selector);
        v2.parseCRLMetadata(_syntheticCrlWithCrlExtensions(extensions));
    }

    function testRejectsMissingCrlNumberOnMetadataPath() public {
        bytes memory der = _syntheticCrlWithCrlExtensions(_authorityKeyIdentifierExtension());
        assertEq(v2.getAuthorityKeyIdentifier(der), hex"0102", "compatibility getter changed");

        vm.expectRevert(X509CRLHelperV2.Invalid_CRL_Profile.selector);
        v2.parseCRLMetadata(der);

        vm.expectRevert(X509CRLHelperV2.Invalid_CRL_Profile.selector);
        v2.parseAndIndexCRLMetadata(der);
    }

    function testRejectsMissingAuthorityKeyIdentifierOnMetadataPath() public {
        bytes memory der = _syntheticCrlWithCrlExtensions(_crlNumberExtension());
        assertEq(v2.getAuthorityKeyIdentifier(der).length, 0, "compatibility getter must return empty");

        vm.expectRevert(X509CRLHelperV2.Invalid_CRL_Profile.selector);
        v2.parseCRLMetadata(der);
    }

    function testRejectsMalformedCrlNumber() public {
        bytes memory extensions =
            bytes.concat(_authorityKeyIdentifierExtension(), _extension(hex"551d14", false, hex"020180"));

        vm.expectRevert(X509CRLHelperV2.Invalid_DER.selector);
        v2.parseCRLMetadata(_syntheticCrlWithCrlExtensions(extensions));
    }

    function testRejectsCriticalEntryExtension() public {
        bytes memory entryExtensions = _extension(hex"2a0304", true, hex"0500");
        bytes memory der = _syntheticCrlWithEntries(_syntheticRevokedEntryWithExtensions(1, entryExtensions));

        vm.expectRevert(X509CRLHelperV2.Unsupported_Critical_Extension.selector);
        v2.parseCRLMetadata(der);
    }

    function testRejectsCertificateIssuerEntryExtension() public {
        bytes memory entryExtensions = _extension(hex"551d1d", false, hex"3000");
        bytes memory der = _syntheticCrlWithEntries(_syntheticRevokedEntryWithExtensions(1, entryExtensions));

        vm.expectRevert(X509CRLHelperV2.Unsupported_CRL_Extension.selector);
        v2.parseCRLMetadata(der);
    }

    function testAcceptsNonCriticalReasonCodeEntryExtension() public {
        bytes memory entryExtensions = _extension(hex"551d15", false, hex"0a0101");
        bytes memory der = _syntheticCrlWithEntries(_syntheticRevokedEntryWithExtensions(1, entryExtensions));
        X509CRLMetadata memory metadata = v2.parseCRLMetadata(der);

        assertEq(metadata.revokedCertificateCount, 1);
        assertTrue(v2.serialNumberIsRevoked(1, der));
    }

    function testRejectsRemoveFromCrlReasonWithoutDeltaCrlSupport() public {
        bytes memory entryExtensions = _extension(hex"551d15", false, hex"0a0108");
        bytes memory der = _syntheticCrlWithEntries(_syntheticRevokedEntryWithExtensions(1, entryExtensions));

        vm.expectRevert(X509CRLHelperV2.Unsupported_CRL_Extension.selector);
        v2.parseCRLMetadata(der);
    }

    function testFallbackRejectsUnsupportedCrlAndEntryExtensions() public {
        bytes memory extensions = bytes.concat(_defaultCrlExtensionItems(), _extension(hex"2a0304", true, hex"0500"));
        vm.expectRevert(X509CRLHelperV2.Unsupported_Critical_Extension.selector);
        v2.serialNumberIsRevoked(1, _syntheticCrlWithCrlExtensions(extensions));

        extensions = bytes.concat(_defaultCrlExtensionItems(), _extension(hex"551d1b", false, hex"020101"));
        vm.expectRevert(X509CRLHelperV2.Unsupported_CRL_Extension.selector);
        v2.serialNumberIsRevoked(1, _syntheticCrlWithCrlExtensions(extensions));

        bytes memory entryExtensions = _extension(hex"551d1d", false, hex"3000");
        bytes memory indirect = _syntheticCrlWithEntries(_syntheticRevokedEntryWithExtensions(1, entryExtensions));
        vm.expectRevert(X509CRLHelperV2.Unsupported_CRL_Extension.selector);
        v2.serialNumberIsRevoked(1, indirect);
    }

    function testGasBenchmark129NonMember() public {
        uint256 candidate = type(uint256).max;
        _completeIndex(crl129);

        uint256 beforeLegacy = gasleft();
        bool legacyResult = legacy.serialNumberIsRevoked(candidate, crl129);
        uint256 legacyGas = beforeLegacy - gasleft();

        uint256 beforeV2 = gasleft();
        bool v2Result = v2.serialNumberIsRevoked(candidate, crl129);
        uint256 v2Gas = beforeV2 - gasleft();

        assertEq(v2Result, legacyResult);
        // `forge test --gas-report` adds reporting overhead to storage-backed
        // calls observed through gasleft(). Keep this assertion conservative;
        // the gas report itself records the callee-side lookup cost.
        assertLt(v2Gas, legacyGas / 10, "indexed V2 lookup should be materially cheaper");
        console2.log("legacy serialNumberIsRevoked 129 gas", legacyGas);
        console2.log("V2 serialNumberIsRevoked 129 gas", v2Gas);
    }

    function _assertMetadataAndEveryRevokedSerial(bytes memory der, uint256 expectedCount) private {
        X509CRLObj memory legacyParsed = legacy.parseCRLDER(der);
        X509CRLObj memory v2Parsed = v2.parseCRLDER(der);
        X509CRLMetadata memory metadata = v2.parseAndIndexCRLMetadata(der);

        assertEq(legacyParsed.serialNumbersRevoked.length, expectedCount);
        assertEq(v2Parsed.serialNumbersRevoked.length, expectedCount);
        assertEq(metadata.revokedCertificateCount, expectedCount);
        assertEq(metadata.issuerCommonName, legacyParsed.issuerCommonName);
        assertEq(metadata.validityNotBefore, legacyParsed.validityNotBefore);
        assertEq(metadata.validityNotAfter, legacyParsed.validityNotAfter);
        assertEq(metadata.authorityKeyIdentifier, legacyParsed.authorityKeyIdentifier);
        assertEq(metadata.signature, legacyParsed.signature);
        assertEq(metadata.tbsHash, keccak256(legacyParsed.tbs));
        assertEq(metadata.tbsSha256, sha256(legacyParsed.tbs));

        for (uint256 i = 0; i < expectedCount; i++) {
            uint256 expected = legacyParsed.serialNumbersRevoked[i];
            assertEq(v2Parsed.serialNumbersRevoked[i], expected);
            assertTrue(v2.serialNumberIsRevoked(expected, der));
        }
    }

    function _completeIndex(bytes memory der) private {
        v2.parseAndIndexCRLMetadata(der);
        assertTrue(v2.indexedCrls(keccak256(der)), "index did not complete");
    }

    function _assertRejectsInvalidTime(bytes memory original, bytes memory replacement) private {
        bytes memory malformed = _copy(crl57);
        _replaceFirst(malformed, original, replacement);
        vm.expectRevert(X509CRLHelperV2.Invalid_DER.selector);
        v2.parseCRLMetadata(malformed);
    }

    function _syntheticRevokedEntry(uint8 serial) private pure returns (bytes memory) {
        bytes memory thisUpdate = hex"170d3236303731373030303030305a";
        return _der(0x30, bytes.concat(_der(0x02, abi.encodePacked(bytes1(serial))), thisUpdate));
    }

    function _syntheticRevokedEntryWithExtensions(uint8 serial, bytes memory extensionItems)
        private
        pure
        returns (bytes memory)
    {
        bytes memory thisUpdate = hex"170d3236303731373030303030305a";
        return
            _der(
                0x30, bytes.concat(_der(0x02, abi.encodePacked(bytes1(serial))), thisUpdate, _der(0x30, extensionItems))
            );
    }

    function _syntheticCrl(bytes memory serialContent) private pure returns (bytes memory) {
        bytes memory thisUpdate = hex"170d3236303731373030303030305a";
        bytes memory serialNode = _der(0x02, serialContent);
        bytes memory entry = _der(0x30, bytes.concat(serialNode, thisUpdate));
        return _syntheticCrlWithEntries(entry);
    }

    function _syntheticCrlWithSerialCount(uint256 count) private pure returns (bytes memory) {
        bytes memory thisUpdate = hex"170d3236303731373030303030305a";
        bytes memory entries;
        for (uint256 serial = 1; serial <= count; serial++) {
            bytes memory serialContent = serial < 128
                ? abi.encodePacked(bytes1(uint8(serial)))
                : abi.encodePacked(bytes1(0), bytes1(uint8(serial)));
            entries = bytes.concat(entries, _der(0x30, bytes.concat(_der(0x02, serialContent), thisUpdate)));
        }
        return _syntheticCrlWithEntries(entries);
    }

    function _syntheticCrlWithEntries(bytes memory entries) private pure returns (bytes memory) {
        bytes memory issuer = hex"3011310f300d06035504030c06497373756572";
        return _syntheticCrlWithIssuerAndEntries(issuer, entries);
    }

    function _syntheticCrlWithIssuerAndEntries(bytes memory issuer, bytes memory entries)
        private
        pure
        returns (bytes memory)
    {
        bytes memory thisUpdate = hex"170d3236303731373030303030305a";
        bytes memory nextUpdate = hex"170d3236303831363030303030305a";
        return _syntheticCrlWithIssuerEntriesAndTimes(issuer, entries, thisUpdate, nextUpdate);
    }

    function _syntheticCrlWithIssuerEntriesAndTimes(
        bytes memory issuer,
        bytes memory entries,
        bytes memory thisUpdate,
        bytes memory nextUpdate
    ) private pure returns (bytes memory) {
        return _syntheticCrlWithIssuerEntriesTimesAndExtensions(
            issuer, entries, thisUpdate, nextUpdate, _defaultCrlExtensionItems()
        );
    }

    function _syntheticCrlWithCrlExtensions(bytes memory extensionItems) private pure returns (bytes memory) {
        bytes memory issuer = hex"3011310f300d06035504030c06497373756572";
        bytes memory thisUpdate = hex"170d3236303731373030303030305a";
        bytes memory nextUpdate = hex"170d3236303831363030303030305a";
        return _syntheticCrlWithIssuerEntriesTimesAndExtensions(
            issuer, _syntheticRevokedEntry(1), thisUpdate, nextUpdate, extensionItems
        );
    }

    function _syntheticCrlWithIssuerEntriesTimesAndExtensions(
        bytes memory issuer,
        bytes memory entries,
        bytes memory thisUpdate,
        bytes memory nextUpdate,
        bytes memory extensionItems
    ) private pure returns (bytes memory) {
        bytes memory algorithm = hex"300a06082a8648ce3d040302";
        bytes memory revoked = _der(0x30, entries);
        bytes memory extensions = _der(0xA0, _der(0x30, extensionItems));
        bytes memory tbs =
            _der(0x30, bytes.concat(hex"020101", algorithm, issuer, thisUpdate, nextUpdate, revoked, extensions));
        bytes memory signature = hex"0309003006020101020101";
        return _der(0x30, bytes.concat(tbs, algorithm, signature));
    }

    function _defaultCrlExtensionItems() private pure returns (bytes memory) {
        return bytes.concat(_authorityKeyIdentifierExtension(), _crlNumberExtension());
    }

    function _authorityKeyIdentifierExtension() private pure returns (bytes memory) {
        return _extension(hex"551d23", false, hex"300480020102");
    }

    function _crlNumberExtension() private pure returns (bytes memory) {
        return _extension(hex"551d14", false, hex"020101");
    }

    function _extension(bytes memory oid, bool critical, bytes memory value) private pure returns (bytes memory) {
        bytes memory criticalNode;
        if (critical) criticalNode = hex"0101ff";
        return _der(0x30, bytes.concat(_der(0x06, oid), criticalNode, _der(0x04, value)));
    }

    function _der(uint8 tag, bytes memory content) private pure returns (bytes memory) {
        uint256 length = content.length;
        if (length < 128) {
            return bytes.concat(bytes1(tag), bytes1(uint8(length)), content);
        }
        if (length <= type(uint8).max) {
            return bytes.concat(bytes1(tag), hex"81", bytes1(uint8(length)), content);
        }
        return bytes.concat(bytes1(tag), hex"82", bytes2(uint16(length)), content);
    }

    function _copy(bytes memory input) private pure returns (bytes memory output) {
        output = _slice(input, 0, input.length);
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

    function _slice(bytes memory input, uint256 start, uint256 length) private pure returns (bytes memory output) {
        output = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            output[i] = input[start + i];
        }
    }
}
