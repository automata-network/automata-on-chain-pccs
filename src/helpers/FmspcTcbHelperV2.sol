// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {LibString} from "solady/utils/LibString.sol";
import {DateTimeUtils} from "../utils/DateTimeUtils.sol";
import {TCBStatus, TcbInfoBasic, TDXModule, TcbInfoJsonObj} from "./FmspcTcbHelper.sol";

/**
 * @title FmspcTcb Helper V2
 * @notice Stateless helper for the optimized async TCBInfo upsert protocol. The DAO keeps
 * authorization, state transitions, storage writes, and signature checks; this helper absorbs
 * the pure payload decoding, raw JSON reconstruction, and legacy packed-byte formatting so the
 * versioned DAO stays under EIP-170 runtime-size limits.
 */
contract FmspcTcbHelperV2 {
    uint8 private constant LEVEL_FIELD_TCB = 0;
    uint8 private constant LEVEL_FIELD_DATE = 1;
    uint8 private constant LEVEL_FIELD_STATUS = 2;
    uint8 private constant LEVEL_FIELD_ADVISORY = 3;

    uint8 private constant COMPONENT_FIELD_SVN = 0;
    uint8 private constant COMPONENT_FIELD_CATEGORY = 1;
    uint8 private constant COMPONENT_FIELD_TYPE = 2;

    uint8 private constant LEVEL_FLAG_HAS_ADVISORY_FIELD = 1;
    // Batch headers carry the common component metadata layout. Per-level overrides
    // preserve valid Intel PCS responses whose category/type/order metadata differs
    // from the batch header, instead of failing because of a batching assumption.
    uint8 private constant LEVEL_FLAG_SGX_LAYOUT_OVERRIDE = 2;
    uint8 private constant LEVEL_FLAG_TDX_LAYOUT_OVERRIDE = 4;

    uint8 private constant IDENTITY_FIELD_ID = 0;
    uint8 private constant IDENTITY_FIELD_MRSIGNER = 1;
    uint8 private constant IDENTITY_FIELD_ATTRIBUTES = 2;
    uint8 private constant IDENTITY_FIELD_ATTRIBUTES_MASK = 3;
    uint8 private constant IDENTITY_FIELD_LEVELS = 4;

    uint8 private constant TOP_FIELD_ID = 0;
    uint8 private constant TOP_FIELD_TDX_MODULE = 8;
    uint8 private constant TOP_FIELD_TDX_IDENTITIES = 9;
    uint8 private constant TOP_FIELD_TCB_LEVELS = 10;

    error TCBInfo_Invalid();
    error Async_Upsert_Invalid_Order();
    error Async_Upsert_Invalid_Range();

    struct AsyncBuiltBatch {
        uint32 rawStart;
        bytes rawJson;
        bytes packedStream;
    }

    struct ComponentDescriptor {
        uint8 svnOrder;
        uint8 categoryOrder;
        uint8 typeOrder;
        bytes category;
        bytes componentType;
    }

    struct LevelInput {
        uint32 byteStart;
        uint32 byteEnd;
        bytes levelOrder;
        bytes tcbOrder;
        uint8 flags;
        bytes16 sgxSvns;
        bytes16 tdxSvns;
        uint16 pcesvn;
        bytes20 tcbDateRaw;
        uint8 status;
        bytes[] advisoryIds;
        ComponentDescriptor[] sgxLayoutOverride;
        ComponentDescriptor[] tdxLayoutOverride;
    }

    struct IdentityNestedLevel {
        bytes levelOrder;
        uint8 flags;
        uint8 isvsvn;
        bytes20 tcbDateRaw;
        uint8 status;
        bytes[] advisoryIds;
    }

    struct IdentityInput {
        uint32 byteStart;
        uint32 byteEnd;
        bytes identityOrder;
        bytes idRaw;
        bytes mrsignerHex;
        bytes attributesHex;
        bytes attributesMaskHex;
        IdentityNestedLevel[] nestedLevels;
    }

    function buildAsyncTcbLevelsBatch(
        uint32 schemaVersion,
        bytes calldata payload,
        uint256 itemCount,
        bool includeLeadingComma
    ) external pure returns (AsyncBuiltBatch memory batch) {
        uint256 cursor;
        bool hasTdxComponents = _readU8(payload, cursor) != 0;
        cursor++;

        ComponentDescriptor[] memory sgxLayout;
        ComponentDescriptor[] memory tdxLayout;
        if (schemaVersion >= 3) {
            (sgxLayout, cursor) = _readComponentLayout(payload, cursor);
            if (hasTdxComponents) {
                (tdxLayout, cursor) = _readComponentLayout(payload, cursor);
            }
        }

        uint32 previousEnd;
        for (uint256 i = 0; i < itemCount; i++) {
            LevelInput memory input;
            (input, cursor) = _decodeLevelInput(payload, cursor, schemaVersion >= 3, hasTdxComponents);
            ComponentDescriptor[] memory sgx = input.sgxLayoutOverride.length > 0 ? input.sgxLayoutOverride : sgxLayout;
            ComponentDescriptor[] memory tdx = input.tdxLayoutOverride.length > 0 ? input.tdxLayoutOverride : tdxLayout;
            bytes memory rawLevel = _buildTcbLevelJson(schemaVersion, input, sgx, tdx, hasTdxComponents);
            bytes memory packedLevel = _packTcbLevel(input, hasTdxComponents);
            (batch, previousEnd) = _appendBuiltItem(
                batch, previousEnd, i, includeLeadingComma, input.byteStart, input.byteEnd, rawLevel, packedLevel
            );
        }
        if (cursor != payload.length) revert TCBInfo_Invalid();
    }

    function buildAsyncTdxModuleIdentitiesBatch(bytes calldata payload, uint256 itemCount, bool includeLeadingComma)
        external
        pure
        returns (AsyncBuiltBatch memory batch)
    {
        uint256 cursor;
        uint32 previousEnd;
        for (uint256 i = 0; i < itemCount; i++) {
            IdentityInput memory input;
            (input, cursor) = _decodeIdentityInput(payload, cursor);
            bytes memory rawIdentity = _buildIdentityJson(input);
            (batch, previousEnd) = _appendBuiltItem(
                batch,
                previousEnd,
                i,
                includeLeadingComma,
                input.byteStart,
                input.byteEnd,
                rawIdentity,
                _packIdentity(input)
            );
        }
        if (cursor != payload.length) revert TCBInfo_Invalid();
    }

    function buildAsyncTdxModuleSegment(
        bytes calldata order,
        bytes calldata mrsignerHex,
        bytes calldata attributesHex,
        bytes calldata attributesMaskHex
    ) external pure returns (bytes memory) {
        bytes[] memory fields = new bytes[](3);
        fields[0] = _kvQuoted("mrsigner", mrsignerHex);
        fields[1] = _kvQuoted("attributes", attributesHex);
        fields[2] = _kvQuoted("attributesMask", attributesMaskHex);
        return abi.encodePacked('"tdxModule":', _orderedObject(fields, order));
    }

    function requireBasicTopOrder(
        bytes calldata order,
        uint8 id,
        uint32 version,
        bool hasTdxModule,
        bytes20 issueDateRaw,
        bytes20 nextUpdateRaw
    ) external pure {
        _requireOrder(order);
        if (id > 1) revert Async_Upsert_Invalid_Order();
        if (version < 3 && uint8(order[TOP_FIELD_ID]) != 0) revert Async_Upsert_Invalid_Order();
        if (version < 3 && id != 0) revert Async_Upsert_Invalid_Order();
        if ((id == 1) != hasTdxModule) revert Async_Upsert_Invalid_Order();
        if (hasTdxModule) {
            if (uint8(order[TOP_FIELD_TDX_MODULE]) == 0 || uint8(order[TOP_FIELD_TDX_IDENTITIES]) == 0) {
                revert Async_Upsert_Invalid_Order();
            }
        } else if (uint8(order[TOP_FIELD_TDX_MODULE]) != 0 || uint8(order[TOP_FIELD_TDX_IDENTITIES]) != 0) {
            revert Async_Upsert_Invalid_Order();
        }
        if (uint8(order[TOP_FIELD_TCB_LEVELS]) == 0) revert Async_Upsert_Invalid_Order();
        _requireIsoString(issueDateRaw);
        _requireIsoString(nextUpdateRaw);
    }

    function requireTopLevelLayout(
        uint32[11] calldata offsets,
        uint32[11] calldata ends,
        bytes calldata order,
        uint32 rawLength
    ) external pure {
        bool wrote;
        uint32 prevEnd;
        for (uint8 pos = 1; pos <= order.length; pos++) {
            for (uint8 i = 0; i < order.length; i++) {
                if (uint8(order[i]) != pos) continue;
                uint32 expected = wrote ? prevEnd + 1 : 1;
                if (offsets[i] != expected || ends[i] <= offsets[i] || ends[i] > rawLength) {
                    revert Async_Upsert_Invalid_Range();
                }
                prevEnd = ends[i];
                wrote = true;
                break;
            }
        }
        if (!wrote || prevEnd != rawLength - 1) revert Async_Upsert_Invalid_Range();
    }

    function buildFinalPayload(
        TcbInfoBasic memory basic,
        TDXModule memory mod,
        bytes calldata levelsStream,
        uint256 totalLevels,
        bytes calldata identitiesStream,
        uint256 totalIdentities,
        bytes memory raw,
        bytes memory signature
    ) external pure returns (bytes memory) {
        bytes memory encodedTcbLevels = _streamToBytesArray(levelsStream, totalLevels);
        TcbInfoJsonObj memory tcbInfoObj = TcbInfoJsonObj({tcbInfoStr: string(raw), signature: signature});
        if (basic.version < 3) {
            return abi.encode(basic, encodedTcbLevels, tcbInfoObj);
        }

        bytes memory encodedIdentities;
        if (totalIdentities > 0) {
            encodedIdentities = _streamToBytesArray(identitiesStream, totalIdentities);
        }
        return abi.encode(basic, mod, encodedIdentities, encodedTcbLevels, tcbInfoObj);
    }

    function _decodeLevelInput(bytes calldata data, uint256 cursor, bool usesComponentArrays, bool hasTdxComponents)
        private
        pure
        returns (LevelInput memory input, uint256 nextCursor)
    {
        (input.byteStart, cursor) = _readU32(data, cursor);
        (input.byteEnd, cursor) = _readU32(data, cursor);
        input.levelOrder = data[cursor:cursor + 4];
        cursor += 4;
        input.tcbOrder = data[cursor:cursor + 3];
        cursor += 3;
        input.flags = _readU8(data, cursor);
        cursor++;
        input.sgxSvns = bytes16(data[cursor:cursor + 16]);
        cursor += 16;
        if (hasTdxComponents) {
            input.tdxSvns = bytes16(data[cursor:cursor + 16]);
            cursor += 16;
        }
        uint32 pcesvn;
        (pcesvn, cursor) = _readU32(data, cursor);
        input.pcesvn = uint16(pcesvn);
        input.tcbDateRaw = bytes20(data[cursor:cursor + 20]);
        cursor += 20;
        input.status = _readU8(data, cursor);
        cursor++;
        (input.advisoryIds, cursor) = _readBytesArray(data, cursor);
        if ((input.flags & LEVEL_FLAG_HAS_ADVISORY_FIELD) == 0 && input.advisoryIds.length != 0) {
            revert TCBInfo_Invalid();
        }

        if (usesComponentArrays && (input.flags & LEVEL_FLAG_SGX_LAYOUT_OVERRIDE) != 0) {
            (input.sgxLayoutOverride, cursor) = _readComponentLayout(data, cursor);
        }
        if (usesComponentArrays && hasTdxComponents && (input.flags & LEVEL_FLAG_TDX_LAYOUT_OVERRIDE) != 0) {
            (input.tdxLayoutOverride, cursor) = _readComponentLayout(data, cursor);
        }
        nextCursor = cursor;
    }

    function _decodeIdentityInput(bytes calldata data, uint256 cursor)
        private
        pure
        returns (IdentityInput memory input, uint256 nextCursor)
    {
        (input.byteStart, cursor) = _readU32(data, cursor);
        (input.byteEnd, cursor) = _readU32(data, cursor);
        input.identityOrder = data[cursor:cursor + 5];
        cursor += 5;
        (input.idRaw, cursor) = _readBytesU8(data, cursor);
        if (input.idRaw.length > 31) revert TCBInfo_Invalid();
        input.mrsignerHex = data[cursor:cursor + 96];
        cursor += 96;
        input.attributesHex = data[cursor:cursor + 16];
        cursor += 16;
        input.attributesMaskHex = data[cursor:cursor + 16];
        cursor += 16;
        uint32 nestedCount;
        (nestedCount, cursor) = _readU32(data, cursor);
        input.nestedLevels = new IdentityNestedLevel[](nestedCount);
        for (uint256 i = 0; i < nestedCount; i++) {
            input.nestedLevels[i].levelOrder = data[cursor:cursor + 4];
            cursor += 4;
            input.nestedLevels[i].flags = _readU8(data, cursor);
            cursor++;
            input.nestedLevels[i].isvsvn = _readU8(data, cursor);
            cursor++;
            input.nestedLevels[i].tcbDateRaw = bytes20(data[cursor:cursor + 20]);
            cursor += 20;
            input.nestedLevels[i].status = _readU8(data, cursor);
            cursor++;
            (input.nestedLevels[i].advisoryIds, cursor) = _readBytesArray(data, cursor);
            if (
                (input.nestedLevels[i].flags & LEVEL_FLAG_HAS_ADVISORY_FIELD) == 0
                    && input.nestedLevels[i].advisoryIds.length != 0
            ) {
                revert TCBInfo_Invalid();
            }
        }
        nextCursor = cursor;
    }

    function _buildTcbLevelJson(
        uint32 schemaVersion,
        LevelInput memory input,
        ComponentDescriptor[] memory sgxLayout,
        ComponentDescriptor[] memory tdxLayout,
        bool hasTdxComponents
    ) private pure returns (bytes memory) {
        bytes[] memory fields = new bytes[](4);
        fields[LEVEL_FIELD_TCB] =
            abi.encodePacked('"tcb":', _buildTcbObject(schemaVersion, input, sgxLayout, tdxLayout, hasTdxComponents));
        fields[LEVEL_FIELD_DATE] = _kvQuoted("tcbDate", abi.encodePacked(input.tcbDateRaw));
        fields[LEVEL_FIELD_STATUS] = _kvQuoted("tcbStatus", bytes(_statusToString(input.status)));
        if ((input.flags & LEVEL_FLAG_HAS_ADVISORY_FIELD) != 0) {
            fields[LEVEL_FIELD_ADVISORY] = abi.encodePacked('"advisoryIDs":', _buildStringArray(input.advisoryIds));
        }
        return _orderedObject(fields, input.levelOrder);
    }

    function _buildTcbObject(
        uint32 schemaVersion,
        LevelInput memory input,
        ComponentDescriptor[] memory sgxLayout,
        ComponentDescriptor[] memory tdxLayout,
        bool hasTdxComponents
    ) private pure returns (bytes memory) {
        if (schemaVersion < 3) {
            bytes memory out = bytes("{");
            for (uint256 i = 0; i < 16; i++) {
                if (i > 0) out = abi.encodePacked(out, bytes(","));
                out = abi.encodePacked(
                    out,
                    bytes('"sgxtcbcomp'),
                    bytes(_twoDigitDecimal(uint8(i + 1))),
                    bytes('svn":'),
                    bytes(LibString.toString(uint256(uint8(input.sgxSvns[i]))))
                );
            }
            out = abi.encodePacked(
                out, bytes(',"pcesvn":'), bytes(LibString.toString(uint256(input.pcesvn))), bytes("}")
            );
            return out;
        }

        bytes[] memory fields = new bytes[](3);
        fields[0] = abi.encodePacked('"sgxtcbcomponents":', _buildComponentArray(input.sgxSvns, sgxLayout));
        fields[1] = _kvUint("pcesvn", input.pcesvn);
        if (hasTdxComponents) {
            fields[2] = abi.encodePacked('"tdxtcbcomponents":', _buildComponentArray(input.tdxSvns, tdxLayout));
        }
        return _orderedObject(fields, input.tcbOrder);
    }

    function _buildComponentArray(bytes16 svns, ComponentDescriptor[] memory layout)
        private
        pure
        returns (bytes memory out)
    {
        if (layout.length != 16) revert TCBInfo_Invalid();
        out = bytes("[");
        for (uint256 i = 0; i < 16; i++) {
            if (i > 0) out = abi.encodePacked(out, bytes(","));
            out = abi.encodePacked(out, _buildComponent(uint8(svns[i]), layout[i]));
        }
        out = abi.encodePacked(out, bytes("]"));
    }

    function _buildComponent(uint8 svn, ComponentDescriptor memory descriptor) private pure returns (bytes memory) {
        bytes[] memory fields = new bytes[](3);
        fields[COMPONENT_FIELD_SVN] = _kvUint("svn", svn);
        if (descriptor.categoryOrder != 0) {
            fields[COMPONENT_FIELD_CATEGORY] = _kvQuoted("category", descriptor.category);
        }
        if (descriptor.typeOrder != 0) {
            fields[COMPONENT_FIELD_TYPE] = _kvQuoted("type", descriptor.componentType);
        }
        bytes memory order = new bytes(3);
        order[0] = bytes1(descriptor.svnOrder);
        order[1] = bytes1(descriptor.categoryOrder);
        order[2] = bytes1(descriptor.typeOrder);
        return _orderedObject(fields, order);
    }

    function _buildIdentityJson(IdentityInput memory input) private pure returns (bytes memory) {
        bytes[] memory fields = new bytes[](5);
        fields[IDENTITY_FIELD_ID] = _kvQuoted("id", input.idRaw);
        fields[IDENTITY_FIELD_MRSIGNER] = _kvQuoted("mrsigner", input.mrsignerHex);
        fields[IDENTITY_FIELD_ATTRIBUTES] = _kvQuoted("attributes", input.attributesHex);
        fields[IDENTITY_FIELD_ATTRIBUTES_MASK] = _kvQuoted("attributesMask", input.attributesMaskHex);
        fields[IDENTITY_FIELD_LEVELS] = abi.encodePacked('"tcbLevels":', _buildNestedLevelArray(input.nestedLevels));
        return _orderedObject(fields, input.identityOrder);
    }

    function _buildNestedLevelArray(IdentityNestedLevel[] memory levels) private pure returns (bytes memory out) {
        out = bytes("[");
        for (uint256 i = 0; i < levels.length; i++) {
            if (i > 0) out = abi.encodePacked(out, bytes(","));
            out = abi.encodePacked(out, _buildNestedLevel(levels[i]));
        }
        out = abi.encodePacked(out, bytes("]"));
    }

    function _buildNestedLevel(IdentityNestedLevel memory level) private pure returns (bytes memory) {
        bytes[] memory fields = new bytes[](4);
        fields[LEVEL_FIELD_TCB] =
            abi.encodePacked('"tcb":{"isvsvn":', bytes(LibString.toString(uint256(level.isvsvn))), bytes("}"));
        fields[LEVEL_FIELD_DATE] = _kvQuoted("tcbDate", abi.encodePacked(level.tcbDateRaw));
        fields[LEVEL_FIELD_STATUS] = _kvQuoted("tcbStatus", bytes(_statusToString(level.status)));
        if ((level.flags & LEVEL_FLAG_HAS_ADVISORY_FIELD) != 0) {
            fields[LEVEL_FIELD_ADVISORY] = abi.encodePacked('"advisoryIDs":', _buildStringArray(level.advisoryIds));
        }
        return _orderedObject(fields, level.levelOrder);
    }

    function _packTcbLevel(LevelInput memory input, bool hasTdxComponents) private pure returns (bytes memory) {
        uint256 firstSlot = uint256(input.pcesvn) << 128 | uint256(_parseIso(input.tcbDateRaw)) << 64 | input.status;
        bytes16 tdxSvns = hasTdxComponents ? input.tdxSvns : bytes16(0);
        return abi.encodePacked(bytes32(firstSlot), input.sgxSvns, tdxSvns, _joinAdvisories(input.advisoryIds));
    }

    function _packIdentity(IdentityInput memory input) private pure returns (bytes memory packed) {
        bytes memory mrsigner = _hexDecode(input.mrsignerHex);
        bytes8 attributes = bytes8(uint64(_parseHex(input.attributesHex)));
        bytes8 attributesMask = bytes8(uint64(_parseHex(input.attributesMaskHex)));
        uint256 n = input.nestedLevels.length;
        packed = new bytes(128 + 32 * n);
        bytes32 slot1 = LibString.packOne(string(input.idRaw));
        bytes32 slot4 = bytes32(attributes) | (bytes32(attributesMask) >> 128);
        _storeWord(packed, 0, slot1);
        assembly {
            mstore(add(add(packed, 32), 32), mload(add(mrsigner, 32)))
            mstore(add(add(packed, 32), 64), mload(add(mrsigner, 64)))
        }
        _storeWord(packed, 96, slot4);
        for (uint256 i = 0; i < n; i++) {
            IdentityNestedLevel memory level = input.nestedLevels[i];
            uint256 slot = uint256(level.isvsvn) << 128 | uint256(_parseIso(level.tcbDateRaw)) << 64 | level.status;
            _storeWord(packed, 128 + i * 32, bytes32(slot));
        }
    }

    function _appendBuiltItem(
        AsyncBuiltBatch memory batch,
        uint32 previousEnd,
        uint256 index,
        bool includeLeadingComma,
        uint32 byteStart,
        uint32 byteEnd,
        bytes memory rawJson,
        bytes memory packed
    ) private pure returns (AsyncBuiltBatch memory nextBatch, uint32 nextEnd) {
        if (byteEnd <= byteStart) revert TCBInfo_Invalid();
        if (rawJson.length != byteEnd - byteStart) revert TCBInfo_Invalid();

        if (index == 0) {
            if (includeLeadingComma) {
                if (byteStart == 0) revert TCBInfo_Invalid();
                batch.rawStart = byteStart - 1;
                batch.rawJson = abi.encodePacked(bytes(","), rawJson);
            } else {
                batch.rawStart = byteStart;
                batch.rawJson = rawJson;
            }
        } else {
            if (byteStart != previousEnd + 1) revert TCBInfo_Invalid();
            batch.rawJson = abi.encodePacked(batch.rawJson, bytes(","), rawJson);
        }

        batch.packedStream = abi.encodePacked(batch.packedStream, uint32(packed.length), packed);
        if (batch.rawJson.length != byteEnd - batch.rawStart) revert TCBInfo_Invalid();
        nextBatch = batch;
        nextEnd = byteEnd;
    }

    function _readComponentLayout(bytes calldata data, uint256 cursor)
        private
        pure
        returns (ComponentDescriptor[] memory layout, uint256 nextCursor)
    {
        layout = new ComponentDescriptor[](16);
        for (uint256 i = 0; i < 16; i++) {
            layout[i].svnOrder = _readU8(data, cursor);
            layout[i].categoryOrder = _readU8(data, cursor + 1);
            layout[i].typeOrder = _readU8(data, cursor + 2);
            cursor += 3;
            (layout[i].category, cursor) = _readBytesU16(data, cursor);
            (layout[i].componentType, cursor) = _readBytesU16(data, cursor);
        }
        nextCursor = cursor;
    }

    function _readBytesArray(bytes calldata data, uint256 cursor)
        private
        pure
        returns (bytes[] memory values, uint256 nextCursor)
    {
        uint32 count;
        (count, cursor) = _readU32(data, cursor);
        values = new bytes[](count);
        for (uint256 i = 0; i < count; i++) {
            (values[i], cursor) = _readBytesU16(data, cursor);
        }
        nextCursor = cursor;
    }

    function _readBytesU8(bytes calldata data, uint256 cursor)
        private
        pure
        returns (bytes memory value, uint256 nextCursor)
    {
        uint8 len = _readU8(data, cursor);
        cursor++;
        value = data[cursor:cursor + len];
        nextCursor = cursor + len;
    }

    function _readBytesU16(bytes calldata data, uint256 cursor)
        private
        pure
        returns (bytes memory value, uint256 nextCursor)
    {
        uint16 len = uint16(bytes2(data[cursor:cursor + 2]));
        cursor += 2;
        value = data[cursor:cursor + len];
        nextCursor = cursor + len;
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

    function _streamToBytesArray(bytes calldata stream, uint256 itemCount) private pure returns (bytes memory) {
        bytes[] memory items = new bytes[](itemCount);
        uint256 cursor;
        for (uint256 i = 0; i < itemCount; i++) {
            if (cursor + 4 > stream.length) revert TCBInfo_Invalid();
            uint32 itemLen = uint32(bytes4(stream[cursor:cursor + 4]));
            cursor += 4;
            if (cursor + itemLen > stream.length) revert TCBInfo_Invalid();
            items[i] = stream[cursor:cursor + itemLen];
            cursor += itemLen;
        }
        if (cursor != stream.length) revert TCBInfo_Invalid();
        return abi.encode(items);
    }

    function _orderedObject(bytes[] memory fields, bytes memory order) private pure returns (bytes memory out) {
        _requireOrder(fields, order);
        out = bytes("{");
        bool wrote;
        for (uint8 pos = 1; pos <= fields.length; pos++) {
            for (uint256 i = 0; i < fields.length; i++) {
                if (uint8(order[i]) == pos) {
                    if (fields[i].length == 0) revert Async_Upsert_Invalid_Order();
                    if (wrote) out = abi.encodePacked(out, bytes(","));
                    out = abi.encodePacked(out, fields[i]);
                    wrote = true;
                }
            }
        }
        out = abi.encodePacked(out, bytes("}"));
    }

    function _requireOrder(bytes[] memory fields, bytes memory order) private pure {
        if (order.length != fields.length) revert Async_Upsert_Invalid_Order();
        uint256 seen;
        for (uint256 i = 0; i < order.length; i++) {
            uint8 pos = uint8(order[i]);
            bool fieldPresent = fields[i].length != 0;
            if (pos == 0) {
                if (fieldPresent) revert Async_Upsert_Invalid_Order();
                continue;
            }
            if (!fieldPresent || pos > order.length) revert Async_Upsert_Invalid_Order();
            uint256 bit = uint256(1) << pos;
            if ((seen & bit) != 0) revert Async_Upsert_Invalid_Order();
            seen |= bit;
        }
    }

    function _requireOrder(bytes calldata order) private pure {
        uint256 seen;
        for (uint256 i = 0; i < order.length; i++) {
            uint8 pos = uint8(order[i]);
            if (pos == 0) continue;
            if (pos > order.length) revert Async_Upsert_Invalid_Order();
            uint256 bit = uint256(1) << pos;
            if ((seen & bit) != 0) revert Async_Upsert_Invalid_Order();
            seen |= bit;
        }
    }

    function _buildStringArray(bytes[] memory values) private pure returns (bytes memory out) {
        out = bytes("[");
        for (uint256 i = 0; i < values.length; i++) {
            if (i > 0) out = abi.encodePacked(out, bytes(","));
            _requireJsonStringSafe(values[i]);
            out = abi.encodePacked(out, bytes('"'), values[i], bytes('"'));
        }
        out = abi.encodePacked(out, bytes("]"));
    }

    function _kvQuoted(string memory key, bytes memory value) private pure returns (bytes memory) {
        _requireJsonStringSafe(value);
        return abi.encodePacked(bytes('"'), bytes(key), bytes('":"'), value, bytes('"'));
    }

    function _kvUint(string memory key, uint256 value) private pure returns (bytes memory) {
        return abi.encodePacked(bytes('"'), bytes(key), bytes('":'), bytes(LibString.toString(value)));
    }

    function _statusToString(uint8 status) private pure returns (string memory) {
        if (status == uint8(TCBStatus.OK)) return "UpToDate";
        if (status == uint8(TCBStatus.TCB_SW_HARDENING_NEEDED)) return "SWHardeningNeeded";
        if (status == uint8(TCBStatus.TCB_CONFIGURATION_AND_SW_HARDENING_NEEDED)) {
            return "ConfigurationAndSWHardeningNeeded";
        }
        if (status == uint8(TCBStatus.TCB_CONFIGURATION_NEEDED)) return "ConfigurationNeeded";
        if (status == uint8(TCBStatus.TCB_OUT_OF_DATE)) return "OutOfDate";
        if (status == uint8(TCBStatus.TCB_OUT_OF_DATE_CONFIGURATION_NEEDED)) return "OutOfDateConfigurationNeeded";
        if (status == uint8(TCBStatus.TCB_REVOKED)) return "Revoked";
        revert TCBInfo_Invalid();
    }

    function _joinAdvisories(bytes[] memory advisoryIds) private pure returns (bytes memory out) {
        for (uint256 i = 0; i < advisoryIds.length; i++) {
            if (i > 0) out = abi.encodePacked(out, bytes("\n"));
            out = abi.encodePacked(out, advisoryIds[i]);
        }
    }

    function _requireJsonStringSafe(bytes memory value) private pure {
        for (uint256 i = 0; i < value.length; i++) {
            uint8 c = uint8(value[i]);
            if (c == 0x22 || c == 0x5c || c < 0x20) revert TCBInfo_Invalid();
        }
    }

    function _parseIso(bytes20 raw) private pure returns (uint64) {
        _requireIsoString(raw);
        return uint64(DateTimeUtils.fromISOToTimestamp(string(abi.encodePacked(raw))));
    }

    function _requireIsoString(bytes20 raw) private pure {
        for (uint256 i = 0; i < 20; i++) {
            uint8 c = uint8(raw[i]);
            if (i == 4 || i == 7) {
                if (c != 0x2d) revert TCBInfo_Invalid();
            } else if (i == 10) {
                if (c != 0x54) revert TCBInfo_Invalid();
            } else if (i == 13 || i == 16) {
                if (c != 0x3a) revert TCBInfo_Invalid();
            } else if (i == 19) {
                if (c != 0x5a) revert TCBInfo_Invalid();
            } else if (c < 0x30 || c > 0x39) {
                revert TCBInfo_Invalid();
            }
        }
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

    function _twoDigitDecimal(uint8 v) private pure returns (string memory) {
        bytes memory b = new bytes(2);
        b[0] = bytes1(uint8(48 + (v / 10)));
        b[1] = bytes1(uint8(48 + (v % 10)));
        return string(b);
    }

    function _storeWord(bytes memory out, uint256 offset, bytes32 word) private pure {
        assembly {
            mstore(add(add(out, 32), offset), word)
        }
    }
}
