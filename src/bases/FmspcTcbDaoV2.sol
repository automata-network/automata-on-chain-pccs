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
 * @notice Splits FMSPC TCBInfo upserts into async upload, parse, range-verified batch
 * upload, and finalize stages. V2 closes the original async consistency hole by requiring
 * the offchain worker to submit byte ranges into the Intel-signed raw JSON and by verifying
 * each packed level / identity with byte-exact reverse serialization before it can be used.
 */
abstract contract FmspcTcbDaoV2 is FmspcTcbDao {
    FmspcTcbHelperV2 public FmspcTcbLibV2;

    bytes32 private constant RAW_REF_TAG = keccak256("fmspcTcb.raw");
    bytes32 private constant HASH_REF_TAG = keccak256("fmspcTcb.hash");
    bytes32 private constant ISSUE_EVAL_REF_TAG = keccak256("fmspcTcb.issueEvaluation");
    bytes32 private constant CONTENT_HASH_REF_TAG = keccak256("fmspcTcb.contentHash");
    bytes32 private constant SGX_COMPONENTS_TEMPLATE_TAG = keccak256("fmspcTcb.sgxComponentsTemplate.v2");
    bytes32 private constant TDX_COMPONENTS_TEMPLATE_TAG = keccak256("fmspcTcb.tdxComponentsTemplate.v2");
    bytes32 private constant VERIFIED_LEVELS_REF_TAG = keccak256("fmspcTcb.verifiedLevels.v2");
    bytes32 private constant VERIFIED_IDENTITIES_REF_TAG = keccak256("fmspcTcb.verifiedIdentities.v2");

    error Use_Async_Upsert();
    error Async_Upsert_Not_Started();
    error Async_Upsert_Finalized();
    error Async_Upsert_Incomplete();
    error Async_Upsert_Invalid_Range();
    error Async_Upsert_Invalid_Attestation_Id();
    error Async_Upsert_Missing_Signature();
    error V2_Template_Missing();
    error V2_Template_Already_Set();
    error V2_Level_Adjacency_Mismatch();
    error V2_Identity_Adjacency_Mismatch();

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
    mapping(bytes32 rootRefId => bool uploaded) internal _templateUploaded;

    struct V2RefState {
        uint32 tcbLevelsArrayStart;
        uint32 tcbLevelsArrayEnd;
        uint32 tdxIdentitiesArrayStart;
        uint32 tdxIdentitiesArrayEnd;
        uint32 expectedNextLevelByteStart;
        uint32 expectedNextIdentityByteStart;
        uint32 tdxModuleObjStart;
        uint32 tdxModuleObjEnd;
        bool rangesParsed;
    }

    mapping(bytes32 rootRefId => V2RefState state) internal _v2RefState;

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

    /// @notice Bundled setup: extract basics + scan both array ranges in one tx. Convenient
    /// for smaller raws. For production and larger Intel payloads, prefer the staged trio
    /// `commitBasicsExtract` -> `commitTcbLevelsRange` -> `commitTdxIdentitiesRange`.
    function commitBasicsV2(bytes32 refId) external virtual {
        AsyncUpsertState storage state = _enterAsync(refId);
        _ensureRangesParsedV2(refId, state);
    }

    /// @notice Stage 1: parse the fixed top-level fields, raw hash, tcb key, and optional TDX module.
    function commitBasicsExtract(bytes32 refId) external virtual {
        AsyncUpsertState storage state = _enterAsync(refId);
        _ensureBasicParsed(refId, state);
    }

    /// @notice Stage 2: scan the signed raw JSON for the top-level `tcbLevels` byte range.
    function commitTcbLevelsRange(bytes32 refId) external virtual {
        AsyncUpsertState storage state = _enterAsync(refId);
        _ensureBasicParsed(refId, state);
        V2RefState storage rs = _v2RefState[refId];
        if (rs.tcbLevelsArrayEnd == 0) {
            _scanTcbLevelsRange(refId, state, rs);
        }
        if (state.basic.id != TcbId.TDX) {
            rs.rangesParsed = true;
        }
    }

    /// @notice Stage 3 for TDX payloads: scan the `tdxModuleIdentities` byte range.
    function commitTdxIdentitiesRange(bytes32 refId) external virtual {
        AsyncUpsertState storage state = _enterAsync(refId);
        _ensureBasicParsed(refId, state);
        if (state.basic.id != TcbId.TDX) revert Async_Upsert_Invalid_Range();
        V2RefState storage rs = _v2RefState[refId];
        if (rs.tdxIdentitiesArrayEnd == 0) {
            _scanTdxIdentitiesRange(refId, state, rs);
        }
        rs.rangesParsed = true;
    }

    function uploadComponentsTemplate(
        bytes32 refId,
        bytes calldata sgxComponentsTemplate,
        bytes calldata tdxComponentsTemplate
    ) external virtual {
        _enterAsync(refId);
        if (_templateUploaded[refId]) revert V2_Template_Already_Set();
        if (sgxComponentsTemplate.length == 0) revert V2_Template_Missing();

        AutomataDaoStorageV2 storageV2 = _storageV2();
        bytes32 sgxRef = _deriveRefId(refId, SGX_COMPONENTS_TEMPLATE_TAG);
        storageV2.startAsync(sgxRef);
        storageV2.appendAttestation(sgxRef, sgxComponentsTemplate);
        if (tdxComponentsTemplate.length > 0) {
            bytes32 tdxRef = _deriveRefId(refId, TDX_COMPONENTS_TEMPLATE_TAG);
            storageV2.startAsync(tdxRef);
            storageV2.appendAttestation(tdxRef, tdxComponentsTemplate);
        }
        _templateUploaded[refId] = true;
    }

    /// @notice Submit a pre-encoded batch of TCB levels with byte-ranges into the signed raw.
    /// `batchStream` shape:
    /// (uint32 packedLength, bytes packedLevel, uint32 byteStart, uint32 byteEnd, bytes20 rawTcbDate)*
    function uploadParsedTcbLevelsBatch(
        bytes32 refId,
        uint256 start,
        uint256 itemCount,
        bytes calldata batchStream
    )
        external
        virtual
        returns (uint256 parsed, uint256 total, bool complete)
    {
        AsyncUpsertState storage state = _enterAsync(refId);
        _ensureRangesParsedV2(refId, state);
        if (state.basic.version >= 3 && !_templateUploaded[refId]) revert V2_Template_Missing();
        if (start != state.parsedLevels) revert Async_Upsert_Invalid_Range();
        if (itemCount == 0 || batchStream.length == 0) revert Async_Upsert_Invalid_Range();

        V2RefState storage rs = _v2RefState[refId];
        bytes memory packedStream;
        uint32 nextExpectedByteStart;
        {
            bytes memory raw = _storageV2().readRef(state.refs.raw);
            bytes memory sgxTpl = _readTemplate(refId, SGX_COMPONENTS_TEMPLATE_TAG);
            bytes memory tdxTpl =
                (state.basic.id == TcbId.TDX) ? _readTemplate(refId, TDX_COMPONENTS_TEMPLATE_TAG) : bytes("");
            (packedStream, nextExpectedByteStart) = FmspcTcbLibV2.verifyAndExtractLevels(
                batchStream,
                raw,
                sgxTpl,
                tdxTpl,
                uint8(state.basic.version),
                state.basic.id == TcbId.TDX,
                rs.expectedNextLevelByteStart,
                rs.tcbLevelsArrayEnd,
                itemCount
            );
        }
        rs.expectedNextLevelByteStart = nextExpectedByteStart;
        _storageV2().appendAttestation(_deriveRefId(refId, VERIFIED_LEVELS_REF_TAG), packedStream);

        state.parsedLevels += itemCount;
        parsed = itemCount;
        total = state.totalLevels;
        complete = _parseComplete(state);
    }

    function uploadParsedTdxModuleIdentitiesBatch(
        bytes32 refId,
        uint256 start,
        uint256 itemCount,
        bytes calldata batchStream
    )
        external
        virtual
        returns (uint256 parsed, uint256 total, bool complete)
    {
        AsyncUpsertState storage state = _enterAsync(refId);
        _ensureRangesParsedV2(refId, state);
        if (state.basic.id != TcbId.TDX) revert Async_Upsert_Invalid_Range();
        if (start != state.parsedModuleIdentities) revert Async_Upsert_Invalid_Range();
        if (itemCount == 0 || batchStream.length == 0) revert Async_Upsert_Invalid_Range();

        V2RefState storage rs = _v2RefState[refId];
        bytes memory packedStream;
        uint32 nextExpectedByteStart;
        {
            bytes memory raw = _storageV2().readRef(state.refs.raw);
            (packedStream, nextExpectedByteStart) = FmspcTcbLibV2.verifyAndExtractIdentities(
                batchStream, raw, rs.expectedNextIdentityByteStart, rs.tdxIdentitiesArrayEnd, itemCount
            );
        }
        rs.expectedNextIdentityByteStart = nextExpectedByteStart;
        _storageV2().appendAttestation(_deriveRefId(refId, VERIFIED_IDENTITIES_REF_TAG), packedStream);

        state.parsedModuleIdentities += itemCount;
        parsed = itemCount;
        total = state.totalModuleIdentities;
        complete = _parseComplete(state);
    }

    function finalizeAsyncUpsert(bytes32 attestationId, bytes32 refId) external virtual returns (bytes32) {
        AsyncUpsertState storage state = _enterAsync(refId);
        _ensureRangesParsedV2(refId, state);
        if (!_parseComplete(state)) revert Async_Upsert_Incomplete();
        if (state.basic.version >= 3 && !_templateUploaded[refId]) revert V2_Template_Missing();
        V2RefState storage rs = _v2RefState[refId];
        if (rs.expectedNextLevelByteStart != rs.tcbLevelsArrayEnd) revert V2_Level_Adjacency_Mismatch();
        if (
            state.basic.id == TcbId.TDX && state.totalModuleIdentities > 0
                && rs.expectedNextIdentityByteStart != rs.tdxIdentitiesArrayEnd
        ) {
            revert V2_Identity_Adjacency_Mismatch();
        }
        return _finalizeAsyncUpsertCommon(attestationId, refId, state);
    }

    function _finalizeAsyncUpsertCommon(
        bytes32 attestationId,
        bytes32 refId,
        AsyncUpsertState storage state
    ) internal returns (bytes32) {
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

        (, string memory levelsJson, string memory moduleJson, string memory moduleIdentitiesJson) = _loadParseInputs(refId, state);
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

    function _ensureBasicParsed(bytes32 refId, AsyncUpsertState storage state) internal virtual {
        if (state.basicParsed) {
            return;
        }

        bytes memory raw = _storageV2().readRef(state.refs.raw);
        if (raw.length == 0) revert Async_Upsert_Incomplete();

        (
            TcbInfoBasic memory basic,
            TDXModule memory mod,
            bool hasMod,
            uint32 tdxModObjStart,
            uint32 tdxModObjEnd
        ) = FmspcTcbLibV2.extractBasics(raw);

        state.basic = basic;
        state.tcbKey = FMSPC_TCB_KEY(uint8(basic.id), basic.fmspc, basic.version);
        state.rawHash = sha256(raw);

        if (hasMod) {
            state.module = mod;
            V2RefState storage rs = _v2RefState[refId];
            rs.tdxModuleObjStart = tdxModObjStart;
            rs.tdxModuleObjEnd = tdxModObjEnd;
        }

        state.basicParsed = true;
    }

    /// @dev Totals are filled by the byte-range scanner stages.
    function _countTcbTotals(
        AsyncUpsertState storage,
        string memory,
        string memory
    ) internal virtual {}

    function _uploadChunkData(bytes32 refId, bytes calldata chunkData) internal {
        AsyncUpsertState storage state = _requireAsyncUpsert(refId);
        if (state.finalized) revert Async_Upsert_Finalized();
        _storageV2().appendAttestation(state.refs.raw, chunkData);
    }

    function _ensureRangesParsedV2(bytes32 refId, AsyncUpsertState storage state) internal {
        V2RefState storage rs = _v2RefState[refId];
        if (rs.rangesParsed) return;
        _ensureBasicParsed(refId, state);
        if (rs.tcbLevelsArrayEnd == 0) {
            _scanTcbLevelsRange(refId, state, rs);
        }
        if (state.basic.id == TcbId.TDX && rs.tdxIdentitiesArrayEnd == 0) {
            _scanTdxIdentitiesRange(refId, state, rs);
        }
        rs.rangesParsed = true;
    }

    function _scanTcbLevelsRange(bytes32 refId, AsyncUpsertState storage state, V2RefState storage rs)
        private
    {
        bytes memory raw = _storageV2().readRef(state.refs.raw);
        (uint32 start, uint32 end, uint32 count) = FmspcTcbLibV2.findTcbLevelsArray(raw);
        rs.tcbLevelsArrayStart = start;
        rs.tcbLevelsArrayEnd = end;
        rs.expectedNextLevelByteStart = start + 1;
        state.totalLevels = count;
        _storageV2().startAsync(_deriveRefId(refId, VERIFIED_LEVELS_REF_TAG));
    }

    function _scanTdxIdentitiesRange(bytes32 refId, AsyncUpsertState storage state, V2RefState storage rs)
        private
    {
        bytes memory raw = _storageV2().readRef(state.refs.raw);
        (uint32 start, uint32 end, uint32 count) = FmspcTcbLibV2.findTdxIdentitiesArray(raw);
        rs.tdxIdentitiesArrayStart = start;
        rs.tdxIdentitiesArrayEnd = end;
        if (start != 0) rs.expectedNextIdentityByteStart = start + 1;
        state.totalModuleIdentities = count;
        _storageV2().startAsync(_deriveRefId(refId, VERIFIED_IDENTITIES_REF_TAG));
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

    function _loadParseInputs(bytes32 refId, AsyncUpsertState storage state)
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
        bytes memory raw = _storageV2().readRef(state.refs.raw);
        V2RefState storage rs = _v2RefState[refId];
        tcbLevelsString = string(_sliceBytes(raw, rs.tcbLevelsArrayStart, rs.tcbLevelsArrayEnd));
        if (rs.tdxModuleObjEnd > rs.tdxModuleObjStart) {
            tdxModuleString = string(_sliceBytes(raw, rs.tdxModuleObjStart, rs.tdxModuleObjEnd));
        }
        if (rs.tdxIdentitiesArrayEnd > rs.tdxIdentitiesArrayStart) {
            tdxModuleIdentitiesString =
                string(_sliceBytes(raw, rs.tdxIdentitiesArrayStart, rs.tdxIdentitiesArrayEnd));
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

    function _buildFinalPayload(bytes32 refId, AsyncUpsertState storage state)
        internal
        view
        virtual
        returns (bytes memory reqData)
    {
        AutomataDaoStorageV2 storageV2 = _storageV2();
        bytes memory raw = _storageV2().readRef(state.refs.raw);
        bytes memory levelsStream = storageV2.readRef(_deriveRefId(refId, VERIFIED_LEVELS_REF_TAG));
        bytes memory identitiesStream = (state.basic.id == TcbId.TDX && state.totalModuleIdentities > 0)
            ? storageV2.readRef(_deriveRefId(refId, VERIFIED_IDENTITIES_REF_TAG))
            : bytes("");
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

    /// @dev Shared "begin an async upsert call" guard used by every state-mutating entry point.
    function _enterAsync(bytes32 refId) internal view returns (AsyncUpsertState storage state) {
        _authorizeAsyncUpsert();
        state = _requireAsyncUpsert(refId);
        if (state.finalized) revert Async_Upsert_Finalized();
    }

    function _deriveRefId(bytes32 rootRefId, bytes32 tag) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(rootRefId, tag));
    }

    function _readTemplate(bytes32 refId, bytes32 tag) private view returns (bytes memory) {
        return _storageV2().readRef(_deriveRefId(refId, tag));
    }

    function _sliceBytes(bytes memory src, uint256 start, uint256 end)
        private
        view
        returns (bytes memory out)
    {
        uint256 n = end - start;
        out = new bytes(n);
        assembly {
            // IDENTITY precompile (0x04): memory-to-memory copy in 3 gas per word.
            let ok := staticcall(gas(), 0x04, add(add(src, 32), start), n, add(out, 32), n)
            if iszero(ok) { revert(0, 0) }
        }
    }

    function _computeTcbIssueEvaluationKey(bytes32 key) internal pure returns (bytes32 ret) {
        ret = keccak256(abi.encodePacked(key, "tcbIssueEvaluation"));
    }

    function _computeContentHashKey(bytes32 key) internal pure returns (bytes32 ret) {
        ret = keccak256(abi.encodePacked(key, "fmspcTcbContentHash"));
    }
}
