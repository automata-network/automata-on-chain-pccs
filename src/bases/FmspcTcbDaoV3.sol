// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FmspcTcbDaoV2} from "./FmspcTcbDaoV2.sol";
import {AutomataDaoStorageV2} from "../automata_pccs/shared/AutomataDaoStorageV2.sol";
import {FmspcTcbHelperV3} from "../helpers/FmspcTcbHelperV3.sol";
import {TcbId, TcbInfoBasic, TDXModule} from "../helpers/FmspcTcbHelper.sol";

/**
 * @title FMSPC TCB Data Access Object V3
 * @notice Closes the V2 step-2/step-3 consistency hole between the signed raw and the packed
 * level/identity bytes uploaded by the offchain worker. V3 requires per-level byte ranges and
 * verifies them incrementally as batches arrive — verification work is amortised across all
 * uploadParsedTcbLevelsBatchV3 / uploadParsedTdxModuleIdentitiesBatchV3 txs so every tx stays
 * well under the per-tx gas cap. The final payload is recomposed lazily at read time from the
 * accumulated verified packed bytes (no large SSTORE at finalize).
 */
abstract contract FmspcTcbDaoV3 is FmspcTcbDaoV2 {
    FmspcTcbHelperV3 public FmspcTcbLibV3;

    bytes32 private constant SGX_COMPONENTS_TEMPLATE_TAG = keccak256("fmspcTcb.sgxComponentsTemplate.v3");
    bytes32 private constant TDX_COMPONENTS_TEMPLATE_TAG = keccak256("fmspcTcb.tdxComponentsTemplate.v3");
    /// @dev Accumulator stream of verified per-level packed bytes (length-prefixed):
    /// (uint32 packedLength, bytes packedLevel)*  — written incrementally by batch uploads,
    /// read once by `_buildFinalPayload`.
    bytes32 private constant VERIFIED_LEVELS_REF_TAG = keccak256("fmspcTcb.verifiedLevels.v3");
    bytes32 private constant VERIFIED_IDENTITIES_REF_TAG = keccak256("fmspcTcb.verifiedIdentities.v3");

    mapping(bytes32 => bool) internal _templateUploaded;

    /// @dev Per-refId V3 state. First 8 fields (8×uint32 + 1×bool = 33 bytes) spill the bool
    /// to a 2nd 32-byte storage slot. The extra cold SSTORE is paid once during
    /// `commitBasicsV3` — finalize then reads back tdxModuleObj{Start,End} to slice the
    /// tdxModule JSON substring instead of re-parsing the raw with Solady.
    struct V3RefState {
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

    mapping(bytes32 => V3RefState) internal _v3RefState;

    error Use_V3_Upload();
    error V3_Template_Missing();
    error V3_Template_Already_Set();
    error V3_Level_Adjacency_Mismatch();
    error V3_Identity_Adjacency_Mismatch();

    constructor(
        address _resolver,
        address _p256,
        address _pcs,
        address _fmspcHelper,
        address _fmspcHelperV2,
        address _fmspcHelperV3,
        address _x509Helper,
        address _crlLib
    )
        FmspcTcbDaoV2(_resolver, _p256, _pcs, _fmspcHelper, _fmspcHelperV2, _x509Helper, _crlLib)
    {
        FmspcTcbLibV3 = FmspcTcbHelperV3(_fmspcHelperV3);
    }

    // V2 batch entry points are blocked — V3 callers must use the *_V3 variants.
    function uploadParsedTcbLevelsBatch(bytes32, uint256, string[] calldata)
        external
        pure
        virtual
        override
        returns (uint256, uint256, bool)
    {
        revert Use_V3_Upload();
    }

    function uploadParsedTdxModuleIdentitiesBatch(bytes32, uint256, string[] calldata)
        external
        pure
        virtual
        override
        returns (uint256, uint256, bool)
    {
        revert Use_V3_Upload();
    }

    /// @notice Bundled setup: extract basics + scan both array ranges in one tx. Convenient
    /// for small raws (≲ 15KB). For larger raw (and as Intel's TCB info grows), prefer the
    /// staged trio `commitBasicsExtract` → `commitTcbLevelsRange` → `commitTdxIdentitiesRange`
    /// (TDX only) so per-tx gas stays under the per-block cap. Idempotent: re-running just
    /// no-ops via `state.basicParsed` / `rs.rangesParsed` guards.
    function commitBasicsV3(bytes32 refId) external virtual {
        AsyncUpsertState storage state = _enterAsync(refId);
        _ensureRangesParsedV3(refId, state);
    }

    /// @notice Stage 1: only do the hand-rolled basic-field extraction (extractBasics) + sha256
    /// of raw + state.basic/tcbKey/rawHash/module writes. Cheap (~300K-1M depending on raw
    /// size). Should be called first; the two range-scan stages depend on `state.basic.id`.
    function commitBasicsExtract(bytes32 refId) external virtual {
        AsyncUpsertState storage state = _enterAsync(refId);
        _ensureBasicParsed(refId, state);
    }

    /// @notice Stage 2: scan raw for the `tcbLevels` array range + item count. Caller MUST
    /// have already called `commitBasicsExtract` (we still trigger it idempotently). On SGX
    /// this is the final stage; sets `rs.rangesParsed=true` and the upsert is ready for level
    /// batches. On TDX, follow up with `commitTdxIdentitiesRange`.
    function commitTcbLevelsRange(bytes32 refId) external virtual {
        AsyncUpsertState storage state = _enterAsync(refId);
        _ensureBasicParsed(refId, state);
        V3RefState storage rs = _v3RefState[refId];
        if (rs.tcbLevelsArrayEnd == 0) {
            _scanTcbLevelsRange(refId, state, rs);
        }
        // SGX never has tdxModuleIdentities → ready for batches now.
        if (state.basic.id != TcbId.TDX) {
            rs.rangesParsed = true;
        }
    }

    /// @notice Stage 3 (TDX only): scan raw for `tdxModuleIdentities` array range + count.
    /// Reverts on SGX so callers don't pay for a full-raw fruitless scan. Sets
    /// `rs.rangesParsed=true` — the upsert is now ready for level + identity batches.
    function commitTdxIdentitiesRange(bytes32 refId) external virtual {
        AsyncUpsertState storage state = _enterAsync(refId);
        _ensureBasicParsed(refId, state);
        if (state.basic.id != TcbId.TDX) revert Async_Upsert_Invalid_Range();
        V3RefState storage rs = _v3RefState[refId];
        if (rs.tdxIdentitiesArrayEnd == 0) {
            _scanTdxIdentitiesRange(refId, state, rs);
        }
        rs.rangesParsed = true;
    }

    /// @dev V3 skips V2's Solady-based per-array count helpers — totals are derived in one
    /// pass by `FmspcTcbLibV3.findArrayBounds` inside `_ensureRangesParsedV3`.
    function _countTcbTotals(AsyncUpsertState storage, string memory, string memory)
        internal
        virtual
        override
    {}

    /// @dev V3 replaces V2's Solady-based `parseTcbString` + `parseTdxModule` with the
    /// hand-rolled `extractBasics`. Parity with V2 across every published Intel SGX/TDX V4
    /// fmspc plus the embedded schema-v2 fixture is enforced by FmspcTcbHelperV3ParityTest.
    /// The shape of state writes is unchanged so finalize / `_buildFinalPayload` are unaffected.
    function _ensureBasicParsed(bytes32 refId, AsyncUpsertState storage state)
        internal
        virtual
        override
    {
        if (state.basicParsed) return;

        bytes memory raw = _storageV2().readRef(state.refs.raw);
        if (raw.length == 0) revert Async_Upsert_Incomplete();

        (
            TcbInfoBasic memory basic,
            TDXModule memory mod,
            bool hasMod,
            uint32 tdxModObjStart,
            uint32 tdxModObjEnd
        ) = FmspcTcbLibV3.extractBasics(raw);
        state.basic = basic;
        state.tcbKey = FMSPC_TCB_KEY(uint8(basic.id), basic.fmspc, basic.version);
        state.rawHash = sha256(raw);
        if (hasMod) {
            state.module = mod;
            V3RefState storage rs = _v3RefState[refId];
            rs.tdxModuleObjStart = tdxModObjStart;
            rs.tdxModuleObjEnd = tdxModObjEnd;
        }
        // totals are populated by _ensureRangesParsedV3 via findArrayBounds (V2's
        // _countTcbTotals is overridden to no-op above).
        state.basicParsed = true;
    }

    function uploadComponentsTemplate(
        bytes32 refId,
        bytes calldata sgxComponentsTemplate,
        bytes calldata tdxComponentsTemplate
    ) external virtual {
        _enterAsync(refId);
        if (_templateUploaded[refId]) revert V3_Template_Already_Set();
        if (sgxComponentsTemplate.length == 0) revert V3_Template_Missing();

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
    /// Verification (per-level round-trip + adjacency chaining) happens in THIS tx so finalize
    /// stays cheap. Pass `start == state.parsedLevels` and `batchStream` shaped as:
    /// (uint32 packedLength, bytes packedLevel, uint32 byteStart, uint32 byteEnd, bytes20 rawTcbDate)*
    function uploadParsedTcbLevelsBatchV3(
        bytes32 refId,
        uint256 start,
        uint256 itemCount,
        bytes calldata batchStream
    ) external virtual returns (uint256 parsed, uint256 total, bool complete) {
        AsyncUpsertState storage state = _enterAsync(refId);
        _ensureRangesParsedV3(refId, state);
        if (state.basic.version >= 3 && !_templateUploaded[refId]) revert V3_Template_Missing();
        if (start != state.parsedLevels) revert Async_Upsert_Invalid_Range();
        if (itemCount == 0 || batchStream.length == 0) revert Async_Upsert_Invalid_Range();

        V3RefState storage rs = _v3RefState[refId];
        bytes memory packedStream;
        uint32 nextExpectedByteStart;
        {
            bytes memory raw = _storageV2().readRef(state.refs.raw);
            bytes memory sgxTpl = _readTemplate(refId, SGX_COMPONENTS_TEMPLATE_TAG);
            bytes memory tdxTpl = (state.basic.id == TcbId.TDX)
                ? _readTemplate(refId, TDX_COMPONENTS_TEMPLATE_TAG)
                : bytes("");
            (packedStream, nextExpectedByteStart) = FmspcTcbLibV3.verifyAndExtractLevels(
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

    function uploadParsedTdxModuleIdentitiesBatchV3(
        bytes32 refId,
        uint256 start,
        uint256 itemCount,
        bytes calldata batchStream
    ) external virtual returns (uint256 parsed, uint256 total, bool complete) {
        AsyncUpsertState storage state = _enterAsync(refId);
        _ensureRangesParsedV3(refId, state);
        if (state.basic.id != TcbId.TDX) revert Async_Upsert_Invalid_Range();
        if (start != state.parsedModuleIdentities) revert Async_Upsert_Invalid_Range();
        if (itemCount == 0 || batchStream.length == 0) revert Async_Upsert_Invalid_Range();

        V3RefState storage rs = _v3RefState[refId];
        bytes memory packedStream;
        uint32 nextExpectedByteStart;
        {
            bytes memory raw = _storageV2().readRef(state.refs.raw);
            (packedStream, nextExpectedByteStart) = FmspcTcbLibV3.verifyAndExtractIdentities(
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

    function finalizeAsyncUpsert(bytes32 attestationId, bytes32 refId)
        external
        virtual
        override
        returns (bytes32)
    {
        AsyncUpsertState storage state = _enterAsync(refId);
        _ensureRangesParsedV3(refId, state);
        if (!_parseComplete(state)) revert Async_Upsert_Incomplete();
        if (state.basic.version >= 3 && !_templateUploaded[refId]) revert V3_Template_Missing();
        // The last verified level/identity must have ended at the matching array's `]` — i.e.
        // its byteEnd == arrayEnd - 1, which sets expectedNext to arrayEnd. If a batch fell
        // short of the array end, expectedNext < arrayEnd and we revert here.
        V3RefState storage rs = _v3RefState[refId];
        if (rs.expectedNextLevelByteStart != rs.tcbLevelsArrayEnd) revert V3_Level_Adjacency_Mismatch();
        if (
            state.basic.id == TcbId.TDX && state.totalModuleIdentities > 0
                && rs.expectedNextIdentityByteStart != rs.tdxIdentitiesArrayEnd
        ) {
            revert V3_Identity_Adjacency_Mismatch();
        }
        return _finalizeAsyncUpsertCommon(attestationId, refId, state);
    }

    /// @dev Lazy fallback used by every state-mutating entry point (batch uploads + finalize).
    /// If the caller skipped the staged commit trio, this runs whichever scans are still
    /// outstanding in this same tx. With the staged path used properly, this is a no-op.
    function _ensureRangesParsedV3(bytes32 refId, AsyncUpsertState storage state) internal {
        V3RefState storage rs = _v3RefState[refId];
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

    function _scanTcbLevelsRange(bytes32 refId, AsyncUpsertState storage state, V3RefState storage rs)
        private
    {
        bytes memory raw = _storageV2().readRef(state.refs.raw);
        (uint32 start, uint32 end, uint32 count) = FmspcTcbLibV3.findTcbLevelsArray(raw);
        rs.tcbLevelsArrayStart = start;
        rs.tcbLevelsArrayEnd = end;
        rs.expectedNextLevelByteStart = start + 1; // skip '['
        state.totalLevels = count;
        _storageV2().startAsync(_deriveRefId(refId, VERIFIED_LEVELS_REF_TAG));
    }

    function _scanTdxIdentitiesRange(bytes32 refId, AsyncUpsertState storage state, V3RefState storage rs)
        private
    {
        bytes memory raw = _storageV2().readRef(state.refs.raw);
        (uint32 start, uint32 end, uint32 count) = FmspcTcbLibV3.findTdxIdentitiesArray(raw);
        rs.tdxIdentitiesArrayStart = start;
        rs.tdxIdentitiesArrayEnd = end;
        if (start != 0) rs.expectedNextIdentityByteStart = start + 1;
        state.totalModuleIdentities = count;
        _storageV2().startAsync(_deriveRefId(refId, VERIFIED_IDENTITIES_REF_TAG));
    }

    /// @dev Lazy reconstruction at read time. PCCSRouter callers absorb a small abi.encode
    /// cost per read instead of paying a 10KB+ SSTORE at finalize. The actual rebuild lives in
    /// the helper so this override stays tiny.
    function _buildFinalPayload(bytes32 refId, AsyncUpsertState storage state)
        internal
        view
        virtual
        override
        returns (bytes memory)
    {
        AutomataDaoStorageV2 storageV2 = _storageV2();
        bytes memory raw = storageV2.readRef(state.refs.raw);
        bytes memory levelsStream = storageV2.readRef(_deriveRefId(refId, VERIFIED_LEVELS_REF_TAG));
        bytes memory identitiesStream = (state.basic.id == TcbId.TDX && state.totalModuleIdentities > 0)
            ? storageV2.readRef(_deriveRefId(refId, VERIFIED_IDENTITIES_REF_TAG))
            : bytes("");
        return FmspcTcbLibV3.buildFinalPayload(
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

    function _readTemplate(bytes32 refId, bytes32 tag) private view returns (bytes memory) {
        return _storageV2().readRef(_deriveRefId(refId, tag));
    }

    /// @dev V3 already has byte ranges from `commitBasicsV3` for tcbLevels, tdxModule, and
    /// tdxModuleIdentities — slice them straight out of raw instead of paying for another
    /// Solady JSON parse here. The slice copy uses the IDENTITY precompile (memory→memory),
    /// which is ~300× cheaper than a Solidity byte loop for kB-sized substrings. Byte-exact
    /// equality vs V2's Solady output is enforced by FmspcTcbHelperV3ParityTest.
    function _loadParseInputs(bytes32 refId, AsyncUpsertState storage state)
        internal
        view
        virtual
        override
        returns (
            TcbInfoBasic memory basic,
            string memory tcbLevelsString,
            string memory tdxModuleString,
            string memory tdxModuleIdentitiesString
        )
    {
        basic = state.basic;
        bytes memory raw = _storageV2().readRef(state.refs.raw);
        V3RefState storage rs = _v3RefState[refId];
        tcbLevelsString = string(_sliceBytes(raw, rs.tcbLevelsArrayStart, rs.tcbLevelsArrayEnd));
        if (rs.tdxModuleObjEnd > rs.tdxModuleObjStart) {
            tdxModuleString = string(_sliceBytes(raw, rs.tdxModuleObjStart, rs.tdxModuleObjEnd));
        }
        if (rs.tdxIdentitiesArrayEnd > rs.tdxIdentitiesArrayStart) {
            tdxModuleIdentitiesString =
                string(_sliceBytes(raw, rs.tdxIdentitiesArrayStart, rs.tdxIdentitiesArrayEnd));
        }
    }

    function _sliceBytes(bytes memory src, uint256 start, uint256 end)
        private
        view
        returns (bytes memory out)
    {
        uint256 n = end - start;
        out = new bytes(n);
        assembly {
            // IDENTITY precompile (0x04): memory→memory copy in 3 gas per word.
            let ok := staticcall(gas(), 0x04, add(add(src, 32), start), n, add(out, 32), n)
            if iszero(ok) { revert(0, 0) }
        }
    }
}
