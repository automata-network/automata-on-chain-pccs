// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FmspcTcbDao} from "./FmspcTcbDao.sol";
import {AutomataDaoStorageV2} from "../automata_pccs/shared/AutomataDaoStorageV2.sol";

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
    bytes32 private constant RAW_REF_TAG = keccak256("fmspcTcb.raw");
    bytes32 private constant LEVELS_JSON_REF_TAG = keccak256("fmspcTcb.levelsJson");
    bytes32 private constant TDX_MODULE_JSON_REF_TAG = keccak256("fmspcTcb.tdxModuleJson");
    bytes32 private constant TDX_MODULE_IDENTITIES_JSON_REF_TAG = keccak256("fmspcTcb.tdxModuleIdentitiesJson");
    bytes32 private constant PARSED_LEVELS_REF_TAG = keccak256("fmspcTcb.parsedLevels");
    bytes32 private constant PARSED_MODULE_IDENTITIES_REF_TAG = keccak256("fmspcTcb.parsedModuleIdentities");
    bytes32 private constant PAYLOAD_REF_TAG = keccak256("fmspcTcb.payload");
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

    struct AsyncRefs {
        bytes32 raw;
        bytes32 levelsJson;
        bytes32 tdxModuleJson;
        bytes32 tdxModuleIdentitiesJson;
        bytes32 parsedLevels;
        bytes32 parsedModuleIdentities;
        bytes32 payload;
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
        TcbInfoBasic basic;
        TDXModule module;
        bytes signature;
        AsyncRefs refs;
    }

    mapping(bytes32 rootRefId => AsyncUpsertState state) internal _asyncUpserts;

    event StartedAsyncFmspcTcbUpsert(bytes32 indexed refId);
    event UploadedAsyncFmspcTcbChunk(bytes32 indexed refId, uint256 chunkLength);
    event ParsedAsyncFmspcTcbInfo(bytes32 indexed refId, uint256 parsed, uint256 total, bool complete);
    event FinalizedAsyncFmspcTcbUpsert(bytes32 indexed refId, bytes32 indexed attestationId);

    constructor(
        address _resolver,
        address _p256,
        address _pcs,
        address _fmspcHelper,
        address _x509Helper,
        address _crlLib
    ) FmspcTcbDao(_resolver, _p256, _pcs, _fmspcHelper, _x509Helper, _crlLib) {}

    function upsertFmspcTcb(TcbInfoJsonObj calldata) external pure virtual override returns (bytes32) {
        revert Use_Async_Upsert();
    }

    function startAsyncUpsert(bytes32 refId) external virtual {
        _authorizeAsyncUpsert();
        _startAsyncUpsert(refId);
    }

    function startAsyncUpsert(bytes32 refId, bytes calldata signature) external virtual {
        _authorizeAsyncUpsert();
        _startAsyncUpsert(refId);
        _asyncUpserts[refId].signature = signature;
    }

    function setAsyncUpsertSignature(bytes32 refId, bytes calldata signature) external virtual {
        _authorizeAsyncUpsert();
        AsyncUpsertState storage state = _requireAsyncUpsert(refId);
        if (state.finalized) revert Async_Upsert_Finalized();
        state.signature = signature;
    }

    function uploadChunckData(bytes32 refId, bytes calldata chunkData) external virtual {
        _authorizeAsyncUpsert();
        AsyncUpsertState storage state = _requireAsyncUpsert(refId);
        if (state.finalized) revert Async_Upsert_Finalized();
        _storageV2().appendAttestation(state.refs.raw, chunkData);
        emit UploadedAsyncFmspcTcbChunk(refId, chunkData.length);
    }

    function uploadChunkData(bytes32 refId, bytes calldata chunkData) external virtual {
        _authorizeAsyncUpsert();
        AsyncUpsertState storage state = _requireAsyncUpsert(refId);
        if (state.finalized) revert Async_Upsert_Finalized();
        _storageV2().appendAttestation(state.refs.raw, chunkData);
        emit UploadedAsyncFmspcTcbChunk(refId, chunkData.length);
    }

    function parseTCBInfo(bytes32 refId, uint256 start, uint256 offset)
        external
        virtual
        returns (uint256 parsed, uint256 total, bool complete)
    {
        _authorizeAsyncUpsert();
        AsyncUpsertState storage state = _requireAsyncUpsert(refId);
        if (state.finalized) revert Async_Upsert_Finalized();
        _ensureBasicParsed(refId, state);

        if (state.parsedLevels < state.totalLevels) {
            if (start != state.parsedLevels) revert Async_Upsert_Invalid_Range();
            bytes memory levelsJson = _storageV2().readRef(state.refs.levelsJson);
            bytes memory packed;
            (packed, total, parsed) =
                FmspcTcbLib.parseTcbLevelsRange(state.basic.version, string(levelsJson), start, offset);
            if (total != state.totalLevels || parsed == 0) revert Async_Upsert_Invalid_Range();
            _storageV2().appendAttestation(state.refs.parsedLevels, packed);
            state.parsedLevels += parsed;
            complete = _parseComplete(state);
            emit ParsedAsyncFmspcTcbInfo(refId, state.parsedLevels, state.totalLevels, complete);
            return (parsed, total, complete);
        }

        if (state.basic.id == TcbId.TDX && state.parsedModuleIdentities < state.totalModuleIdentities) {
            if (start != state.parsedModuleIdentities) revert Async_Upsert_Invalid_Range();
            bytes memory identitiesJson = _storageV2().readRef(state.refs.tdxModuleIdentitiesJson);
            bytes memory packed;
            (packed, total, parsed) = FmspcTcbLib.parseTdxModuleIdentitiesRange(string(identitiesJson), start, offset);
            if (total != state.totalModuleIdentities || parsed == 0) revert Async_Upsert_Invalid_Range();
            _storageV2().appendAttestation(state.refs.parsedModuleIdentities, packed);
            state.parsedModuleIdentities += parsed;
            complete = _parseComplete(state);
            emit ParsedAsyncFmspcTcbInfo(refId, state.parsedModuleIdentities, state.totalModuleIdentities, complete);
            return (parsed, total, complete);
        }

        complete = true;
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

        bytes memory levelsJson = _storageV2().readRef(state.refs.levelsJson);
        bytes memory moduleJson = _storageV2().readRef(state.refs.tdxModuleJson);
        bytes memory moduleIdentitiesJson = _storageV2().readRef(state.refs.tdxModuleIdentitiesJson);
        state.contentHash = FmspcTcbLib.generateFmspcTcbContentHash(
            state.basic, string(levelsJson), string(moduleJson), string(moduleIdentitiesJson)
        );

        _appendFinalRefs(state);
        _finalizeExternalRefs(refId, state);

        state.finalized = true;

        emit UpsertedFmpscTcb(uint8(state.basic.id), state.basic.fmspc, state.basic.version);
        emit FinalizedAsyncFmspcTcbUpsert(refId, attestationId);
        return attestationId;
    }

    function asyncUpsertProgress(bytes32 refId)
        external
        view
        returns (
            bool started,
            bool basicParsed,
            bool finalized,
            bytes32 tcbKey,
            uint256 parsedLevels,
            uint256 totalLevels,
            uint256 parsedModuleIdentities,
            uint256 totalModuleIdentities
        )
    {
        AsyncUpsertState storage state = _asyncUpserts[refId];
        return (
            state.started,
            state.basicParsed,
            state.finalized,
            state.tcbKey,
            state.parsedLevels,
            state.totalLevels,
            state.parsedModuleIdentities,
            state.totalModuleIdentities
        );
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
            levelsJson: _deriveRefId(refId, LEVELS_JSON_REF_TAG),
            tdxModuleJson: _deriveRefId(refId, TDX_MODULE_JSON_REF_TAG),
            tdxModuleIdentitiesJson: _deriveRefId(refId, TDX_MODULE_IDENTITIES_JSON_REF_TAG),
            parsedLevels: _deriveRefId(refId, PARSED_LEVELS_REF_TAG),
            parsedModuleIdentities: _deriveRefId(refId, PARSED_MODULE_IDENTITIES_REF_TAG),
            payload: _deriveRefId(refId, PAYLOAD_REF_TAG),
            hash: _deriveRefId(refId, HASH_REF_TAG),
            issueEvaluation: _deriveRefId(refId, ISSUE_EVAL_REF_TAG),
            contentHash: _deriveRefId(refId, CONTENT_HASH_REF_TAG)
        });

        AutomataDaoStorageV2 storageV2 = _storageV2();
        storageV2.startAsync(state.refs.raw);
        storageV2.startAsync(state.refs.levelsJson);
        storageV2.startAsync(state.refs.tdxModuleJson);
        storageV2.startAsync(state.refs.tdxModuleIdentitiesJson);
        storageV2.startAsync(state.refs.parsedLevels);
        storageV2.startAsync(state.refs.parsedModuleIdentities);
        storageV2.startAsync(state.refs.payload);
        storageV2.startAsync(state.refs.hash);
        storageV2.startAsync(state.refs.issueEvaluation);
        storageV2.startAsync(state.refs.contentHash);

        emit StartedAsyncFmspcTcbUpsert(refId);
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

        _storageV2().appendAttestation(state.refs.levelsJson, bytes(tcbLevelsString));
        if (bytes(tdxModuleString).length > 0) {
            _storageV2().appendAttestation(state.refs.tdxModuleJson, bytes(tdxModuleString));
            state.module = FmspcTcbLib.parseTdxModule(tdxModuleString);
        }
        if (bytes(tdxModuleIdentitiesString).length > 0) {
            _storageV2().appendAttestation(state.refs.tdxModuleIdentitiesJson, bytes(tdxModuleIdentitiesString));
        }

        (, state.totalLevels,) = FmspcTcbLib.parseTcbLevelsRange(basic.version, tcbLevelsString, 0, 0);
        if (basic.id == TcbId.TDX) {
            (, state.totalModuleIdentities,) =
                FmspcTcbLib.parseTdxModuleIdentitiesRange(tdxModuleIdentitiesString, 0, 0);
        }

        state.basicParsed = true;
        emit ParsedAsyncFmspcTcbInfo(refId, 0, state.totalLevels, _parseComplete(state));
    }

    function _appendFinalRefs(AsyncUpsertState storage state) internal {
        uint256 issueSlot = (uint256(state.basic.issueDate) << 192) | (uint256(state.basic.nextUpdate) << 128)
            | state.basic.evaluationDataNumber;

        _storageV2().appendAttestation(state.refs.payload, _buildFinalPayload(state));
        _storageV2().appendAttestation(state.refs.hash, abi.encodePacked(state.rawHash));
        _storageV2().appendAttestation(state.refs.issueEvaluation, abi.encode(issueSlot));
        _storageV2().appendAttestation(state.refs.contentHash, abi.encodePacked(state.contentHash));
    }

    function _finalizeExternalRefs(bytes32 refId, AsyncUpsertState storage state) internal {
        AutomataDaoStorageV2 storageV2 = _storageV2();
        bytes32 key = state.tcbKey;

        storageV2.finalizeAsync(resolver.collateralPointer(key), state.refs.payload);
        storageV2.finalizeAsync(resolver.collateralHashPointer(key), state.refs.hash);
        storageV2.finalizeAsync(resolver.collateralPointer(_computeTcbIssueEvaluationKey(key)), state.refs.issueEvaluation);
        storageV2.finalizeAsync(resolver.collateralPointer(_computeContentHashKey(key)), state.refs.contentHash);

        storageV2.finalizeAsync(_deriveRefId(refId, RAW_REF_TAG), state.refs.raw);
        storageV2.finalizeAsync(_deriveRefId(refId, LEVELS_JSON_REF_TAG), state.refs.levelsJson);
        storageV2.finalizeAsync(_deriveRefId(refId, PARSED_LEVELS_REF_TAG), state.refs.parsedLevels);

        if (_storageV2().readRef(state.refs.tdxModuleJson).length > 0) {
            storageV2.finalizeAsync(_deriveRefId(refId, TDX_MODULE_JSON_REF_TAG), state.refs.tdxModuleJson);
        }
        if (_storageV2().readRef(state.refs.tdxModuleIdentitiesJson).length > 0) {
            storageV2.finalizeAsync(
                _deriveRefId(refId, TDX_MODULE_IDENTITIES_JSON_REF_TAG), state.refs.tdxModuleIdentitiesJson
            );
        }
        if (_storageV2().readRef(state.refs.parsedModuleIdentities).length > 0) {
            storageV2.finalizeAsync(
                _deriveRefId(refId, PARSED_MODULE_IDENTITIES_REF_TAG), state.refs.parsedModuleIdentities
            );
        }
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

    function _buildFinalPayload(AsyncUpsertState storage state) internal view returns (bytes memory reqData) {
        bytes memory raw = _storageV2().readRef(state.refs.raw);
        bytes memory encodedTcbLevels = _encodeLengthPrefixedStream(
            _storageV2().readRef(state.refs.parsedLevels), state.totalLevels
        );
        TcbInfoJsonObj memory tcbInfoObj = TcbInfoJsonObj({tcbInfoStr: string(raw), signature: state.signature});

        if (state.basic.version < 3) {
            reqData = abi.encode(state.basic, encodedTcbLevels, tcbInfoObj);
        } else {
            bytes memory encodedModuleIdentities;
            if (state.totalModuleIdentities > 0) {
                encodedModuleIdentities = _encodeLengthPrefixedStream(
                    _storageV2().readRef(state.refs.parsedModuleIdentities), state.totalModuleIdentities
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

    function _computeTcbIssueEvaluationKey(bytes32 key) internal pure returns (bytes32 ret) {
        ret = keccak256(abi.encodePacked(key, "tcbIssueEvaluation"));
    }

    function _computeContentHashKey(bytes32 key) internal pure returns (bytes32 ret) {
        ret = keccak256(abi.encodePacked(key, "fmspcTcbContentHash"));
    }
}
