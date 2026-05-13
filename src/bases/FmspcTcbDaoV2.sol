// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FmspcTcbDao} from "./FmspcTcbDao.sol";
import {AutomataDaoStorageV2} from "../automata_pccs/shared/AutomataDaoStorageV2.sol";
import {FmspcTcbHelperV2} from "../helpers/FmspcTcbHelperV2.sol";

import {CA} from "../Common.sol";
import {
    TcbInfoJsonObj,
    TcbId,
    TcbInfoBasic,
    TDXModule
} from "../helpers/FmspcTcbHelper.sol";

/**
 * @title FMSPC TCB Data Access Object V2
 * @notice Splits FMSPC TCBInfo upserts into async upload, parse, and finalize stages.
 */
abstract contract FmspcTcbDaoV2 is FmspcTcbDao {
    FmspcTcbHelperV2 public FmspcTcbLibV2;

    bytes32 private constant RAW_REF_TAG = keccak256("fmspcTcb.raw");
    bytes32 private constant PARSED_LEVELS_BATCH_REF_TAG = keccak256("fmspcTcb.parsedLevelsBatch");
    bytes32 private constant PARSED_MODULE_IDENTITIES_BATCH_REF_TAG = keccak256("fmspcTcb.parsedModuleIdentitiesBatch");
    bytes32 private constant HASH_REF_TAG = keccak256("fmspcTcb.hash");
    bytes32 private constant ISSUE_EVAL_REF_TAG = keccak256("fmspcTcb.issueEvaluation");
    bytes32 private constant CONTENT_HASH_REF_TAG = keccak256("fmspcTcb.contentHash");

    error Use_Async_Upsert();
    error Async_Upsert_Not_Started();
    error Async_Upsert_Finalized();
    error Async_Upsert_Incomplete();
    error Async_Upsert_Invalid_Range();
    error Async_Upsert_Invalid_Attestation_Id();
    error Async_Upsert_Missing_Signature();
    error Async_Upsert_Missing_Batch();

    struct AsyncRefs {
        bytes32 raw;
        bytes32 hash;
        bytes32 issueEvaluation;
        bytes32 contentHash;
    }

    struct AsyncUpsertState {
        bool started;
        bool basicParsed;
        bool finalized;
        bytes32 tcbKey;
        bytes32 rawHash;
        bytes32 contentHash;
        uint256 totalLevels;
        uint256 parsedLevels;
        uint256 totalModuleIdentities;
        uint256 parsedModuleIdentities;
        uint256 moduleIdentitiesCursor;
        TcbInfoBasic basic;
        TDXModule module;
        bytes signature;
        AsyncRefs refs;
    }

    mapping(bytes32 rootRefId => AsyncUpsertState state) internal _asyncUpserts;
    mapping(bytes32 tcbKey => bytes32 rootRefId) internal _finalizedAsyncRoots;
    mapping(bytes32 rootRefId => mapping(uint256 startIndex => uint256 batchSize)) internal _parsedLevelBatchSizes;
    mapping(bytes32 rootRefId => mapping(uint256 startIndex => uint256 batchSize)) internal _parsedModuleIdentityBatchSizes;

    constructor(
        address _resolver,
        address _p256,
        address _pcs,
        address _fmspcHelper,
        address _fmspcHelperV2,
        address _x509Helper,
        address _crlLib
    ) FmspcTcbDao(_resolver, _p256, _pcs, _fmspcHelper, _x509Helper, _crlLib) {
        FmspcTcbLibV2 = FmspcTcbHelperV2(_fmspcHelperV2);
    }

    function upsertFmspcTcb(TcbInfoJsonObj calldata) external pure virtual override returns (bytes32) {
        revert Use_Async_Upsert();
    }

    function startAsyncUpsert(bytes32 refId, bytes calldata signature) external virtual {
        _authorizeAsyncUpsert();
        _startAsyncUpsert(refId);
        _asyncUpserts[refId].signature = signature;
    }

    function uploadChunkData(bytes32 refId, bytes calldata chunkData) external virtual {
        _authorizeAsyncUpsert();
        _uploadChunkData(refId, chunkData);
    }

    function uploadParsedTcbLevelsBatch(bytes32 refId, uint256 start, string[] calldata rawLevelObjects)
        external
        virtual
        returns (uint256 parsed, uint256 total, bool complete)
    {
        _authorizeAsyncUpsert();
        AsyncUpsertState storage state = _requireAsyncUpsert(refId);
        if (state.finalized) revert Async_Upsert_Finalized();
        _ensureBasicParsed(refId, state);

        if (start != state.parsedLevels) revert Async_Upsert_Invalid_Range();
        bytes memory packed;
        (packed, parsed) = FmspcTcbLibV2.parseTcbLevelObjects(state.basic.version, rawLevelObjects);
        if (parsed == 0) revert Async_Upsert_Invalid_Range();
        _storeBatch(_deriveBatchRefId(refId, PARSED_LEVELS_BATCH_REF_TAG, start), packed);
        _parsedLevelBatchSizes[refId][start] = parsed;
        state.parsedLevels += parsed;
        total = state.totalLevels;
        complete = _parseComplete(state);
    }

    function uploadParsedTdxModuleIdentitiesBatch(bytes32 refId, uint256 start, string[] calldata rawIdentityObjects)
        external
        virtual
        returns (uint256 parsed, uint256 total, bool complete)
    {
        _authorizeAsyncUpsert();
        AsyncUpsertState storage state = _requireAsyncUpsert(refId);
        if (state.finalized) revert Async_Upsert_Finalized();
        _ensureBasicParsed(refId, state);

        if (state.basic.id != TcbId.TDX) revert Async_Upsert_Invalid_Range();
        if (start != state.parsedModuleIdentities) revert Async_Upsert_Invalid_Range();
        bytes memory packed;
        (packed, parsed) = FmspcTcbLibV2.parseTdxModuleIdentityObjects(rawIdentityObjects);
        if (parsed == 0) revert Async_Upsert_Invalid_Range();
        _storeBatch(_deriveBatchRefId(refId, PARSED_MODULE_IDENTITIES_BATCH_REF_TAG, start), packed);
        _parsedModuleIdentityBatchSizes[refId][start] = parsed;
        state.parsedModuleIdentities += parsed;
        total = state.totalModuleIdentities;
        complete = _parseComplete(state);
    }

    function finalizeAsyncUpsert(bytes32 attestationId, bytes32 refId) external virtual returns (bytes32) {
        _authorizeAsyncUpsert();
        AsyncUpsertState storage state = _requireAsyncUpsert(refId);
        if (state.finalized) revert Async_Upsert_Finalized();
        _ensureBasicParsed(refId, state);
        if (!_parseComplete(state)) revert Async_Upsert_Incomplete();

        bytes32 expectedAttestationId = resolver.collateralPointer(state.tcbKey);
        if (attestationId != expectedAttestationId) revert Async_Upsert_Invalid_Attestation_Id();

        bytes memory raw = _storageV2().readRef(state.refs.raw);
        bytes32 rawHash = sha256(raw);
        if (rawHash != state.rawHash) revert Async_Upsert_Incomplete();

        _checkCollateralDuplicate(state.tcbKey, rawHash);
        _validateTcbInfoV2(string(raw), state.signature);

        if (block.timestamp < state.basic.issueDate || block.timestamp > state.basic.nextUpdate) {
            revert TCB_Expired();
        }
        _checkTcbEvaluationData(state.tcbKey, state.basic);

        (, string memory levelsJson, string memory moduleJson, string memory moduleIdentitiesJson) = _loadParseInputs(state);
        state.contentHash = FmspcTcbLib.generateFmspcTcbContentHash(
            state.basic, levelsJson, moduleJson, moduleIdentitiesJson
        );

        _appendFinalRefs(state);
        _finalizeExternalRefs(refId, state);

        state.finalized = true;
        _finalizedAsyncRoots[state.tcbKey] = refId;

        emit UpsertedFmpscTcb(uint8(state.basic.id), state.basic.fmspc, state.basic.version);
        return attestationId;
    }

    function _onFetchDataFromResolver(bytes32 key, bool hash)
        internal
        view
        virtual
        override
        returns (bytes memory data)
    {
        return _fetchDataFromResolver(key, hash);
    }

    function _storeTcbInfoIssueEvaluation(bytes32, uint64, uint64, uint32) internal virtual override {}

    function _loadTcbInfoIssueEvaluation(bytes32 tcbKey)
        internal
        view
        virtual
        override
        returns (uint64 issueDateTimestamp, uint64 nextUpdateTimestamp, uint32 evaluationDataNumber)
    {
        bytes memory data = _fetchDataFromResolver(_computeTcbIssueEvaluationKey(tcbKey), false);
        if (data.length > 0) {
            (uint256 slot) = abi.decode(data, (uint256));
            issueDateTimestamp = uint64(slot >> 192);
            nextUpdateTimestamp = uint64(slot >> 128);
            evaluationDataNumber = uint32(slot);
        }
    }

    function _storeFmspcTcbContentHash(bytes32, bytes32) internal virtual override {}

    function _loadFmspcTcbContentHash(bytes32 tcbKey)
        internal
        view
        virtual
        override
        returns (bytes32 contentHash)
    {
        bytes memory data = _fetchDataFromResolver(_computeContentHashKey(tcbKey), false);
        if (data.length > 0) {
            contentHash = bytes32(data);
        }
    }

    function _authorizeAsyncUpsert() internal view virtual {}

    function _startAsyncUpsert(bytes32 refId) internal {
        AsyncUpsertState storage state = _asyncUpserts[refId];
        if (state.started) revert Async_Upsert_Finalized();

        state.started = true;
        state.refs = AsyncRefs({
            raw: _deriveRefId(refId, RAW_REF_TAG),
            hash: _deriveRefId(refId, HASH_REF_TAG),
            issueEvaluation: _deriveRefId(refId, ISSUE_EVAL_REF_TAG),
            contentHash: _deriveRefId(refId, CONTENT_HASH_REF_TAG)
        });

        AutomataDaoStorageV2 storageV2 = _storageV2();
        storageV2.startAsync(state.refs.raw);
        storageV2.startAsync(state.refs.hash);
        storageV2.startAsync(state.refs.issueEvaluation);
        storageV2.startAsync(state.refs.contentHash);

    }

    function _ensureBasicParsed(bytes32 refId, AsyncUpsertState storage state) internal {
        if (state.basicParsed) {
            return;
        }

        bytes memory raw = _storageV2().readRef(state.refs.raw);
        if (raw.length == 0) revert Async_Upsert_Incomplete();

        (
            TcbInfoBasic memory basic,
            string memory tcbLevelsString,
            string memory tdxModuleString,
            string memory tdxModuleIdentitiesString
        ) = FmspcTcbLib.parseTcbString(string(raw));

        state.basic = basic;
        state.tcbKey = FMSPC_TCB_KEY(uint8(basic.id), basic.fmspc, basic.version);
        state.rawHash = sha256(raw);

        if (bytes(tdxModuleString).length > 0) {
            state.module = FmspcTcbLib.parseTdxModule(tdxModuleString);
        }

        state.totalLevels = FmspcTcbLibV2.countTcbLevels(tcbLevelsString);
        if (basic.id == TcbId.TDX) {
            state.totalModuleIdentities = FmspcTcbLibV2.countTdxModuleIdentities(tdxModuleIdentitiesString);
            state.moduleIdentitiesCursor = 0;
        }

        state.basicParsed = true;
    }

    function _uploadChunkData(bytes32 refId, bytes calldata chunkData) internal {
        AsyncUpsertState storage state = _requireAsyncUpsert(refId);
        if (state.finalized) revert Async_Upsert_Finalized();
        _storageV2().appendAttestation(state.refs.raw, chunkData);
    }

    function _appendFinalRefs(AsyncUpsertState storage state) internal {
        uint256 issueSlot = (uint256(state.basic.issueDate) << 192) | (uint256(state.basic.nextUpdate) << 128)
            | state.basic.evaluationDataNumber;

        _storageV2().appendAttestation(state.refs.hash, abi.encodePacked(state.rawHash));
        _storageV2().appendAttestation(state.refs.issueEvaluation, abi.encode(issueSlot));
        _storageV2().appendAttestation(state.refs.contentHash, abi.encodePacked(state.contentHash));
    }

    function _finalizeExternalRefs(bytes32 refId, AsyncUpsertState storage state) internal {
        AutomataDaoStorageV2 storageV2 = _storageV2();
        bytes32 key = state.tcbKey;

        storageV2.finalizeAsync(resolver.collateralHashPointer(key), state.refs.hash);
        storageV2.finalizeAsync(resolver.collateralPointer(_computeTcbIssueEvaluationKey(key)), state.refs.issueEvaluation);
        storageV2.finalizeAsync(resolver.collateralPointer(_computeContentHashKey(key)), state.refs.contentHash);

        storageV2.finalizeAsync(_deriveRefId(refId, RAW_REF_TAG), state.refs.raw);
    }

    function _loadAsyncFinalPayload(bytes32 key) internal view returns (bytes memory payload) {
        bytes32 refId = _finalizedAsyncRoots[key];
        if (refId == bytes32(0)) {
            return payload;
        }

        AsyncUpsertState storage state = _asyncUpserts[refId];
        if (!state.finalized) {
            return payload;
        }

        payload = _buildFinalPayload(refId, state);
    }

    function _loadParseInputs(AsyncUpsertState storage state)
        internal
        view
        returns (
            TcbInfoBasic memory basic,
            string memory tcbLevelsString,
            string memory tdxModuleString,
            string memory tdxModuleIdentitiesString
        )
    {
        bytes memory raw = _storageV2().readRef(state.refs.raw);
        (basic, tcbLevelsString, tdxModuleString, tdxModuleIdentitiesString) = FmspcTcbLib.parseTcbString(string(raw));
    }

    function _validateTcbInfoV2(string memory tcbInfoStr, bytes memory signature) internal view {
        if (signature.length == 0) revert Async_Upsert_Missing_Signature();

        bytes32 issuerKey = Pcs.PCS_KEY(CA.SIGNING, false);
        (uint256 issuerNotValidBefore, uint256 issuerNotValidAfter) = Pcs.getCollateralValidity(issuerKey);
        if (block.timestamp < issuerNotValidBefore || block.timestamp > issuerNotValidAfter) {
            revert TCB_Cert_Expired();
        }

        bytes memory signingDer = _fetchDataFromResolver(issuerKey, false);
        if (signingDer.length == 0) {
            revert Missing_TCB_Cert();
        }

        bytes memory rootCrl = _fetchDataFromResolver(Pcs.PCS_KEY(CA.ROOT, true), false);
        if (rootCrl.length > 0) {
            (bool snSuccess, bytes memory serialNumberData) =
                x509.staticcall(abi.encodeWithSelector(0xb29b51cb, signingDer));
            require(snSuccess, "Failed to get serial number");
            uint256 serialNumber = abi.decode(serialNumberData, (uint256));
            (bool crlSuccess, bytes memory serialNumberRevokedData) =
                crlLibAddr.staticcall(abi.encodeWithSelector(0xcedb9781, serialNumber, rootCrl));
            require(crlSuccess, "Failed to check CRL revocation");
            bool revoked = abi.decode(serialNumberRevokedData, (bool));
            if (revoked) {
                revert TCB_Cert_Revoked(serialNumber);
            }
        }

        bool sigVerified = verifySignature(sha256(bytes(tcbInfoStr)), signature, signingDer);
        if (!sigVerified) {
            revert Invalid_TCB_Cert_Signature();
        }
    }

    function _buildFinalPayload(bytes32 refId, AsyncUpsertState storage state) internal view returns (bytes memory reqData) {
        bytes memory raw = _storageV2().readRef(state.refs.raw);
        bytes memory encodedTcbLevels = _encodeLengthPrefixedStream(
            _loadBatchStream(refId, PARSED_LEVELS_BATCH_REF_TAG, state.totalLevels, true), state.totalLevels
        );
        TcbInfoJsonObj memory tcbInfoObj = TcbInfoJsonObj({tcbInfoStr: string(raw), signature: state.signature});

        if (state.basic.version < 3) {
            reqData = abi.encode(state.basic, encodedTcbLevels, tcbInfoObj);
        } else {
            bytes memory encodedModuleIdentities;
            if (state.totalModuleIdentities > 0) {
                encodedModuleIdentities = _encodeLengthPrefixedStream(
                    _loadBatchStream(
                        refId, PARSED_MODULE_IDENTITIES_BATCH_REF_TAG, state.totalModuleIdentities, false
                    ),
                    state.totalModuleIdentities
                );
            }
            reqData = abi.encode(state.basic, state.module, encodedModuleIdentities, encodedTcbLevels, tcbInfoObj);
        }
    }

    function _encodeLengthPrefixedStream(bytes memory stream, uint256 expectedItems)
        internal
        pure
        returns (bytes memory encoded)
    {
        bytes[] memory items = new bytes[](expectedItems);
        uint256 cursor;
        for (uint256 i = 0; i < expectedItems; i++) {
            if (cursor + 4 > stream.length) revert Async_Upsert_Incomplete();
            uint256 itemLength = _readUint32(stream, cursor);
            cursor += 4;
            if (cursor + itemLength > stream.length) revert Async_Upsert_Incomplete();
            bytes memory item = new bytes(itemLength);
            for (uint256 j = 0; j < itemLength; j++) {
                item[j] = stream[cursor + j];
            }
            cursor += itemLength;
            items[i] = item;
        }
        if (cursor != stream.length) revert Async_Upsert_Incomplete();
        encoded = abi.encode(items);
    }

    function _readUint32(bytes memory data, uint256 offset) internal pure returns (uint32 value) {
        value = (uint32(uint8(data[offset])) << 24) | (uint32(uint8(data[offset + 1])) << 16)
            | (uint32(uint8(data[offset + 2])) << 8) | uint32(uint8(data[offset + 3]));
    }

    function _parseComplete(AsyncUpsertState storage state) internal view returns (bool) {
        return state.basicParsed && state.parsedLevels == state.totalLevels
            && (state.basic.id != TcbId.TDX || state.parsedModuleIdentities == state.totalModuleIdentities);
    }

    function _storeBatch(bytes32 refId, bytes memory packed) internal {
        AutomataDaoStorageV2 storageV2 = _storageV2();
        storageV2.startAsync(refId);
        storageV2.appendAttestation(refId, packed);
    }

    function _loadBatchStream(bytes32 rootRefId, bytes32 tag, uint256 expectedItems, bool levels)
        internal
        view
        returns (bytes memory stream)
    {
        uint256 cursor;
        while (cursor < expectedItems) {
            uint256 batchSize =
                levels ? _parsedLevelBatchSizes[rootRefId][cursor] : _parsedModuleIdentityBatchSizes[rootRefId][cursor];
            if (batchSize == 0) revert Async_Upsert_Missing_Batch();
            bytes32 batchRefId = _deriveBatchRefId(rootRefId, tag, cursor);
            stream = bytes.concat(stream, _storageV2().readRef(batchRefId));
            cursor += batchSize;
        }
    }

    function _requireAsyncUpsert(bytes32 refId) internal view returns (AsyncUpsertState storage state) {
        state = _asyncUpserts[refId];
        if (!state.started) revert Async_Upsert_Not_Started();
    }

    function _storageV2() internal view returns (AutomataDaoStorageV2) {
        return AutomataDaoStorageV2(address(resolver));
    }

    function _deriveRefId(bytes32 rootRefId, bytes32 tag) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(rootRefId, tag));
    }

    function _deriveBatchRefId(bytes32 rootRefId, bytes32 tag, uint256 startIndex) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(rootRefId, tag, startIndex));
    }

    function _computeTcbIssueEvaluationKey(bytes32 key) internal pure returns (bytes32 ret) {
        ret = keccak256(abi.encodePacked(key, "tcbIssueEvaluation"));
    }

    function _computeContentHashKey(bytes32 key) internal pure returns (bytes32 ret) {
        ret = keccak256(abi.encodePacked(key, "fmspcTcbContentHash"));
    }
}
