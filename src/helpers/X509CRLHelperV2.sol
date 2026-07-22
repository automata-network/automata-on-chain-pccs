// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {X509CRLObj} from "./X509CRLHelper.sol";
import {DateTimeUtils} from "../utils/DateTimeUtils.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {DateTimeLib} from "solady/utils/DateTimeLib.sol";

/**
 * @notice The subset of a CRL needed by PcsDao when validating an upsert.
 * @dev The TBS hashes are computed over the exact signed DER node. Returning
 * hashes instead of the full TBS avoids copying a potentially large CRL back
 * across the external helper call.
 */
struct X509CRLMetadata {
    string issuerCommonName;
    uint256 validityNotBefore;
    uint256 validityNotAfter;
    bytes authorityKeyIdentifier;
    bytes signature;
    bytes32 tbsHash;
    bytes32 tbsSha256;
    uint256 revokedCertificateCount;
}

/**
 * @title Gas-bounded X509 CRL helper
 * @notice ABI-compatible replacement for X509CRLHelper with a metadata-only
 * parser for CRL upserts and an exact serial-number index for verification.
 * @dev This parser intentionally supports the Intel PCS CRL profile used by
 * the on-chain PCCS: v2 CRLs, ECDSA-with-SHA256, a nextUpdate value and CRL
 * extensions. Malformed or unsupported encodings revert instead of being
 * interpreted as a non-revoked certificate.
 */
