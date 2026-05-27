// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {LibString} from "solady/utils/LibString.sol";

import {FmspcTcbDao} from "./FmspcTcbDao.sol";
import {AutomataDaoStorageV2} from "../automata_pccs/shared/AutomataDaoStorageV2.sol";
import {FmspcTcbHelperV2} from "../helpers/FmspcTcbHelperV2.sol";
import {DateTimeUtils} from "../utils/DateTimeUtils.sol";

import {CA} from "../Common.sol";
import {TcbInfoJsonObj, TcbId, TcbInfoBasic, TDXModule} from "../helpers/FmspcTcbHelper.sol";

/**
 * @title FMSPC TCB Data Access Object V2
 * @notice Optimized async TCBInfo upsert. Off-chain workers upload typed fields plus
 * source-order metadata; the DAO rebuilds the Intel-signed raw JSON while storing the
 * packed representation required by legacy readers. Finalization verifies the rebuilt raw
 * against Intel's signature, so no on-chain JSON parser or raw-slice round-trip serializer is
 * needed.
 */
abstract contract FmspcTcbDaoV2 is FmspcTcbDao {
    FmspcTcbHelperV2 public FmspcTcbLibV2;

    uint8 public constant ASYNC_UPSERT_PROTOCOL_VERSION = 2;

    bytes32 private constant RAW_REF_TAG = keccak256("fmspcTcb.raw");
    bytes32 private constant HASH_REF_TAG = keccak256("fmspcTcb.hash");
    bytes32 private constant ISSUE_EVAL_REF_TAG = keccak256("fmspcTcb.issueEvaluation");
    bytes32 private constant CONTENT_HASH_REF_TAG = keccak256("fmspcTcb.contentHash");
    bytes32 private constant VERIFIED_LEVELS_REF_TAG = keccak256("fmspcTcb.verifiedLevels.v2");
    bytes32 private constant VERIFIED_IDENTITIES_REF_TAG = keccak256("fmspcTcb.verifiedIdentities.v2");

    uint8 private constant FIELD_ID = 0;
    uint8 private constant FIELD_VERSION = 1;
    uint8 private constant FIELD_ISSUE_DATE = 2;
    uint8 private constant FIELD_NEXT_UPDATE = 3;
    uint8 private constant FIELD_FMSPC = 4;
    uint8 private constant FIELD_PCEID = 5;
    uint8 private constant FIELD_TCB_TYPE = 6;
    uint8 private constant FIELD_EVAL_NUMBER = 7;
    uint8 private constant FIELD_TDX_MODULE = 8;
    uint8 private constant FIELD_TDX_IDENTITIES = 9;
    uint8 private constant FIELD_TCB_LEVELS = 10;
    uint8 private constant TOP_FIELD_COUNT = 11;
    uint32 private constant TDX_MODULE_VALUE_OFFSET = 12;

    error Use_Async_Upsert();
    error Async_Upsert_Not_Started();
    error Async_Upsert_Finalized();
    error Async_Upsert_Incomplete();
    error Async_Upsert_Invalid_Range();
    error Async_Upsert_Invalid_Order();
    error Async_Upsert_Invalid_Length();
    error Async_Upsert_Invalid_Attestation_Id();
    error Async_Upsert_Missing_Signature();
    error TCBInfo_Invalid();

    struct AsyncRefs {
        bytes32 raw;
        bytes32 hash;
        bytes32 issueEvaluation;
        bytes32 contentHash;
        bytes32 levels;
        bytes32 identities;
    }

    struct RawRanges {
        uint32 tcbLevelsArrayStart;
        uint32 tcbLevelsArrayEnd;
        uint32 tdxIdentitiesArrayStart;
        uint32 tdxIdentitiesArrayEnd;
        uint32 tdxModuleObjStart;
        uint32 tdxModuleObjEnd;
    }

    struct AsyncUpsertState {
        bool started;
        bool basicUploaded;
        bool finalized;
        bytes32 tcbKey;
        bytes32 rawHash;
        bytes32 contentHash;
        uint32 rawLength;
        uint32 totalLevels;
        uint32 parsedLevels;
        uint32 totalModuleIdentities;
        uint32 parsedModuleIdentities;
        uint32 levelsStreamLength;
        uint32 identitiesStreamLength;
        uint32 levelsRawCursor;
        uint32 identitiesRawCursor;
        uint256 levelsStreamCursor;
        uint256 identitiesStreamCursor;
        TcbInfoBasic basic;
        TDXModule module;
        bytes signature;
        AsyncRefs refs;
        RawRanges ranges;
    }

    struct BasicInput {
        uint32[TOP_FIELD_COUNT] offsets;
        uint32 tcbLevelsArrayStart;
        uint32 tcbLevelsArrayEnd;
        uint32 tcbLevelsCount;
        uint32 tdxIdentitiesArrayStart;
        uint32 tdxIdentitiesArrayEnd;
        uint32 tdxIdentitiesCount;
        uint32 tdxModuleObjStart;
        uint32 tdxModuleObjEnd;
        uint32 levelsStreamLength;
        uint32 identitiesStreamLength;
        uint8 id;
        uint32 version;
        bytes20 issueDateRaw;
        bytes20 nextUpdateRaw;
        bytes12 fmspcHex;
        bytes4 pceidHex;
        uint8 tcbType;
        uint32 evaluationDataNumber;
        bool hasTdxModule;
        bytes moduleOrder;
        bytes moduleMrsignerHex;
        bytes moduleAttributesHex;
        bytes moduleAttributesMaskHex;
    }

    mapping(bytes32 rootRefId => AsyncUpsertState state) internal _asyncUpserts;
    mapping(bytes32 tcbKey => bytes32 rootRefId) internal _finalizedAsyncRoots;

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

    function asyncUpsertProtocolVersion() external pure returns (uint8) {
        return ASYNC_UPSERT_PROTOCOL_VERSION;
    }

    function upsertFmspcTcb(TcbInfoJsonObj calldata) external pure virtual override returns (bytes32) {
        revert Use_Async_Upsert();
    }

    function startAsyncUpsert(bytes32 refId, bytes calldata signature, uint32 rawLength) external virtual {
        _authorizeAsyncUpsert();
        if (signature.length == 0) revert Async_Upsert_Missing_Signature();
        if (rawLength <= 31) revert Async_Upsert_Invalid_Length();

        AsyncUpsertState storage state = _asyncUpserts[refId];
        if (state.started) revert Async_Upsert_Finalized();

        state.started = true;
        state.rawLength = rawLength;
        state.signature = signature;
        state.refs = AsyncRefs({
            raw: _deriveRefId(refId, RAW_REF_TAG),
            hash: _deriveRefId(refId, HASH_REF_TAG),
            issueEvaluation: _deriveRefId(refId, ISSUE_EVAL_REF_TAG),
            contentHash: _deriveRefId(refId, CONTENT_HASH_REF_TAG),
            levels: _deriveRefId(refId, VERIFIED_LEVELS_REF_TAG),
            identities: _deriveRefId(refId, VERIFIED_IDENTITIES_REF_TAG)
        });

        AutomataDaoStorageV2 storageV2 = _storageV2();
        storageV2.startAsyncWithLength(state.refs.raw, rawLength);
        storageV2.startAsync(state.refs.hash);
        storageV2.startAsync(state.refs.issueEvaluation);
        storageV2.startAsync(state.refs.contentHash);
    }

    function uploadBasicInfo(bytes32 refId, bytes calldata basicPayload, bytes calldata topLevelOrder)
        external
        virtual
    {
        AsyncUpsertState storage state = _enterAsync(refId);
        if (state.basicUploaded) revert Async_Upsert_Invalid_Range();
        if (topLevelOrder.length != TOP_FIELD_COUNT) revert Async_Upsert_Invalid_Order();

        BasicInput memory input = _decodeBasicInput(basicPayload);
        _validateTopOrder(input, topLevelOrder);
        _storeBasicState(state, input);
        _writeBasicRaw(state, input, topLevelOrder);

        AutomataDaoStorageV2 storageV2 = _storageV2();
        storageV2.startAsyncWithLength(state.refs.levels, input.levelsStreamLength);
        if (input.identitiesStreamLength > 0) {
            storageV2.startAsyncWithLength(state.refs.identities, input.identitiesStreamLength);
        }

        state.basicUploaded = true;
    }

    function uploadTcbLevelsBatch(bytes32 refId, uint256 start, uint256 itemCount, bytes calldata payload)
        external
        virtual
        returns (uint256 parsed, uint256 total, bool complete)
    {
        AsyncUpsertState storage state = _enterUploadedAsync(refId);
        if (start != state.parsedLevels) revert Async_Upsert_Invalid_Range();
        if (itemCount == 0) revert Async_Upsert_Invalid_Range();

        if (start + itemCount > state.totalLevels) revert Async_Upsert_Invalid_Range();
        FmspcTcbHelperV2.AsyncBuiltBatch memory batch =
            FmspcTcbLibV2.buildAsyncTcbLevelsBatch(state.basic.version, payload, itemCount, start > 0);
        AutomataDaoStorageV2 storageV2 = _storageV2();
        (state.levelsStreamCursor, state.levelsRawCursor) = _writeBuiltBatch(
            storageV2,
            state.refs.raw,
            state.refs.levels,
            state.levelsStreamCursor,
            state.levelsRawCursor,
            batch,
            state.ranges.tcbLevelsArrayEnd
        );
        state.parsedLevels = uint32(start + itemCount);

        parsed = itemCount;
        total = state.totalLevels;
        complete = _parseComplete(state);
    }

    function uploadTdxModuleIdentitiesBatch(bytes32 refId, uint256 start, uint256 itemCount, bytes calldata payload)
        external
        virtual
        returns (uint256 parsed, uint256 total, bool complete)
    {
        AsyncUpsertState storage state = _enterUploadedAsync(refId);
        if (state.basic.id != TcbId.TDX) revert Async_Upsert_Invalid_Range();
        if (start != state.parsedModuleIdentities) revert Async_Upsert_Invalid_Range();
        if (itemCount == 0) revert Async_Upsert_Invalid_Range();

        if (start + itemCount > state.totalModuleIdentities) revert Async_Upsert_Invalid_Range();
        FmspcTcbHelperV2.AsyncBuiltBatch memory batch =
            FmspcTcbLibV2.buildAsyncTdxModuleIdentitiesBatch(payload, itemCount, start > 0);
        AutomataDaoStorageV2 storageV2 = _storageV2();
        (state.identitiesStreamCursor, state.identitiesRawCursor) = _writeBuiltBatch(
            storageV2,
            state.refs.raw,
            state.refs.identities,
            state.identitiesStreamCursor,
            state.identitiesRawCursor,
            batch,
            state.ranges.tdxIdentitiesArrayEnd
        );
        state.parsedModuleIdentities = uint32(start + itemCount);

        parsed = itemCount;
        total = state.totalModuleIdentities;
        complete = _parseComplete(state);
    }

    function finalizeAsyncUpsert(bytes32 attestationId, bytes32 refId) external virtual returns (bytes32) {
        AsyncUpsertState storage state = _enterUploadedAsync(refId);
        if (!_parseComplete(state)) revert Async_Upsert_Incomplete();
        return _finalizeAsyncUpsertCommon(attestationId, refId, state);
    }

    function _finalizeAsyncUpsertCommon(bytes32 attestationId, bytes32 refId, AsyncUpsertState storage state)
        internal
        returns (bytes32)
    {
        bytes32 expectedAttestationId = resolver.collateralPointer(state.tcbKey);
        if (attestationId != expectedAttestationId) revert Async_Upsert_Invalid_Attestation_Id();

        bytes memory raw = _storageV2().readRef(state.refs.raw);
        if (raw.length != state.rawLength) revert Async_Upsert_Incomplete();

        bytes32 rawHash = sha256(raw);
        state.rawHash = rawHash;
        _checkCollateralDuplicate(state.tcbKey, rawHash);
        _validateTcbInfoV2(string(raw), state.signature);

        if (block.timestamp < state.basic.issueDate || block.timestamp > state.basic.nextUpdate) {
            revert TCB_Expired();
        }
        _checkTcbEvaluationData(state.tcbKey, state.basic);

        (, string memory levelsJson, string memory moduleJson, string memory moduleIdentitiesJson) =
            _loadParseInputsFromRaw(raw, state);
        state.contentHash =
            FmspcTcbLib.generateFmspcTcbContentHash(state.basic, levelsJson, moduleJson, moduleIdentitiesJson);

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

    function _loadFmspcTcbContentHash(bytes32 tcbKey) internal view virtual override returns (bytes32 contentHash) {
        bytes memory data = _fetchDataFromResolver(_computeContentHashKey(tcbKey), false);
        if (data.length > 0) {
            contentHash = bytes32(data);
        }
    }

    function _authorizeAsyncUpsert() internal view virtual {}

    function _decodeBasicInput(bytes calldata data) private pure returns (BasicInput memory input) {
        uint256 cursor;
        for (uint256 i = 0; i < TOP_FIELD_COUNT; i++) {
            (input.offsets[i], cursor) = _readU32(data, cursor);
        }
        (input.tcbLevelsArrayStart, cursor) = _readU32(data, cursor);
        (input.tcbLevelsArrayEnd, cursor) = _readU32(data, cursor);
        (input.tcbLevelsCount, cursor) = _readU32(data, cursor);
        (input.tdxIdentitiesArrayStart, cursor) = _readU32(data, cursor);
        (input.tdxIdentitiesArrayEnd, cursor) = _readU32(data, cursor);
        (input.tdxIdentitiesCount, cursor) = _readU32(data, cursor);
        (input.tdxModuleObjStart, cursor) = _readU32(data, cursor);
        (input.tdxModuleObjEnd, cursor) = _readU32(data, cursor);
        (input.levelsStreamLength, cursor) = _readU32(data, cursor);
        (input.identitiesStreamLength, cursor) = _readU32(data, cursor);
        input.id = _readU8(data, cursor);
        cursor++;
        (input.version, cursor) = _readU32(data, cursor);
        input.issueDateRaw = bytes20(data[cursor:cursor + 20]);
        cursor += 20;
        input.nextUpdateRaw = bytes20(data[cursor:cursor + 20]);
        cursor += 20;
        input.fmspcHex = bytes12(data[cursor:cursor + 12]);
        cursor += 12;
        input.pceidHex = bytes4(data[cursor:cursor + 4]);
        cursor += 4;
        input.tcbType = _readU8(data, cursor);
        cursor++;
        (input.evaluationDataNumber, cursor) = _readU32(data, cursor);
        input.hasTdxModule = _readU8(data, cursor) != 0;
        cursor++;
        if (input.hasTdxModule) {
            input.moduleOrder = data[cursor:cursor + 3];
            cursor += 3;
            input.moduleMrsignerHex = data[cursor:cursor + 96];
            cursor += 96;
            input.moduleAttributesHex = data[cursor:cursor + 16];
            cursor += 16;
            input.moduleAttributesMaskHex = data[cursor:cursor + 16];
            cursor += 16;
        }
        if (cursor != data.length) revert TCBInfo_Invalid();
    }

    function _validateTopOrder(BasicInput memory input, bytes calldata order) private view {
        FmspcTcbLibV2.requireBasicTopOrder(
            order, input.id, input.version, input.hasTdxModule, input.issueDateRaw, input.nextUpdateRaw
        );
        if (!input.hasTdxModule) {
            if (
                input.tdxIdentitiesCount != 0 || input.identitiesStreamLength != 0 || input.tdxIdentitiesArrayStart != 0
                    || input.tdxIdentitiesArrayEnd != 0 || input.tdxModuleObjStart != 0 || input.tdxModuleObjEnd != 0
            ) {
                revert Async_Upsert_Invalid_Range();
            }
        }
    }

    function _storeBasicState(AsyncUpsertState storage state, BasicInput memory input) private {
        state.basic.id = input.id == 1 ? TcbId.TDX : TcbId.SGX;
        state.basic.version = input.version;
        state.basic.issueDate = _parseIso(input.issueDateRaw);
        state.basic.nextUpdate = _parseIso(input.nextUpdateRaw);
        state.basic.fmspc = bytes6(uint48(_parseHex(abi.encodePacked(input.fmspcHex))));
        state.basic.pceid = bytes2(uint16(_parseHex(abi.encodePacked(input.pceidHex))));
        state.basic.tcbType = input.tcbType;
        state.basic.evaluationDataNumber = input.evaluationDataNumber;
        state.tcbKey = FMSPC_TCB_KEY(uint8(state.basic.id), state.basic.fmspc, state.basic.version);

        state.totalLevels = input.tcbLevelsCount;
        state.totalModuleIdentities = input.tdxIdentitiesCount;
        state.levelsStreamLength = input.levelsStreamLength;
        state.identitiesStreamLength = input.identitiesStreamLength;
        state.levelsRawCursor = input.tcbLevelsArrayStart + 1;
        state.identitiesRawCursor = input.hasTdxModule ? input.tdxIdentitiesArrayStart + 1 : 0;
        state.ranges = RawRanges({
            tcbLevelsArrayStart: input.tcbLevelsArrayStart,
            tcbLevelsArrayEnd: input.tcbLevelsArrayEnd,
            tdxIdentitiesArrayStart: input.tdxIdentitiesArrayStart,
            tdxIdentitiesArrayEnd: input.tdxIdentitiesArrayEnd,
            tdxModuleObjStart: input.tdxModuleObjStart,
            tdxModuleObjEnd: input.tdxModuleObjEnd
        });

        if (input.hasTdxModule) {
            state.module = TDXModule({
                mrsigner: _hexDecode(input.moduleMrsignerHex),
                attributes: bytes8(uint64(_parseHex(input.moduleAttributesHex))),
                attributesMask: bytes8(uint64(_parseHex(input.moduleAttributesMaskHex)))
            });
        }
    }

    function _writeBasicRaw(AsyncUpsertState storage state, BasicInput memory input, bytes calldata order) private {
        AutomataDaoStorageV2 storageV2 = _storageV2();
        uint32[TOP_FIELD_COUNT] memory ends;
        storageV2.writeAttestation(state.refs.raw, 0, bytes("{"));
        storageV2.writeAttestation(state.refs.raw, state.rawLength - 1, bytes("}"));

        if (input.version >= 3) {
            ends[FIELD_ID] =
                _writeTopSegment(state, input.offsets[FIELD_ID], uint8(order[FIELD_ID]), _idSegment(state.basic.id));
        }
        ends[FIELD_VERSION] = _writeTopSegment(
            state, input.offsets[FIELD_VERSION], uint8(order[FIELD_VERSION]), _kvUint("version", input.version)
        );
        ends[FIELD_ISSUE_DATE] = _writeTopSegment(
            state,
            input.offsets[FIELD_ISSUE_DATE],
            uint8(order[FIELD_ISSUE_DATE]),
            _kvQuoted("issueDate", abi.encodePacked(input.issueDateRaw))
        );
        ends[FIELD_NEXT_UPDATE] = _writeTopSegment(
            state,
            input.offsets[FIELD_NEXT_UPDATE],
            uint8(order[FIELD_NEXT_UPDATE]),
            _kvQuoted("nextUpdate", abi.encodePacked(input.nextUpdateRaw))
        );
        ends[FIELD_FMSPC] = _writeTopSegment(
            state,
            input.offsets[FIELD_FMSPC],
            uint8(order[FIELD_FMSPC]),
            _kvQuoted("fmspc", abi.encodePacked(input.fmspcHex))
        );
        ends[FIELD_PCEID] = _writeTopSegment(
            state,
            input.offsets[FIELD_PCEID],
            uint8(order[FIELD_PCEID]),
            _kvQuoted("pceId", abi.encodePacked(input.pceidHex))
        );
        ends[FIELD_TCB_TYPE] = _writeTopSegment(
            state, input.offsets[FIELD_TCB_TYPE], uint8(order[FIELD_TCB_TYPE]), _kvUint("tcbType", input.tcbType)
        );
        ends[FIELD_EVAL_NUMBER] = _writeTopSegment(
            state,
            input.offsets[FIELD_EVAL_NUMBER],
            uint8(order[FIELD_EVAL_NUMBER]),
            _kvUint("tcbEvaluationDataNumber", input.evaluationDataNumber)
        );

        if (input.hasTdxModule) {
            bytes memory moduleSegment = FmspcTcbLibV2.buildAsyncTdxModuleSegment(
                input.moduleOrder, input.moduleMrsignerHex, input.moduleAttributesHex, input.moduleAttributesMaskHex
            );
            ends[FIELD_TDX_MODULE] =
                _writeTopSegment(state, input.offsets[FIELD_TDX_MODULE], uint8(order[FIELD_TDX_MODULE]), moduleSegment);
            if (
                input.tdxModuleObjStart != input.offsets[FIELD_TDX_MODULE] + TDX_MODULE_VALUE_OFFSET
                    || input.tdxModuleObjEnd != ends[FIELD_TDX_MODULE]
            ) {
                revert Async_Upsert_Invalid_Range();
            }
            uint32 identitiesStartEnd = _writeTopSegment(
                state,
                input.offsets[FIELD_TDX_IDENTITIES],
                uint8(order[FIELD_TDX_IDENTITIES]),
                bytes('"tdxModuleIdentities":[')
            );
            if (
                identitiesStartEnd != input.tdxIdentitiesArrayStart + 1
                    || input.tdxIdentitiesArrayEnd <= identitiesStartEnd
            ) {
                revert Async_Upsert_Invalid_Range();
            }
            ends[FIELD_TDX_IDENTITIES] = input.tdxIdentitiesArrayEnd;
            storageV2.writeAttestation(state.refs.raw, input.tdxIdentitiesArrayEnd - 1, bytes("]"));
        }

        uint32 levelsStartEnd = _writeTopSegment(
            state, input.offsets[FIELD_TCB_LEVELS], uint8(order[FIELD_TCB_LEVELS]), bytes('"tcbLevels":[')
        );
        if (levelsStartEnd != input.tcbLevelsArrayStart + 1 || input.tcbLevelsArrayEnd <= levelsStartEnd) {
            revert Async_Upsert_Invalid_Range();
        }
        ends[FIELD_TCB_LEVELS] = input.tcbLevelsArrayEnd;
        storageV2.writeAttestation(state.refs.raw, input.tcbLevelsArrayEnd - 1, bytes("]"));
        FmspcTcbLibV2.requireTopLevelLayout(input.offsets, ends, order, state.rawLength);
    }

    function _writeTopSegment(AsyncUpsertState storage state, uint32 offset, uint8 order, bytes memory segment)
        private
        returns (uint32 end)
    {
        if (order == 0) revert Async_Upsert_Invalid_Order();
        if (offset == 0 || offset + segment.length > state.rawLength) revert Async_Upsert_Invalid_Range();
        AutomataDaoStorageV2 storageV2 = _storageV2();
        if (order > 1) {
            storageV2.writeAttestation(state.refs.raw, offset - 1, bytes(","));
        }
        storageV2.writeAttestation(state.refs.raw, offset, segment);
        end = uint32(offset + segment.length);
    }

    function _writeBuiltBatch(
        AutomataDaoStorageV2 storageV2,
        bytes32 rawRef,
        bytes32 streamRef,
        uint256 streamCursor,
        uint32 rawCursor,
        FmspcTcbHelperV2.AsyncBuiltBatch memory batch,
        uint32 arrayEnd
    ) private returns (uint256 nextStreamCursor, uint32 nextRawCursor) {
        if (batch.rawJson.length == 0 || batch.packedStream.length == 0) {
            revert Async_Upsert_Invalid_Length();
        }
        if (batch.rawStart != rawCursor) revert Async_Upsert_Invalid_Range();
        uint256 rawEnd = uint256(batch.rawStart) + batch.rawJson.length;
        if (rawEnd > arrayEnd - 1) revert Async_Upsert_Invalid_Range();

        storageV2.writeAttestation(rawRef, batch.rawStart, batch.rawJson);
        storageV2.writeAttestation(streamRef, streamCursor, batch.packedStream);
        nextStreamCursor = streamCursor + batch.packedStream.length;
        nextRawCursor = uint32(rawEnd);
    }

    function _loadParseInputsFromRaw(bytes memory raw, AsyncUpsertState storage state)
        internal
        view
        virtual
        returns (
            TcbInfoBasic memory basic,
            string memory tcbLevelsString,
            string memory tdxModuleString,
            string memory tdxModuleIdentitiesString
        )
    {
        basic = state.basic;
        RawRanges storage rs = state.ranges;
        tcbLevelsString = string(_sliceBytes(raw, rs.tcbLevelsArrayStart, rs.tcbLevelsArrayEnd));
        if (rs.tdxModuleObjEnd > rs.tdxModuleObjStart) {
            tdxModuleString = string(_sliceBytes(raw, rs.tdxModuleObjStart, rs.tdxModuleObjEnd));
        }
        if (rs.tdxIdentitiesArrayEnd > rs.tdxIdentitiesArrayStart) {
            tdxModuleIdentitiesString = string(_sliceBytes(raw, rs.tdxIdentitiesArrayStart, rs.tdxIdentitiesArrayEnd));
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
        if (signingDer.length == 0) revert Missing_TCB_Cert();

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
            if (revoked) revert TCB_Cert_Revoked(serialNumber);
        }

        bool sigVerified = verifySignature(sha256(bytes(tcbInfoStr)), signature, signingDer);
        if (!sigVerified) revert Invalid_TCB_Cert_Signature();
    }

    function _buildFinalPayload(bytes32 refId, AsyncUpsertState storage state)
        internal
        view
        virtual
        returns (bytes memory reqData)
    {
        AutomataDaoStorageV2 storageV2 = _storageV2();
        bytes memory raw = storageV2.readRef(state.refs.raw);
        bytes memory levelsStream = storageV2.readRef(_deriveRefId(refId, VERIFIED_LEVELS_REF_TAG));
        bytes memory identitiesStream;
        if (state.totalModuleIdentities > 0) {
            identitiesStream = storageV2.readRef(_deriveRefId(refId, VERIFIED_IDENTITIES_REF_TAG));
        }
        reqData = FmspcTcbLibV2.buildFinalPayload(
            state.basic,
            state.module,
            levelsStream,
            state.totalLevels,
            identitiesStream,
            state.totalModuleIdentities,
            raw,
            state.signature
        );
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
        storageV2.finalizeAsync(
            resolver.collateralPointer(_computeTcbIssueEvaluationKey(key)), state.refs.issueEvaluation
        );
        storageV2.finalizeAsync(resolver.collateralPointer(_computeContentHashKey(key)), state.refs.contentHash);
        storageV2.finalizeAsync(_deriveRefId(refId, RAW_REF_TAG), state.refs.raw);
    }

    function _loadAsyncFinalPayload(bytes32 key) internal view returns (bytes memory payload) {
        bytes32 refId = _finalizedAsyncRoots[key];
        if (refId == bytes32(0)) return payload;

        AsyncUpsertState storage state = _asyncUpserts[refId];
        if (!state.finalized) return payload;

        payload = _buildFinalPayload(refId, state);
    }

    function _parseComplete(AsyncUpsertState storage state) internal view returns (bool) {
        if (
            !state.basicUploaded || state.parsedLevels != state.totalLevels
                || state.levelsStreamCursor != state.levelsStreamLength
                || state.levelsRawCursor != state.ranges.tcbLevelsArrayEnd - 1
        ) {
            return false;
        }

        if (state.basic.id == TcbId.TDX) {
            return state.parsedModuleIdentities == state.totalModuleIdentities
                && state.identitiesStreamCursor == state.identitiesStreamLength
                && state.identitiesRawCursor == state.ranges.tdxIdentitiesArrayEnd - 1;
        }

        return state.identitiesStreamLength == 0 && state.identitiesStreamCursor == 0;
    }

    function _enterAsync(bytes32 refId) internal view returns (AsyncUpsertState storage state) {
        _authorizeAsyncUpsert();
        state = _asyncUpserts[refId];
        if (!state.started) revert Async_Upsert_Not_Started();
        if (state.finalized) revert Async_Upsert_Finalized();
    }

    function _enterUploadedAsync(bytes32 refId) internal view returns (AsyncUpsertState storage state) {
        state = _enterAsync(refId);
        if (!state.basicUploaded) revert Async_Upsert_Incomplete();
    }

    function _storageV2() internal view returns (AutomataDaoStorageV2) {
        return AutomataDaoStorageV2(address(resolver));
    }

    function _deriveRefId(bytes32 rootRefId, bytes32 tag) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(rootRefId, tag));
    }

    function _idSegment(TcbId id) private pure returns (bytes memory) {
        return id == TcbId.TDX ? bytes('"id":"TDX"') : bytes('"id":"SGX"');
    }

    function _kvUint(string memory key, uint256 value) private pure returns (bytes memory) {
        return abi.encodePacked(bytes('"'), bytes(key), bytes('":'), bytes(LibString.toString(value)));
    }

    function _kvQuoted(string memory key, bytes memory value) private pure returns (bytes memory) {
        return abi.encodePacked(bytes('"'), bytes(key), bytes('":"'), value, bytes('"'));
    }

    function _readU8(bytes calldata data, uint256 cursor) private pure returns (uint8) {
        if (cursor + 1 > data.length) revert TCBInfo_Invalid();
        return uint8(bytes1(data[cursor:cursor + 1]));
    }

    function _readU32(bytes calldata data, uint256 cursor) private pure returns (uint32 v, uint256 nextCursor) {
        if (cursor + 4 > data.length) revert TCBInfo_Invalid();
        v = uint32(bytes4(data[cursor:cursor + 4]));
        nextCursor = cursor + 4;
    }

    function _parseIso(bytes20 raw) private pure returns (uint64) {
        return uint64(DateTimeUtils.fromISOToTimestamp(string(abi.encodePacked(raw))));
    }

    function _parseHex(bytes memory raw) private pure returns (uint256 value) {
        for (uint256 i = 0; i < raw.length; i++) {
            value = (value << 4) | uint256(_hexNibble(uint8(raw[i])));
        }
    }

    function _hexDecode(bytes memory raw) private pure returns (bytes memory out) {
        if (raw.length % 2 != 0) revert TCBInfo_Invalid();
        out = new bytes(raw.length / 2);
        for (uint256 i = 0; i < out.length; i++) {
            out[i] = bytes1(uint8((_hexNibble(uint8(raw[2 * i])) << 4) | _hexNibble(uint8(raw[2 * i + 1]))));
        }
    }

    function _hexNibble(uint8 c) private pure returns (uint8) {
        if (c >= 48 && c <= 57) return c - 48;
        if (c >= 65 && c <= 70) return c - 55;
        if (c >= 97 && c <= 102) return c - 87;
        revert TCBInfo_Invalid();
    }

    function _sliceBytes(bytes memory src, uint256 start, uint256 end) private pure returns (bytes memory out) {
        if (end < start || end > src.length) revert Async_Upsert_Invalid_Range();
        uint256 n = end - start;
        out = new bytes(n);
        if (n == 0) {
            return out;
        }
        assembly {
            let srcPtr := add(add(src, 0x20), start)
            let dstPtr := add(out, 0x20)
            let endPtr := add(dstPtr, n)

            for {} lt(dstPtr, endPtr) {
                srcPtr := add(srcPtr, 0x20)
                dstPtr := add(dstPtr, 0x20)
            } {
                mstore(dstPtr, mload(srcPtr))
            }

            let rem := mod(n, 0x20)
            if rem {
                let lastPtr := sub(endPtr, rem)
                let mask := not(sub(shl(mul(sub(0x20, rem), 8), 1), 1))
                mstore(lastPtr, and(mload(lastPtr), mask))
            }
        }
    }

    function _computeTcbIssueEvaluationKey(bytes32 key) internal pure returns (bytes32 ret) {
        ret = keccak256(abi.encodePacked(key, "tcbIssueEvaluation"));
    }

    function _computeContentHashKey(bytes32 key) internal pure returns (bytes32 ret) {
        ret = keccak256(abi.encodePacked(key, "fmspcTcbContentHash"));
    }
}
