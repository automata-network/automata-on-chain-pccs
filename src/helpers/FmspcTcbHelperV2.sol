// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {LibString} from "solady/utils/LibString.sol";
import {DateTimeUtils} from "../utils/DateTimeUtils.sol";
import {TCBStatus, TcbInfoBasic, TcbId, TDXModule, TcbInfoJsonObj} from "./FmspcTcbHelper.sol";

/// @notice Schema-3 level container ranges located inside the raw inner tcbInfo string.
/// @dev tcbLevelsArrayStart points at the '[' of the outer tcbLevels array.
/// @dev tcbLevelsArrayEnd points at the position immediately after the matching ']'.
struct TcbInfoRanges {
    uint32 tcbLevelsArrayStart;
    uint32 tcbLevelsArrayEnd;
    uint32 tdxModuleIdentitiesArrayStart;
    uint32 tdxModuleIdentitiesArrayEnd;
}

/**
 * @title FmspcTcb Helper V2 — reverse serializer + ranged parser
 * @notice Used by FmspcTcbDaoV2 to verify that offchain-uploaded packed level bytes are
 * faithful representations of a real substring inside the Intel-signed raw tcbInfo. The
 * helper is stateless and called as an external pure library.
 */
contract FmspcTcbHelperV2 {
    // -------- errors --------

    error TCBInfo_Invalid();
    error Invalid_Status();
    error Invalid_Schema_Version();
    error Invalid_Packed_Level();
    error Invalid_Components_Template();

    /// @notice Find the outer-level `tcbLevels` and `tdxModuleIdentities` array byte ranges
    /// inside an inner tcbInfo JSON in one pass. O(|raw|) — also returns top-level object
    /// counts in each array so the DAO can skip Solady's `countTcbLevels` /
    /// `countTdxModuleIdentities` re-parses.
    function findArrayBounds(bytes calldata raw)
        external
        pure
        returns (
            uint32 tcbLevelsStart,
            uint32 tcbLevelsEnd,
            uint32 tdxIdentitiesStart,
            uint32 tdxIdentitiesEnd,
            uint32 tcbLevelsCount,
            uint32 tdxIdentitiesCount
        )
    {
        (tcbLevelsStart, tcbLevelsEnd, tcbLevelsCount) = _findOuterKeyArray(raw, '"tcbLevels":');
        (tdxIdentitiesStart, tdxIdentitiesEnd, tdxIdentitiesCount) =
            _findOuterKeyArray(raw, '"tdxModuleIdentities":');
    }

    /// @notice Single-key variant of `findArrayBounds`. Used by FmspcTcbDaoV2's staged
    /// `commitTcbLevelsRange` so the depth-1 scan for tcbLevels happens in its own tx —
    /// keeping per-tx gas under the per-block cap as raw grows.
    function findTcbLevelsArray(bytes calldata raw)
        external
        pure
        returns (uint32 start, uint32 end, uint32 count)
    {
        return _findOuterKeyArray(raw, '"tcbLevels":');
    }

    /// @notice Single-key variant for tdxModuleIdentities. Only called by V2 DAO on TDX paths
    /// — SGX raw never has this key so callers must skip this on SGX (lookup would still walk
    /// the whole raw to find nothing, wasting gas).
    function findTdxIdentitiesArray(bytes calldata raw)
        external
        pure
        returns (uint32 start, uint32 end, uint32 count)
    {
        return _findOuterKeyArray(raw, '"tdxModuleIdentities":');
    }

    /// @dev Depth-1 brace-tracked scan for `"key":[...]` at object depth 1 (the outermost
    /// fields of a single-object tcbInfo). Returns (start, end_exclusive, itemCount) of the
    /// array value including the `[` and `]`. `itemCount` is the number of top-level `{...}`
    /// objects in the array (counted at adepth=1 && bdepth=0 so nested objects/arrays inside
    /// items don't inflate the count). Returns (0, 0, 0) when the key is absent at depth 1.
    function _findOuterKeyArray(bytes calldata raw, bytes memory key)
        private
        pure
        returns (uint32 start, uint32 end, uint32 itemCount)
    {
        int256 depth = 0;
        uint256 keyLen = key.length;
        uint256 i = 0;
        while (i < raw.length) {
            bytes1 c = raw[i];
            if (c == "{") {
                depth++;
            } else if (c == "}") {
                depth--;
            } else if (c == '"') {
                if (depth == 1 && i + keyLen <= raw.length) {
                    bool match_ = true;
                    for (uint256 j = 0; j < keyLen; j++) {
                        if (raw[i + j] != key[j]) {
                            match_ = false;
                            break;
                        }
                    }
                    if (match_) {
                        uint256 valStart = i + keyLen;
                        if (valStart >= raw.length || raw[valStart] != "[") return (0, 0, 0);
                        int256 adepth = 0;
                        int256 bdepth = 0;
                        uint32 count = 0;
                        uint256 k = valStart;
                        while (k < raw.length) {
                            bytes1 cc = raw[k];
                            if (cc == "[") {
                                adepth++;
                            } else if (cc == "]") {
                                adepth--;
                                if (adepth == 0) {
                                    return (uint32(valStart), uint32(k + 1), count);
                                }
                            } else if (cc == "{") {
                                // Top-level object = directly inside outer array (adepth==1)
                                // and not inside any other object (bdepth==0).
                                if (adepth == 1 && bdepth == 0) {
                                    count++;
                                }
                                bdepth++;
                            } else if (cc == "}") {
                                bdepth--;
                            } else if (cc == '"') {
                                k++;
                                while (k < raw.length && raw[k] != '"') {
                                    if (raw[k] == "\\") k++;
                                    k++;
                                }
                            }
                            k++;
                        }
                        return (0, 0, 0);
                    }
                }
                // Skip past string value at any depth.
                i++;
                while (i < raw.length && raw[i] != '"') {
                    if (raw[i] == "\\") i++;
                    i++;
                }
            }
            i++;
        }
        return (0, 0, 0);
    }

    // -------- lightweight basic-field extractor --------

    /// @notice Hand-rolled replacement for V1 helper's `parseTcbString`+`parseTdxModule`+the
    /// V2 helper's `countTcbLevels`/`countTdxModuleIdentities`. Walks the inner-tcbInfo bytes
    /// directly with depth-1 key matching for each known field. Produces byte-exact-equal
    /// output to the Solady pipeline on Intel's minified PCS payloads — the parity test suite
    /// (`FmspcTcbHelperV2ParityTest`) asserts this against every published SGX+TDX fmspc.
    /// @return basic the parsed TcbInfoBasic
    /// @return mod the parsed TDX module fields (zeroed unless `hasTdxModule`)
    /// @return hasTdxModule true iff the input has a `"tdxModule":{…}` top-level field
    /// @return tdxModuleObjStart byte offset of the `{` opening the tdxModule object (0 if absent)
    /// @return tdxModuleObjEnd byte offset one past the matching `}` (0 if absent)
    function extractBasics(bytes calldata raw)
        external
        pure
        returns (
            TcbInfoBasic memory basic,
            TDXModule memory mod,
            bool hasTdxModule,
            uint32 tdxModuleObjStart,
            uint32 tdxModuleObjEnd
        )
    {
        uint256 vp;
        bool found;

        // version (uint32) — required first because v2 schema omits "id" and defaults to SGX.
        (vp, found) = _findValueAtDepth1(raw, '"version":');
        if (!found) revert TCBInfo_Invalid();
        (uint256 v, ) = _parseUintAt(raw, vp);
        basic.version = uint32(v);

        // id (TcbId enum) — present only in v3+. V2 = SGX by default (matches V1 helper).
        if (basic.version >= 3) {
            (vp, found) = _findValueAtDepth1(raw, '"id":');
            if (!found) revert TCBInfo_Invalid();
            if (raw[vp + 1] == "T" && raw[vp + 2] == "D" && raw[vp + 3] == "X") {
                basic.id = TcbId.TDX;
            } else if (raw[vp + 1] == "S" && raw[vp + 2] == "G" && raw[vp + 3] == "X") {
                basic.id = TcbId.SGX;
            } else {
                revert TCBInfo_Invalid();
            }
        }

        (vp, found) = _findValueAtDepth1(raw, '"issueDate":');
        if (!found) revert TCBInfo_Invalid();
        basic.issueDate = _parseIsoAt(raw, vp);

        (vp, found) = _findValueAtDepth1(raw, '"nextUpdate":');
        if (!found) revert TCBInfo_Invalid();
        basic.nextUpdate = _parseIsoAt(raw, vp);

        (vp, found) = _findValueAtDepth1(raw, '"fmspc":');
        if (!found) revert TCBInfo_Invalid();
        basic.fmspc = bytes6(uint48(_parseHexUint(raw, vp + 1, 12)));

        (vp, found) = _findValueAtDepth1(raw, '"pceId":');
        if (!found) revert TCBInfo_Invalid();
        basic.pceid = bytes2(uint16(_parseHexUint(raw, vp + 1, 4)));

        (vp, found) = _findValueAtDepth1(raw, '"tcbType":');
        if (!found) revert TCBInfo_Invalid();
        (uint256 t, ) = _parseUintAt(raw, vp);
        basic.tcbType = uint8(t);

        (vp, found) = _findValueAtDepth1(raw, '"tcbEvaluationDataNumber":');
        if (!found) revert TCBInfo_Invalid();
        (uint256 e, ) = _parseUintAt(raw, vp);
        basic.evaluationDataNumber = uint32(e);

        // tdxModule (optional, present only on schema-v3 TDX payloads). Returns its byte
        // range so finalize can slice the substring back out for contentHash without a Solady
        // re-parse.
        if (basic.version >= 3 && basic.id == TcbId.TDX) {
            (vp, found) = _findValueAtDepth1(raw, '"tdxModule":');
            if (found) {
                hasTdxModule = true;
                tdxModuleObjStart = uint32(vp);
                uint256 objEnd = _findObjectEnd(raw, vp);
                tdxModuleObjEnd = uint32(objEnd);
                mod = _extractTdxModuleInner(raw[vp:objEnd]);
            }
        }
    }

    function _findValueAtDepth1(bytes calldata raw, bytes memory keyWithSuffix)
        private
        pure
        returns (uint256 valPos, bool found)
    {
        int256 depth = 0;
        uint256 kl = keyWithSuffix.length;
        uint256 i = 0;
        while (i < raw.length) {
            bytes1 c = raw[i];
            if (c == "{") { depth++; i++; continue; }
            if (c == "}") { depth--; i++; continue; }
            if (c == '"') {
                if (depth == 1 && i + kl <= raw.length) {
                    bool match_ = true;
                    for (uint256 j = 0; j < kl; j++) {
                        if (raw[i + j] != keyWithSuffix[j]) {
                            match_ = false;
                            break;
                        }
                    }
                    if (match_) return (i + kl, true);
                }
                i++;
                while (i < raw.length && raw[i] != '"') {
                    if (raw[i] == "\\") i++;
                    i++;
                }
                i++;
                continue;
            }
            i++;
        }
        return (0, false);
    }

    /// @dev Read a decimal uint starting at `pos`. Stops at first non-digit. Reverts if no
    /// digits were consumed (matches Solady's `parseUint` semantics for our use cases).
    function _parseUintAt(bytes calldata raw, uint256 pos)
        private
        pure
        returns (uint256 value, uint256 nextPos)
    {
        uint256 start = pos;
        while (pos < raw.length) {
            uint8 c = uint8(raw[pos]);
            if (c < 48 || c > 57) break;
            value = value * 10 + (c - 48);
            pos++;
        }
        if (pos == start) revert TCBInfo_Invalid();
        nextPos = pos;
    }

    /// @dev Read exactly `hexLen` hex characters starting at `pos`, return as uint256 (big-end).
    function _parseHexUint(bytes calldata raw, uint256 pos, uint256 hexLen)
        private
        pure
        returns (uint256 value)
    {
        for (uint256 i = 0; i < hexLen; i++) {
            value = (value << 4) | uint256(_hexNibble(uint8(raw[pos + i])));
        }
    }

    /// @dev Read a 20-char ISO timestamp value starting at the opening `"` (raw[vp]='"').
    function _parseIsoAt(bytes calldata raw, uint256 vp) private pure returns (uint64) {
        // value layout: `"YYYY-MM-DDTHH:MM:SSZ"` — 22 bytes total.
        bytes20 dateBytes = bytes20(raw[vp + 1:vp + 21]);
        return uint64(DateTimeUtils.fromISOToTimestamp(string(abi.encodePacked(dateBytes))));
    }

    /// @dev Find matching `}` for the object that starts at raw[pos] (must be `{`). Returns
    /// position immediately after the closing brace.
    function _findObjectEnd(bytes calldata raw, uint256 pos) private pure returns (uint256) {
        if (pos >= raw.length || raw[pos] != "{") revert TCBInfo_Invalid();
        int256 depth = 0;
        while (pos < raw.length) {
            bytes1 c = raw[pos];
            if (c == "{") {
                depth++;
            } else if (c == "}") {
                depth--;
                if (depth == 0) return pos + 1;
            } else if (c == '"') {
                pos++;
                while (pos < raw.length && raw[pos] != '"') {
                    if (raw[pos] == "\\") pos++;
                    pos++;
                }
            }
            pos++;
        }
        revert TCBInfo_Invalid();
    }

    /// @dev Extract mrsigner / attributes / attributesMask out of a `{...}` tdxModule slice.
    function _extractTdxModuleInner(bytes calldata sub) private pure returns (TDXModule memory mod) {
        uint256 vp;
        bool found;

        (vp, found) = _findValueAtDepth1(sub, '"mrsigner":');
        if (!found) revert TCBInfo_Invalid();
        mod.mrsigner = _hexDecodeBytes(sub, vp + 1, 96);

        (vp, found) = _findValueAtDepth1(sub, '"attributes":');
        if (!found) revert TCBInfo_Invalid();
        mod.attributes = bytes8(uint64(_parseHexUint(sub, vp + 1, 16)));

        (vp, found) = _findValueAtDepth1(sub, '"attributesMask":');
        if (!found) revert TCBInfo_Invalid();
        mod.attributesMask = bytes8(uint64(_parseHexUint(sub, vp + 1, 16)));
    }

    function _hexDecodeBytes(bytes calldata raw, uint256 pos, uint256 hexLen)
        private
        pure
        returns (bytes memory out)
    {
        out = new bytes(hexLen / 2);
        for (uint256 i = 0; i < hexLen / 2; i++) {
            uint8 hi = _hexNibble(uint8(raw[pos + 2 * i]));
            uint8 lo = _hexNibble(uint8(raw[pos + 2 * i + 1]));
            out[i] = bytes1(uint8((hi << 4) | lo));
        }
    }

    // -------- TCB level serializer --------

    /// @notice Serialize a TCB level back to its exact Intel-JSON form.
    /// @param packedLevel bit-packed level produced by FmspcTcbHelper.tcbLevelsObjToBytes
    /// @param rawTcbDate the original 20-byte ISO timestamp "YYYY-MM-DDTHH:MM:SSZ"
    /// @param schemaVersion 2 (flat sgxtcbcompXXsvn keys) or 3 (sgxtcbcomponents[] structure)
    /// @param hasTdxComponents only relevant for schemaVersion==3; emit tdxtcbcomponents block
    /// @param sgxComponentsTemplate raw substring of sgxtcbcomponents value from level[0] (v3 only; ignored for v2)
    /// @param tdxComponentsTemplate raw substring of tdxtcbcomponents value from level[0] (v3+TDX only)
    /// @return out exact bytes for the level's JSON object including its outer braces
    function serializeTcbLevel(
        bytes calldata packedLevel,
        bytes20 rawTcbDate,
        uint8 schemaVersion,
        bool hasTdxComponents,
        bytes calldata sgxComponentsTemplate,
        bytes calldata tdxComponentsTemplate
    ) external pure returns (bytes memory out) {
        out = _serializeLevelInternal(
            packedLevel,
            rawTcbDate,
            schemaVersion,
            hasTdxComponents,
            sgxComponentsTemplate,
            tdxComponentsTemplate
        );
    }

    function _serializeLevelInternal(
        bytes calldata packedLevel,
        bytes20 rawTcbDate,
        uint8 schemaVersion,
        bool hasTdxComponents,
        bytes calldata sgxComponentsTemplate,
        bytes calldata tdxComponentsTemplate
    ) private pure returns (bytes memory out) {
        if (packedLevel.length < 64) revert Invalid_Packed_Level();
        uint16 pcesvn = uint16((uint256(bytes32(packedLevel[0:32])) >> 128) & 0xFFFF);
        uint8 status = uint8(packedLevel[31]);

        bytes16 sgxSvns;
        bytes16 tdxSvns;
        assembly {
            let slot2 := calldataload(add(packedLevel.offset, 32))
            sgxSvns := and(slot2, 0xffffffffffffffffffffffffffffffff00000000000000000000000000000000)
            tdxSvns := shl(128, slot2)
        }

        bytes memory tcbInner = _emitTcbInner(
            schemaVersion, hasTdxComponents, sgxSvns, tdxSvns, pcesvn, sgxComponentsTemplate, tdxComponentsTemplate
        );
        bytes memory advisorySegment = _emitAdvisorySegment(packedLevel);

        out = bytes.concat(
            bytes('{"tcb":'),
            tcbInner,
            bytes(',"tcbDate":"'),
            abi.encodePacked(rawTcbDate),
            bytes('","tcbStatus":"'),
            bytes(_statusToString(status)),
            bytes('"'),
            advisorySegment,
            bytes('}')
        );
    }

    function _emitTcbInner(
        uint8 schemaVersion,
        bool hasTdxComponents,
        bytes16 sgxSvns,
        bytes16 tdxSvns,
        uint16 pcesvn,
        bytes calldata sgxComponentsTemplate,
        bytes calldata tdxComponentsTemplate
    ) private pure returns (bytes memory inner) {
        if (schemaVersion == 2) {
            // Flat shape: {"sgxtcbcomp01svn":N,...,"sgxtcbcomp16svn":N,"pcesvn":N}
            inner = _emitV2TcbInner(sgxSvns, pcesvn);
            return inner;
        }
        if (schemaVersion != 3) revert Invalid_Schema_Version();

        bytes memory sgxArr = _spliceSvnsIntoTemplate(sgxComponentsTemplate, sgxSvns);
        bytes memory pcePart = bytes.concat(bytes(',"pcesvn":'), bytes(LibString.toString(uint256(pcesvn))));

        if (hasTdxComponents) {
            bytes memory tdxArr = _spliceSvnsIntoTemplate(tdxComponentsTemplate, tdxSvns);
            inner = bytes.concat(
                bytes('{"sgxtcbcomponents":'),
                sgxArr,
                pcePart,
                bytes(',"tdxtcbcomponents":'),
                tdxArr,
                bytes('}')
            );
        } else {
            inner = bytes.concat(bytes('{"sgxtcbcomponents":'), sgxArr, pcePart, bytes('}'));
        }
    }

    function _emitV2TcbInner(bytes16 sgxSvns, uint16 pcesvn) private pure returns (bytes memory) {
        // sgxtcbcomp01svn..sgxtcbcomp16svn keys are zero-padded; sgxSvns[i] (0..15) is component i.
        bytes memory result = bytes('{');
        for (uint8 i = 0; i < 16; i++) {
            // build key "sgxtcbcompXXsvn" where XX is zero-padded 01..16
            uint8 oneBased = i + 1;
            bytes memory key = bytes('"sgxtcbcomp');
            key = bytes.concat(key, bytes(_twoDigitDecimal(oneBased)), bytes('svn":'));
            uint8 svn = uint8(sgxSvns[i]);
            result = bytes.concat(result, key, bytes(LibString.toString(uint256(svn))), bytes(','));
        }
        result = bytes.concat(result, bytes('"pcesvn":'), bytes(LibString.toString(uint256(pcesvn))), bytes('}'));
        return result;
    }

    function _twoDigitDecimal(uint8 v) private pure returns (string memory) {
        bytes memory b = new bytes(2);
        b[0] = bytes1(uint8(48 + (v / 10)));
        b[1] = bytes1(uint8(48 + (v % 10)));
        return string(b);
    }

    /// @notice Replace each `"svn":<digits>` occurrence in `template` with the corresponding entry from `svns`.
    /// @dev `template` is the raw substring `[{...},{...},...]` taken from level[0] of the actual TCB.
    /// For each component we find the literal `"svn":`, skip the existing digits, and splice the new svn ASCII.
    function _spliceSvnsIntoTemplate(bytes calldata template, bytes16 svns) private pure returns (bytes memory) {
        bytes memory out = new bytes(0);
        uint256 cursor;
        uint8 componentIndex;
        bytes memory needle = bytes('"svn":');
        while (cursor < template.length && componentIndex < 16) {
            // find next occurrence of `"svn":` starting at cursor
            int256 hit = _indexOf(template, needle, cursor);
            if (hit < 0) break;
            uint256 hitPos = uint256(hit);
            uint256 digitStart = hitPos + needle.length;
            uint256 digitEnd = digitStart;
            while (digitEnd < template.length) {
                uint8 c = uint8(template[digitEnd]);
                if (c < 48 || c > 57) break;
                digitEnd++;
            }
            // append template[cursor..digitStart], then new svn ascii, advance cursor past old digits
            out = bytes.concat(out, _calldataSlice(template, cursor, digitStart - cursor));
            out = bytes.concat(out, bytes(LibString.toString(uint256(uint8(svns[componentIndex])))));
            cursor = digitEnd;
            componentIndex++;
        }
        if (componentIndex != 16) revert Invalid_Components_Template();
        // append remainder
        if (cursor < template.length) {
            out = bytes.concat(out, _calldataSlice(template, cursor, template.length - cursor));
        }
        return out;
    }

    function _calldataSlice(bytes calldata src, uint256 offset, uint256 length) private pure returns (bytes memory) {
        bytes memory dst = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            dst[i] = src[offset + i];
        }
        return dst;
    }

    function _indexOf(bytes calldata haystack, bytes memory needle, uint256 from) private pure returns (int256) {
        if (needle.length == 0 || haystack.length < needle.length) return -1;
        uint256 limit = haystack.length - needle.length;
        for (uint256 i = from; i <= limit; i++) {
            bool match_ = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) {
                    match_ = false;
                    break;
                }
            }
            if (match_) return int256(i);
        }
        return -1;
    }

    /// @dev Emit `,"advisoryIDs":["X","Y"]` from a `bytes[]` array (empty bytes => empty result).
    function _emitAdvisorySegmentArray(bytes[] memory ids) private pure returns (bytes memory) {
        if (ids.length == 0) return bytes("");
        bytes memory result = bytes(',"advisoryIDs":[');
        for (uint256 i = 0; i < ids.length; i++) {
            if (i > 0) result = bytes.concat(result, bytes(","));
            result = bytes.concat(result, bytes('"'), ids[i], bytes('"'));
        }
        result = bytes.concat(result, bytes("]"));
        return result;
    }

    function _emitAdvisorySegment(bytes calldata packedLevel) private pure returns (bytes memory) {
        if (packedLevel.length <= 64) return bytes('');
        // advisoryIDs are '\n'-joined in the packed string slot
        uint256 segLen = packedLevel.length - 64;
        bytes memory result = bytes(',"advisoryIDs":["');
        bool first = true;
        uint256 i = 0;
        bytes memory current = new bytes(0);
        while (i < segLen) {
            bytes1 c = packedLevel[64 + i];
            if (c == 0x0a /* '\n' */) {
                if (!first) {
                    result = bytes.concat(result, bytes('","'));
                }
                result = bytes.concat(result, current);
                current = new bytes(0);
                first = false;
                i++;
                continue;
            }
            current = bytes.concat(current, bytes.concat(c));
            i++;
        }
        // tail
        if (!first) {
            result = bytes.concat(result, bytes('","'));
        }
        result = bytes.concat(result, current, bytes('"]'));
        return result;
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
        revert Invalid_Status();
    }

    // -------- batch verifiers (callable per-batch; state held by the DAO) --------

    /// @notice Verify each TCB level in `stream` matches its claimed raw slice and is properly
    /// chained with the previous batch. The caller (V2 DAO) tracks `expectedFirstByteStart`
    /// across batches; at finalize the DAO checks `nextExpectedByteStart == tcbLevelsArrayEnd`
    /// to confirm the last level reached the end of the array.
    /// @param stream inline batch format: (uint32 packedLength, bytes packedLevel, uint32 byteStart, uint32 byteEnd, bytes20 rawTcbDate)*
    /// @param expectedFirstByteStart byteStart that the first level in this batch MUST equal
    /// @return packedStream length-prefixed verified packed bytes, ready to append to the accumulator ref
    /// @return nextExpectedByteStart the value the caller should pass as `expectedFirstByteStart` for the next batch
    function verifyAndExtractLevels(
        bytes calldata stream,
        bytes calldata raw,
        bytes calldata sgxComponentsTemplate,
        bytes calldata tdxComponentsTemplate,
        uint8 schemaVersion,
        bool hasTdxComponents,
        uint32 expectedFirstByteStart,
        uint32 tcbLevelsArrayEnd,
        uint256 itemCount
    ) external pure returns (bytes memory packedStream, uint32 nextExpectedByteStart) {
        uint256 cursor;
        uint32 expectedStart = expectedFirstByteStart;
        for (uint256 i = 0; i < itemCount; i++) {
            uint32 packedLength;
            (packedLength, cursor) = _readU32(stream, cursor);
            bytes calldata packedLevel = stream[cursor:cursor + packedLength];
            cursor += packedLength;
            uint32 byteStart;
            uint32 byteEnd;
            (byteStart, cursor) = _readU32(stream, cursor);
            (byteEnd, cursor) = _readU32(stream, cursor);
            bytes20 rawTcbDate = bytes20(stream[cursor:cursor + 20]);
            cursor += 20;

            if (byteStart != expectedStart) revert TCBInfo_Invalid();
            if (byteEnd <= byteStart || byteEnd > tcbLevelsArrayEnd - 1) revert TCBInfo_Invalid();

            bytes memory serialized = _serializeLevelInternal(
                packedLevel,
                rawTcbDate,
                schemaVersion,
                hasTdxComponents,
                sgxComponentsTemplate,
                tdxComponentsTemplate
            );
            if (keccak256(raw[byteStart:byteEnd]) != keccak256(serialized)) revert TCBInfo_Invalid();

            // Per-level adjacency: byteEnd < arrayEnd-1 means there are more levels after this one
            // (raw[byteEnd] must be ','); byteEnd == arrayEnd-1 means this is the last level in
            // the entire tcbLevels array (raw[byteEnd] is ']' by definition).
            if (byteEnd < tcbLevelsArrayEnd - 1) {
                if (raw[byteEnd] != ",") revert TCBInfo_Invalid();
                expectedStart = byteEnd + 1;
            } else {
                expectedStart = tcbLevelsArrayEnd; // signal "no more levels"
            }
            packedStream = bytes.concat(packedStream, abi.encodePacked(packedLength, packedLevel));
        }
        if (cursor != stream.length) revert TCBInfo_Invalid();
        nextExpectedByteStart = expectedStart;
    }

    /// @notice Verify every TDX module identity in `stream` matches its claimed raw slice and
    /// tiles the `tdxModuleIdentities` array exactly. Returns per-identity packed bytes.
    /// @param stream concatenated batches in the FmspcTcbDaoV2 inline identity format:
    ///   (uint32 packedLength, bytes packed, uint32 byteStart, uint32 byteEnd,
    ///    96 mrSignerHex, 16 attrHex, 16 attrMaskHex, uint32 nestedCount,
    ///    [for each nested: bytes20 date, uint16 advisoryCount, [for each advisory: uint16 len, bytes id]])*
    /// @notice Per-batch identity verifier. Same chaining semantics as `verifyAndExtractLevels`.
    function verifyAndExtractIdentities(
        bytes calldata stream,
        bytes calldata raw,
        uint32 expectedFirstByteStart,
        uint32 arrayEnd,
        uint256 itemCount
    ) external pure returns (bytes memory packedStream, uint32 nextExpectedByteStart) {
        uint256 cursor;
        uint32 expectedStart = expectedFirstByteStart;
        for (uint256 i = 0; i < itemCount; i++) {
            bytes memory packedItem;
            (cursor, expectedStart, packedItem) =
                _verifyOneIdentity(stream, cursor, raw, expectedStart, arrayEnd);
            packedStream = bytes.concat(packedStream, abi.encodePacked(uint32(packedItem.length), packedItem));
        }
        if (cursor != stream.length) revert TCBInfo_Invalid();
        nextExpectedByteStart = expectedStart;
    }

    function _verifyOneIdentity(
        bytes calldata stream,
        uint256 cursor,
        bytes calldata raw,
        uint32 expectedStart,
        uint32 arrayEnd
    ) private pure returns (uint256 nextCursor, uint32 nextExpectedStart, bytes memory packedItem) {
        uint32 packedLength;
        (packedLength, cursor) = _readU32(stream, cursor);
        bytes calldata packedIdentity = stream[cursor:cursor + packedLength];
        cursor += packedLength;
        uint32 byteStart;
        uint32 byteEnd;
        (byteStart, cursor) = _readU32(stream, cursor);
        (byteEnd, cursor) = _readU32(stream, cursor);
        bytes calldata mrSignerHex = stream[cursor:cursor + 96];
        cursor += 96;
        bytes calldata attrHex = stream[cursor:cursor + 16];
        cursor += 16;
        bytes calldata attrMaskHex = stream[cursor:cursor + 16];
        cursor += 16;
        uint32 nestedCount;
        (nestedCount, cursor) = _readU32(stream, cursor);

        bytes20[] memory nestedDates = new bytes20[](nestedCount);
        bytes[][] memory nestedAdvisories = new bytes[][](nestedCount);
        for (uint256 j = 0; j < nestedCount; j++) {
            nestedDates[j] = bytes20(stream[cursor:cursor + 20]);
            cursor += 20;
            uint16 advisoryCount = uint16(bytes2(stream[cursor:cursor + 2]));
            cursor += 2;
            nestedAdvisories[j] = new bytes[](advisoryCount);
            for (uint256 k = 0; k < advisoryCount; k++) {
                uint16 advLen = uint16(bytes2(stream[cursor:cursor + 2]));
                cursor += 2;
                nestedAdvisories[j][k] = stream[cursor:cursor + advLen];
                cursor += advLen;
            }
        }

        if (byteStart != expectedStart) revert TCBInfo_Invalid();
        if (byteEnd <= byteStart || byteEnd > arrayEnd - 1) revert TCBInfo_Invalid();

        bytes memory serialized = _serializeIdentityInternal(
            packedIdentity, mrSignerHex, attrHex, attrMaskHex, nestedDates, nestedAdvisories
        );
        if (keccak256(raw[byteStart:byteEnd]) != keccak256(serialized)) revert TCBInfo_Invalid();

        // Per-item adjacency: byteEnd < arrayEnd-1 ⇒ more items follow (raw[byteEnd] must be
        // ','); byteEnd == arrayEnd-1 ⇒ this is the last item in the whole array. The DAO
        // checks `state.expectedNextStart == arrayEnd` at finalize to confirm completion.
        if (byteEnd < arrayEnd - 1) {
            if (raw[byteEnd] != ",") revert TCBInfo_Invalid();
            nextExpectedStart = byteEnd + 1;
        } else {
            nextExpectedStart = arrayEnd;
        }
        packedItem = packedIdentity;
        nextCursor = cursor;
    }

    function _readU32(bytes calldata data, uint256 cursor) private pure returns (uint32 v, uint256 nextCursor) {
        if (cursor + 4 > data.length) revert TCBInfo_Invalid();
        v = uint32(bytes4(data[cursor:cursor + 4]));
        nextCursor = cursor + 4;
    }


    /// @notice Reconstruct the full V2/V3 final payload from the two verified-batch streams.
    /// Absorbs the abi.encode + stream decode bytecode so the DAO override stays tiny.
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
        bytes memory encodedTcbLevels = _streamToBytesArrayMem(levelsStream, totalLevels);
        TcbInfoJsonObj memory tcbInfoObj = TcbInfoJsonObj({tcbInfoStr: string(raw), signature: signature});
        if (basic.version < 3) {
            return abi.encode(basic, encodedTcbLevels, tcbInfoObj);
        }
        bytes memory encodedIdentities;
        if (totalIdentities > 0) {
            encodedIdentities = _streamToBytesArrayMem(identitiesStream, totalIdentities);
        }
        return abi.encode(basic, mod, encodedIdentities, encodedTcbLevels, tcbInfoObj);
    }

    function _streamToBytesArrayMem(bytes calldata stream, uint256 itemCount)
        private
        pure
        returns (bytes memory)
    {
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
        return abi.encode(items);
    }

    // -------- TDX module identity serializer --------

    error Invalid_Hex();
    error Hex_Mismatch();
    error Nested_TcbDate_Mismatch();
    error Identity_Field_Length();
    error Nested_Count_Mismatch();

    /// @notice Serialize a TDX module identity object back to its exact Intel-JSON form.
    /// @dev Carries Intel's exact ASCII hex strings for mrsigner/attributes/attributesMask so
    /// no case/format guessing is needed. The helper also cross-checks the hex strings against
    /// the packed bytes (so a worker cannot lie by submitting a hex string that doesn't decode
    /// to the bytes inside packedIdentity).
    /// @param packedIdentity output of FmspcTcbHelper.tdxModuleIdentityToBytes
    /// @param rawMrsignerHex  96 ASCII hex chars (case insensitive) — decodes to packed[32:80]
    /// @param rawAttributesHex 16 ASCII hex chars — decodes to packed[96:104]
    /// @param rawAttributesMaskHex 16 ASCII hex chars — decodes to packed[112:120]
    /// @param nestedRawTcbDates 20-byte ISO timestamps, one per nested tcbLevel, in source order
    function serializeTdxModuleIdentity(
        bytes calldata packedIdentity,
        bytes calldata rawMrsignerHex,
        bytes calldata rawAttributesHex,
        bytes calldata rawAttributesMaskHex,
        bytes20[] calldata nestedRawTcbDates
    ) external pure returns (bytes memory out) {
        // Convenience wrapper for callers (tests) that have no nested advisoryIDs.
        bytes[][] memory empty = new bytes[][](nestedRawTcbDates.length);
        for (uint256 i = 0; i < nestedRawTcbDates.length; i++) empty[i] = new bytes[](0);
        out = _serializeIdentityInternal(
            packedIdentity, rawMrsignerHex, rawAttributesHex, rawAttributesMaskHex, nestedRawTcbDates, empty
        );
    }

    function _serializeIdentityInternal(
        bytes calldata packedIdentity,
        bytes calldata rawMrsignerHex,
        bytes calldata rawAttributesHex,
        bytes calldata rawAttributesMaskHex,
        bytes20[] memory nestedRawTcbDates,
        bytes[][] memory nestedAdvisoryIDs
    ) private pure returns (bytes memory out) {
        // Length sanity: 4 fixed slots (128 bytes) + 32 bytes per nested level.
        if (packedIdentity.length < 128 || (packedIdentity.length - 128) % 32 != 0) {
            revert Invalid_Packed_Level();
        }
        uint256 nestedCount = (packedIdentity.length - 128) / 32;
        if (nestedCount != nestedRawTcbDates.length) revert Nested_Count_Mismatch();

        if (rawMrsignerHex.length != 96) revert Identity_Field_Length();
        if (rawAttributesHex.length != 16) revert Identity_Field_Length();
        if (rawAttributesMaskHex.length != 16) revert Identity_Field_Length();

        // 1) Cross-check hex strings against packed bytes
        _hexCheck(rawMrsignerHex, packedIdentity[32:80]);
        _hexCheck(rawAttributesHex, packedIdentity[96:104]);
        _hexCheck(rawAttributesMaskHex, packedIdentity[112:120]);

        // 2) Cross-check nested tcbDates against packed timestamps
        for (uint256 i = 0; i < nestedCount; i++) {
            uint256 slotOffset = 128 + i * 32;
            uint64 packedTs;
            assembly {
                let slot := calldataload(add(packedIdentity.offset, slotOffset))
                packedTs := and(shr(64, slot), 0xffffffffffffffff)
            }
            string memory iso = string(abi.encodePacked(nestedRawTcbDates[i]));
            uint64 derivedTs = uint64(DateTimeUtils.fromISOToTimestamp(iso));
            if (derivedTs != packedTs) revert Nested_TcbDate_Mismatch();
        }

        // 3) Extract id from packed[0:32] via Solady's packOne layout
        string memory idStr = LibString.unpackOne(bytes32(packedIdentity[0:32]));

        // 4) Build nested tcbLevels JSON
        bytes memory nested = bytes("[");
        for (uint256 i = 0; i < nestedCount; i++) {
            uint256 slotOffset = 128 + i * 32;
            uint8 isvsvn;
            uint8 status;
            assembly {
                let slot := calldataload(add(packedIdentity.offset, slotOffset))
                isvsvn := and(shr(128, slot), 0xff)
                status := and(slot, 0xff)
            }
            bytes memory comma = (i == 0) ? bytes("") : bytes(",");
            nested = bytes.concat(
                nested,
                comma,
                bytes('{"tcb":{"isvsvn":'),
                bytes(LibString.toString(uint256(isvsvn))),
                bytes('},"tcbDate":"'),
                abi.encodePacked(nestedRawTcbDates[i]),
                bytes('","tcbStatus":"'),
                bytes(_statusToString(status)),
                bytes('"'),
                _emitAdvisorySegmentArray(nestedAdvisoryIDs[i]),
                bytes("}")
            );
        }
        nested = bytes.concat(nested, bytes("]"));

        // 5) Compose final identity JSON
        out = bytes.concat(
            bytes('{"id":"'),
            bytes(idStr),
            bytes('","mrsigner":"'),
            rawMrsignerHex,
            bytes('","attributes":"'),
            rawAttributesHex,
            bytes('","attributesMask":"'),
            rawAttributesMaskHex,
            bytes('","tcbLevels":'),
            nested,
            bytes('}')
        );
    }

    /// @dev Verify `hexStr` (ASCII hex chars, case insensitive) decodes to exactly `expected`.
    function _hexCheck(bytes calldata hexStr, bytes calldata expected) private pure {
        if (hexStr.length != expected.length * 2) revert Identity_Field_Length();
        for (uint256 i = 0; i < expected.length; i++) {
            uint8 hi = _hexNibble(uint8(hexStr[2 * i]));
            uint8 lo = _hexNibble(uint8(hexStr[2 * i + 1]));
            uint8 byteVal = (hi << 4) | lo;
            if (byteVal != uint8(expected[i])) revert Hex_Mismatch();
        }
    }

    function _hexNibble(uint8 c) private pure returns (uint8) {
        if (c >= 0x30 && c <= 0x39) return c - 0x30;       // '0'..'9'
        if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;  // 'a'..'f'
        if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;  // 'A'..'F'
        revert Invalid_Hex();
    }
}