contract X509CRLHelperV2 is Ownable {
    bytes8 private constant ECDSA_WITH_SHA256_OID = 0x2a8648ce3d040302;
    bytes3 private constant COMMON_NAME_OID = 0x550403;
    bytes3 private constant AUTHORITY_KEY_IDENTIFIER_OID = 0x551d23;

    error Invalid_DER();
    error Invalid_CRL_Profile();
    error Invalid_Serial_Number();
    error Missing_Common_Name();
    error Unauthorized_Indexer(address caller);
    event SetAuthorizedIndexer(address indexed indexer, bool authorized);
    event IndexedCrl(
        bytes32 indexed derHash, bytes32 indexed revokedSetHash, uint256 revokedCertificateCount, bool reused
    );

    mapping(address indexer => bool authorized) public authorizedIndexers;
    /// @notice Binds an exact CRL DER to its canonical ordered revoked-serial set.
    mapping(bytes32 derHash => bytes32 revokedSetHash) public crlRevokedSetHashes;
    mapping(bytes32 revokedSetHash => bool isIndexed) public indexedRevokedSets;
    mapping(bytes32 revokedSetHash => uint256 revokedCertificateCount) public revokedSetCounts;
    mapping(bytes32 revokedSetHash => mapping(uint256 serialNumber => bool revoked)) private _revokedSerials;

    struct Node {
        uint256 start;
        uint256 content;
        uint256 end; // exclusive
    }

    struct CrlLayout {
        Node outer;
        Node tbs;
        Node issuer;
        Node thisUpdate;
        Node nextUpdate;
        Node revokedCertificates;
        Node extensions;
        Node signature;
        bool hasRevokedCertificates;
    }

    constructor(address initialOwner) {
        _initializeOwner(initialOwner);
    }

    modifier onlyAuthorizedIndexer() {
        if (!authorizedIndexers[msg.sender]) revert Unauthorized_Indexer(msg.sender);
        _;
    }

    /**
     * @notice Authorizes a PCS DAO to build immutable indexes from validated DER.
     * @dev An indexer cannot choose membership values: they are always derived by
     * the strict parser from the exact DER preimage used as the index key.
     */
    function setAuthorizedIndexer(address indexer, bool authorized) external onlyOwner {
        authorizedIndexers[indexer] = authorized;
        emit SetAuthorizedIndexer(indexer, authorized);
    }

    /// =================================================================================
    /// Existing X509CRLHelper ABI
    /// =================================================================================

    function getTbsAndSig(bytes calldata der) external pure returns (bytes memory tbs, bytes memory sig) {
        CrlLayout memory layout = _locateCrl(der);
        tbs = _copyNode(der, layout.tbs, true);
        sig = _getSignature(der, layout.signature);
    }

    function getIssuerCommonName(bytes calldata der) external pure returns (string memory issuerCommonName) {
        CrlLayout memory layout = _locateCrl(der);
        issuerCommonName = _getCommonName(der, layout.issuer);
    }

    function getCrlValidity(bytes calldata der)
        external
        pure
        returns (uint256 validityNotBefore, uint256 validityNotAfter)
    {
        CrlLayout memory layout = _locateCrl(der);
        validityNotBefore = _parseTime(der, layout.thisUpdate);
        validityNotAfter = _parseTime(der, layout.nextUpdate);
    }

    function serialNumberIsRevoked(uint256 serialNumber, bytes calldata der) external view returns (bool revoked) {
        bytes32 derHash = keccak256(der);
        bytes32 revokedSetHash = crlRevokedSetHashes[derHash];
        if (indexedRevokedSets[revokedSetHash]) {
            return _revokedSerials[revokedSetHash][serialNumber];
        }

        // Safe migration fallback for a CRL that was stored before V2 was
        // deployed. Once that CRL is upserted through PcsDaoV2, this path is no
        // longer used and membership becomes an O(1) storage lookup.
        CrlLayout memory layout = _locateCrl(der);

        // Validate all non-list fields too, so malformed input cannot silently
        // turn into a negative revocation result.
        _getCommonName(der, layout.issuer);
        _parseTime(der, layout.thisUpdate);
        _parseTime(der, layout.nextUpdate);
        _getAuthorityKeyIdentifier(der, layout.extensions);
        _getSignature(der, layout.signature);

        if (layout.hasRevokedCertificates) {
            revoked = _containsSerial(der, layout.revokedCertificates, serialNumber);
        }
    }

    /// @dev Returns an empty value when the extension is not present, matching V1 semantics.
    function getAuthorityKeyIdentifier(bytes calldata der) external pure returns (bytes memory akid) {
        CrlLayout memory layout = _locateCrl(der);
        akid = _getAuthorityKeyIdentifier(der, layout.extensions);
    }

    function parseCRLDER(bytes calldata der) external pure returns (X509CRLObj memory crl) {
        CrlLayout memory layout = _locateCrl(der);
        crl.issuerCommonName = _getCommonName(der, layout.issuer);
        crl.validityNotBefore = _parseTime(der, layout.thisUpdate);
        crl.validityNotAfter = _parseTime(der, layout.nextUpdate);
        crl.authorityKeyIdentifier = _getAuthorityKeyIdentifier(der, layout.extensions);
        crl.signature = _getSignature(der, layout.signature);
        crl.tbs = _copyNode(der, layout.tbs, true);
        crl.serialNumbersRevoked = _getAllSerials(der, layout);
    }

    /// =================================================================================
    /// V2 upsert API
    /// =================================================================================

    function parseCRLMetadata(bytes calldata der) external pure returns (X509CRLMetadata memory metadata) {
        CrlLayout memory layout = _locateCrl(der);
        metadata = _metadataFromLayout(der, layout);

        if (layout.hasRevokedCertificates) {
            metadata.revokedCertificateCount = _countAndValidateSerials(der, layout.revokedCertificates);
        }
    }

    /**
     * @notice Strictly parses a CRL and makes its exact membership index available atomically.
     * @dev Membership storage is keyed by a domain-separated rolling hash of the
     * strictly parsed uint256 serial sequence. Reissues that keep the same ordered
     * serial set reuse the exact index even if revocation dates, entry metadata,
     * outer metadata, or the signature change. Any later revert in the authorized
     * PCS DAO also reverts these writes.
     */
    function parseAndIndexCRLMetadata(bytes calldata der)
        external
        onlyAuthorizedIndexer
        returns (X509CRLMetadata memory metadata)
    {
        CrlLayout memory layout = _locateCrl(der);
        metadata = _metadataFromLayout(der, layout);

        bytes32 derHash = keccak256(der);
        (bytes32 revokedSetHash, uint256[] memory serials) = _parseRevokedSerialSet(der, layout);
        crlRevokedSetHashes[derHash] = revokedSetHash;

        bool reused = indexedRevokedSets[revokedSetHash];
        metadata.revokedCertificateCount = serials.length;
        if (reused) {
            if (revokedSetCounts[revokedSetHash] != serials.length) revert Invalid_DER();
        } else {
            for (uint256 i = 0; i < serials.length; i++) {
                _revokedSerials[revokedSetHash][serials[i]] = true;
            }
            revokedSetCounts[revokedSetHash] = metadata.revokedCertificateCount;
            indexedRevokedSets[revokedSetHash] = true;
        }

        emit IndexedCrl(derHash, revokedSetHash, metadata.revokedCertificateCount, reused);
    }

    /// @notice Reports whether the exact DER is bound to a complete shared membership index.
    function indexedCrls(bytes32 derHash) public view returns (bool) {
        return indexedRevokedSets[crlRevokedSetHashes[derHash]];
    }

    function _metadataFromLayout(bytes calldata der, CrlLayout memory layout)
        private
        pure
        returns (X509CRLMetadata memory metadata)
    {
        metadata.issuerCommonName = _getCommonName(der, layout.issuer);
        metadata.validityNotBefore = _parseTime(der, layout.thisUpdate);
        metadata.validityNotAfter = _parseTime(der, layout.nextUpdate);
        metadata.authorityKeyIdentifier = _getAuthorityKeyIdentifier(der, layout.extensions);
        metadata.signature = _getSignature(der, layout.signature);

        bytes memory tbs = _copyNode(der, layout.tbs, true);
        metadata.tbsHash = keccak256(tbs);
        metadata.tbsSha256 = sha256(tbs);
    }

    function _parseRevokedSerialSet(bytes calldata der, CrlLayout memory layout)
        private
        pure
        returns (bytes32 revokedSetHash, uint256[] memory serials)
    {
        bytes32 rollingHash = keccak256("X509CRLHelperV2.revokedSerialSet.v1");
        if (!layout.hasRevokedCertificates) {
            serials = new uint256[](0);
            return (keccak256(abi.encodePacked(rollingHash, uint256(0))), serials);
        }

        // A valid entry needs at least a SEQUENCE header, a one-byte positive
        // INTEGER, and a UTCTime. This keeps the temporary array proportional
        // to the maximum possible entry count instead of the CRL byte length.
        uint256 listLength = layout.revokedCertificates.end - layout.revokedCertificates.content;
        uint256 maxCount = listLength / 20 + 1;
        serials = new uint256[](maxCount);

        uint256 cursor = layout.revokedCertificates.content;
        uint256 count;
        while (cursor < layout.revokedCertificates.end) {
            Node memory entry = _readNode(der, cursor, layout.revokedCertificates.end);
            uint256 serial = _validateRevokedEntry(der, entry);
            if (count == maxCount) revert Invalid_DER();
            serials[count++] = serial;
            rollingHash = keccak256(abi.encodePacked(rollingHash, serial));
            cursor = entry.end;
        }
        if (cursor != layout.revokedCertificates.end) revert Invalid_DER();

        assembly ("memory-safe") {
            mstore(serials, count)
        }
        revokedSetHash = keccak256(abi.encodePacked(rollingHash, count));
    }

    /// =================================================================================
    /// CRL layout and DER validation
    /// =================================================================================

    function _locateCrl(bytes calldata der) private pure returns (CrlLayout memory layout) {
        if (der.length == 0) revert Invalid_DER();

        layout.outer = _readNode(der, 0, der.length);
        _requireTag(der, layout.outer, 0x30);
        if (layout.outer.end != der.length) revert Invalid_DER();

        uint256 cursor = layout.outer.content;
        layout.tbs = _readNode(der, cursor, layout.outer.end);
        _requireTag(der, layout.tbs, 0x30);

        cursor = layout.tbs.end;
        Node memory outerAlgorithm = _readNode(der, cursor, layout.outer.end);
        _validateSignatureAlgorithm(der, outerAlgorithm);

        cursor = outerAlgorithm.end;
        layout.signature = _readNode(der, cursor, layout.outer.end);
        _requireTag(der, layout.signature, 0x03);
        if (layout.signature.end != layout.outer.end) revert Invalid_DER();

        cursor = layout.tbs.content;
        Node memory version = _readNode(der, cursor, layout.tbs.end);
        _requireTag(der, version, 0x02);
        if (_readPositiveInteger(der, version, false) != 1) revert Invalid_CRL_Profile();

        cursor = version.end;
        Node memory tbsAlgorithm = _readNode(der, cursor, layout.tbs.end);
        _validateSignatureAlgorithm(der, tbsAlgorithm);

        cursor = tbsAlgorithm.end;
        layout.issuer = _readNode(der, cursor, layout.tbs.end);
        _requireTag(der, layout.issuer, 0x30);

        cursor = layout.issuer.end;
        layout.thisUpdate = _readNode(der, cursor, layout.tbs.end);
        _requireTimeNode(der, layout.thisUpdate);

        cursor = layout.thisUpdate.end;
        layout.nextUpdate = _readNode(der, cursor, layout.tbs.end);
        _requireTimeNode(der, layout.nextUpdate);

        cursor = layout.nextUpdate.end;
        Node memory next = _readNode(der, cursor, layout.tbs.end);
        if (_tag(der, next) == 0x30) {
            layout.hasRevokedCertificates = true;
            layout.revokedCertificates = next;
            cursor = next.end;
            next = _readNode(der, cursor, layout.tbs.end);
        }

        layout.extensions = next;
        _requireTag(der, layout.extensions, 0xA0);
        if (layout.extensions.end != layout.tbs.end) revert Invalid_DER();
    }

    function _validateSignatureAlgorithm(bytes calldata der, Node memory algorithm) private pure {
        _requireTag(der, algorithm, 0x30);
        Node memory oid = _readNode(der, algorithm.content, algorithm.end);
        _requireTag(der, oid, 0x06);
        if (oid.end != algorithm.end || oid.end - oid.content != 8) revert Invalid_CRL_Profile();

        bytes32 word = _wordAt(der, oid.content);
        if (bytes8(word) != ECDSA_WITH_SHA256_OID) revert Invalid_CRL_Profile();
    }

    function _requireTimeNode(bytes calldata der, Node memory node) private pure {
        uint8 tag = _tag(der, node);
        uint256 length = node.end - node.content;
        if (!((tag == 0x17 && length == 13) || (tag == 0x18 && length == 15))) {
            revert Invalid_CRL_Profile();
        }
    }

    function _parseTime(bytes calldata der, Node memory node) private pure returns (uint256 timestamp) {
        _validateTimeEncoding(der, node);
        timestamp = DateTimeUtils.fromDERToTimestamp(_copyContent(der, node));
    }

    function _validateTimeEncoding(bytes calldata der, Node memory node) private pure {
        _requireTimeNode(der, node);
        uint256 length = node.end - node.content;
        for (uint256 i = 0; i < length - 1; i++) {
            uint8 char = uint8(der[node.content + i]);
            if (char < 0x30 || char > 0x39) revert Invalid_DER();
        }
        if (der[node.end - 1] != 0x5A) revert Invalid_DER();

        uint256 cursor = node.content;
        uint256 year;
        if (length == 13) {
            year = _decimalPair(der, cursor);
            year += year < 50 ? 2000 : 1900;
            cursor += 2;
        } else {
            year = _decimalPair(der, cursor) * 100 + _decimalPair(der, cursor + 2);
            cursor += 4;
        }

        uint256 month = _decimalPair(der, cursor);
        uint256 day = _decimalPair(der, cursor + 2);
        uint256 hour = _decimalPair(der, cursor + 4);
        uint256 minute = _decimalPair(der, cursor + 6);
        uint256 second = _decimalPair(der, cursor + 8);
        if (!DateTimeLib.isSupportedDateTime(year, month, day, hour, minute, second)) revert Invalid_DER();
    }

    function _getCommonName(bytes calldata der, Node memory issuer) private pure returns (string memory commonName) {
        bool found;
        uint256 rdnCursor = issuer.content;
        while (rdnCursor < issuer.end) {
            Node memory rdn = _readNode(der, rdnCursor, issuer.end);
            _requireTag(der, rdn, 0x31);

            uint256 attributeCursor = rdn.content;
            while (attributeCursor < rdn.end) {
                Node memory attribute = _readNode(der, attributeCursor, rdn.end);
                _requireTag(der, attribute, 0x30);

                Node memory oid = _readNode(der, attribute.content, attribute.end);
                _requireTag(der, oid, 0x06);
                Node memory value = _readNode(der, oid.end, attribute.end);
                if (value.end != attribute.end || (_tag(der, value) & 0x20) != 0) revert Invalid_DER();

                if (!found && _contentEquals3(der, oid, COMMON_NAME_OID)) {
                    commonName = string(_copyContent(der, value));
                    found = true;
                }
                attributeCursor = attribute.end;
            }
            if (attributeCursor != rdn.end) revert Invalid_DER();
            rdnCursor = rdn.end;
        }
        if (rdnCursor != issuer.end) revert Invalid_DER();
        if (!found) revert Missing_Common_Name();
    }

    function _getAuthorityKeyIdentifier(bytes calldata der, Node memory explicitExtensions)
        private
        pure
        returns (bytes memory akid)
    {
        Node memory extensions = _readNode(der, explicitExtensions.content, explicitExtensions.end);
        _requireTag(der, extensions, 0x30);
        if (extensions.end != explicitExtensions.end) revert Invalid_DER();

        uint256 cursor = extensions.content;
        while (cursor < extensions.end) {
            Node memory extension = _readNode(der, cursor, extensions.end);
            _requireTag(der, extension, 0x30);

            Node memory oid = _readNode(der, extension.content, extension.end);
            _requireTag(der, oid, 0x06);
            Node memory value = _readNode(der, oid.end, extension.end);
            if (_tag(der, value) == 0x01) {
                if (value.end - value.content != 1) revert Invalid_DER();
                uint8 booleanValue = uint8(der[value.content]);
                if (booleanValue != 0x00 && booleanValue != 0xFF) revert Invalid_DER();
                value = _readNode(der, value.end, extension.end);
            }
            _requireTag(der, value, 0x04);
            if (value.end != extension.end) revert Invalid_DER();

            if (_contentEquals3(der, oid, AUTHORITY_KEY_IDENTIFIER_OID)) {
                akid = _decodeAuthorityKeyIdentifier(der, value);
            }
            cursor = extension.end;
        }
        if (cursor != extensions.end) revert Invalid_DER();
    }

    function _decodeAuthorityKeyIdentifier(bytes calldata der, Node memory octetString)
        private
        pure
        returns (bytes memory akid)
    {
        Node memory sequence = _readNode(der, octetString.content, octetString.end);
        _requireTag(der, sequence, 0x30);
        if (sequence.end != octetString.end) revert Invalid_DER();

        uint256 cursor = sequence.content;
        while (cursor < sequence.end) {
            Node memory field = _readNode(der, cursor, sequence.end);
            if (_tag(der, field) == 0x80) {
                akid = _copyContent(der, field);
            }
            cursor = field.end;
        }
        if (cursor != sequence.end) revert Invalid_DER();
    }

    function _getSignature(bytes calldata der, Node memory bitString) private pure returns (bytes memory signature) {
        if (bitString.end - bitString.content < 2 || der[bitString.content] != 0x00) revert Invalid_DER();

        Node memory sequence = _readNode(der, bitString.content + 1, bitString.end);
        _requireTag(der, sequence, 0x30);
        if (sequence.end != bitString.end) revert Invalid_DER();

        Node memory rNode = _readNode(der, sequence.content, sequence.end);
        Node memory sNode = _readNode(der, rNode.end, sequence.end);
        if (sNode.end != sequence.end) revert Invalid_DER();

        uint256 r = _readPositiveInteger(der, rNode, true);
        uint256 s = _readPositiveInteger(der, sNode, true);
        signature = abi.encodePacked(bytes32(r), bytes32(s));
    }

    /// =================================================================================
    /// Revoked certificate list scanning
    /// =================================================================================

    function _containsSerial(bytes calldata der, Node memory revokedCertificates, uint256 target)
        private
        pure
        returns (bool found)
    {
        uint256 cursor = revokedCertificates.content;
        while (cursor < revokedCertificates.end) {
            Node memory entry = _readNode(der, cursor, revokedCertificates.end);
            uint256 serial = _validateRevokedEntry(der, entry);
            if (serial == target) found = true;
            cursor = entry.end;
        }
        if (cursor != revokedCertificates.end) revert Invalid_DER();
    }

    function _countAndValidateSerials(bytes calldata der, Node memory revokedCertificates)
        private
        pure
        returns (uint256 count)
    {
        uint256 cursor = revokedCertificates.content;
        while (cursor < revokedCertificates.end) {
            Node memory entry = _readNode(der, cursor, revokedCertificates.end);
            _validateRevokedEntry(der, entry);
            count++;
            cursor = entry.end;
        }
        if (cursor != revokedCertificates.end) revert Invalid_DER();
    }

    function _getAllSerials(bytes calldata der, CrlLayout memory layout)
        private
        pure
        returns (uint256[] memory serials)
    {
        if (!layout.hasRevokedCertificates) return new uint256[](0);

        uint256 count = _countAndValidateSerials(der, layout.revokedCertificates);
        serials = new uint256[](count);

        uint256 cursor = layout.revokedCertificates.content;
        uint256 index;
        while (cursor < layout.revokedCertificates.end) {
            Node memory entry = _readNode(der, cursor, layout.revokedCertificates.end);
            serials[index++] = _validateRevokedEntry(der, entry);
            cursor = entry.end;
        }
    }

    function _validateRevokedEntry(bytes calldata der, Node memory entry) private pure returns (uint256 serial) {
        _requireTag(der, entry, 0x30);
        Node memory serialNode = _readNode(der, entry.content, entry.end);
        serial = _readPositiveInteger(der, serialNode, true);

        Node memory revocationDate = _readNode(der, serialNode.end, entry.end);
        _validateTimeEncoding(der, revocationDate);

        uint256 cursor = revocationDate.end;
        if (cursor < entry.end) {
            Node memory entryExtensions = _readNode(der, cursor, entry.end);
            _validateExtensionSequence(der, entryExtensions);
            cursor = entryExtensions.end;
        }
        if (cursor != entry.end) revert Invalid_DER();
    }

    function _validateExtensionSequence(bytes calldata der, Node memory extensions) private pure {
        _requireTag(der, extensions, 0x30);
        uint256 cursor = extensions.content;
        while (cursor < extensions.end) {
            Node memory extension = _readNode(der, cursor, extensions.end);
            _requireTag(der, extension, 0x30);

            Node memory oid = _readNode(der, extension.content, extension.end);
            _requireTag(der, oid, 0x06);
            Node memory value = _readNode(der, oid.end, extension.end);
            if (_tag(der, value) == 0x01) {
                if (value.end - value.content != 1) revert Invalid_DER();
                uint8 booleanValue = uint8(der[value.content]);
                if (booleanValue != 0x00 && booleanValue != 0xFF) revert Invalid_DER();
                value = _readNode(der, value.end, extension.end);
            }
            _requireTag(der, value, 0x04);
            if (value.end != extension.end) revert Invalid_DER();
            cursor = extension.end;
        }
        if (cursor != extensions.end) revert Invalid_DER();
    }

    /// =================================================================================
    /// Minimal calldata-native DER primitives
    /// =================================================================================

    function _readNode(bytes calldata der, uint256 start, uint256 limit) private pure returns (Node memory node) {
        if (limit > der.length || start >= limit || limit - start < 2) revert Invalid_DER();
        if ((uint8(der[start]) & 0x1F) == 0x1F) revert Invalid_CRL_Profile();

        uint256 firstLengthByte = uint8(der[start + 1]);
        uint256 contentLength;
        uint256 headerLength;
        if ((firstLengthByte & 0x80) == 0) {
            contentLength = firstLengthByte;
            headerLength = 2;
        } else {
            uint256 lengthByteCount = firstLengthByte & 0x7F;
            if (lengthByteCount == 0 || lengthByteCount > 4 || limit - start < 2 + lengthByteCount) {
                revert Invalid_DER();
            }
            if (der[start + 2] == 0x00) revert Invalid_DER();
            for (uint256 i = 0; i < lengthByteCount; i++) {
                contentLength = (contentLength << 8) | uint8(der[start + 2 + i]);
            }
            if (contentLength < 128) revert Invalid_DER();
            headerLength = 2 + lengthByteCount;
        }
        if (contentLength == 0) revert Invalid_DER();

        uint256 content = start + headerLength;
        if (content > limit || contentLength > limit - content) revert Invalid_DER();
        node = Node({start: start, content: content, end: content + contentLength});
    }

    function _readPositiveInteger(bytes calldata der, Node memory node, bool serial)
        private
        pure
        returns (uint256 value)
    {
        _requireTag(der, node, 0x02);
        uint256 cursor = node.content;
        uint256 length = node.end - cursor;
        if (length == 0) revert Invalid_DER();

        uint8 first = uint8(der[cursor]);
        if (first == 0) {
            if (length == 1 || (uint8(der[cursor + 1]) & 0x80) == 0) revert Invalid_DER();
            cursor++;
            length--;
        } else if ((first & 0x80) != 0) {
            revert Invalid_DER();
        }

        if (length > 32) {
            if (serial) revert Invalid_Serial_Number();
            revert Invalid_DER();
        }
        bytes32 word = _wordAt(der, cursor);
        value = uint256(word) >> ((32 - length) * 8);
        if (serial && value == 0) revert Invalid_Serial_Number();
    }

    function _requireTag(bytes calldata der, Node memory node, uint8 expected) private pure {
        if (_tag(der, node) != expected) revert Invalid_DER();
    }

    function _tag(bytes calldata der, Node memory node) private pure returns (uint8) {
        return uint8(der[node.start]);
    }

    function _contentEquals3(bytes calldata der, Node memory node, bytes3 expected) private pure returns (bool) {
        return node.end - node.content == 3 && bytes3(_wordAt(der, node.content)) == expected;
    }

    function _decimalPair(bytes calldata der, uint256 offset) private pure returns (uint256) {
        return (uint8(der[offset]) - 0x30) * 10 + uint8(der[offset + 1]) - 0x30;
    }

    function _wordAt(bytes calldata der, uint256 offset) private pure returns (bytes32 word) {
        assembly ("memory-safe") {
            word := calldataload(add(der.offset, offset))
        }
    }

    function _copyContent(bytes calldata der, Node memory node) private pure returns (bytes memory output) {
        return _copy(der, node.content, node.end - node.content);
    }

    function _copyNode(bytes calldata der, Node memory node, bool includeHeader)
        private
        pure
        returns (bytes memory output)
    {
        uint256 start = includeHeader ? node.start : node.content;
        output = _copy(der, start, node.end - start);
    }

    function _copy(bytes calldata der, uint256 start, uint256 length) private pure returns (bytes memory output) {
        output = new bytes(length);
        assembly ("memory-safe") {
            calldatacopy(add(output, 0x20), add(der.offset, start), length)
        }
    }
}
