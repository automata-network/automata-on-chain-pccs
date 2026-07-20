// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console2} from "forge-std/Test.sol";

import {X509CRLHelper, X509CRLObj} from "../../src/helpers/X509CRLHelper.sol";
import {X509CRLHelperV2, X509CRLMetadata} from "../../src/helpers/X509CRLHelperV2.sol";

contract X509CRLHelperV2Test is Test {
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

    function testFirstMiddleLastAndMissingSerials() public {
        X509CRLObj memory parsed = legacy.parseCRLDER(crl129);
        uint256 length = parsed.serialNumbersRevoked.length;
        _completeIndex(crl129, 50);

        assertTrue(v2.serialNumberIsRevoked(parsed.serialNumbersRevoked[0], crl129), "first serial");
        assertTrue(v2.serialNumberIsRevoked(parsed.serialNumbersRevoked[length / 2], crl129), "middle serial");
        assertTrue(v2.serialNumberIsRevoked(parsed.serialNumbersRevoked[length - 1], crl129), "last serial");
        assertFalse(v2.serialNumberIsRevoked(type(uint256).max, crl129), "missing serial");
    }

    function testManyNonRevokedSerialsAndLegacyDifferential() public {
        _completeIndex(crl129, 50);
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
        v2.indexCrlBatch(crl57, 50);
        assertFalse(v2.indexedCrls(keccak256(crl57)));
    }

    function testPartialIndexNeverCreatesFalseNegativeAndOnlyCompletesAtEnd() public {
        X509CRLObj memory parsed = legacy.parseCRLDER(crl129);
        bytes32 derHash = keccak256(crl129);

        (uint256 indexedCount, bool complete) = v2.indexCrlBatch(crl129, 50);
        assertEq(indexedCount, 50);
        assertFalse(complete);
        assertFalse(v2.indexedCrls(derHash));

        // The last serial has not been indexed yet. It must still be found by
        // the strict linear fallback while the index is incomplete.
        assertTrue(v2.serialNumberIsRevoked(parsed.serialNumbersRevoked[128], crl129));

        assertFalse(v2.serialNumberIsRevoked(type(uint256).max, crl129));

        (indexedCount, complete) = v2.indexCrlBatch(crl129, 50);
        assertEq(indexedCount, 100);
        assertFalse(complete);

        (indexedCount, complete) = v2.indexCrlBatch(crl129, 50);
        assertEq(indexedCount, 129);
        assertTrue(complete);
        assertTrue(v2.indexedCrls(derHash));

        assertFalse(v2.serialNumberIsRevoked(type(uint256).max, crl129));

        (,, uint256 progressCount, bool progressComplete) = v2.getIndexProgress(derHash);
        assertEq(progressCount, 129);
        assertTrue(progressComplete);
    }

    function testRejectsZeroSizedIndexBatch() public {
        vm.expectRevert(X509CRLHelperV2.Invalid_Batch_Size.selector);
        v2.indexCrlBatch(crl57, 0);
    }

    function testIndexesTwoHundredSerialsInFourFiftyEntryBatches() public {
        bytes memory der = _syntheticCrlWithSerialCount(200);
        bytes32 derHash = keccak256(der);

        for (uint256 batch = 1; batch <= 4; batch++) {
            (uint256 indexedCount, bool complete) = v2.indexCrlBatch(der, 50);
            assertEq(indexedCount, batch * 50);
            assertEq(complete, batch == 4);
            assertEq(v2.indexedCrls(derHash), batch == 4);
        }

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

    function testGasBenchmark129NonMember() public {
        uint256 candidate = type(uint256).max;
        _completeIndex(crl129, 50);

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
        X509CRLMetadata memory metadata = v2.parseCRLMetadata(der);
        _completeIndex(der, 50);

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

    function _completeIndex(bytes memory der, uint256 batchSize) private {
        bool complete;
        for (uint256 i = 0; i < 32 && !complete; i++) {
            (, complete) = v2.indexCrlBatch(der, batchSize);
        }
        assertTrue(complete, "index did not complete");
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
        bytes memory algorithm = hex"300a06082a8648ce3d040302";
        bytes memory issuer = hex"3011310f300d06035504030c06497373756572";
        bytes memory thisUpdate = hex"170d3236303731373030303030305a";
        bytes memory nextUpdate = hex"170d3236303831363030303030305a";
        bytes memory revoked = _der(0x30, entries);
        bytes memory extensions = hex"a011300f300d0603551d230406300480020102";
        bytes memory tbs =
            _der(0x30, bytes.concat(hex"020101", algorithm, issuer, thisUpdate, nextUpdate, revoked, extensions));
        bytes memory signature = hex"0309003006020101020101";
        return _der(0x30, bytes.concat(tbs, algorithm, signature));
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

    function _slice(bytes memory input, uint256 start, uint256 length) private pure returns (bytes memory output) {
        output = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            output[i] = input[start + i];
        }
    }
}
