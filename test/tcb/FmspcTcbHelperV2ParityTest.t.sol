// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {
    FmspcTcbHelper,
    TcbInfoBasic,
    TcbId,
    TCBLevelsObj,
    TDXModule,
    TDXModuleIdentity
} from "../../src/helpers/FmspcTcbHelper.sol";
import {FmspcTcbHelperV2} from "../../src/helpers/FmspcTcbHelperV2.sol";
import "./TCBConstants.t.sol";

/// @notice Asserts that V2's hand-rolled extractBasics + findArrayBounds produces field-by-field
/// identical results to V1 helper's Solady-based parseTcbString + parseTdxModule +
/// parseTcbLevels + parseTcbTdxModules, across:
///   - every published SGX V4 fmspc (37 fixtures under test/tcb/fixtures/pcs/sgx_*.tcbInfo)
///   - every published TDX V4 fmspc (14 fixtures under test/tcb/fixtures/pcs/tdx_*.tcbInfo)
///   - the embedded schema-v2 fixture (`sgx_v2_tcbStr` from TCBConstants)
/// The fixtures are downloaded by test/tcb/fixtures/pcs/fetch.sh and committed alongside.
///
/// If you add fixtures (e.g. new fmspcs Intel publishes), drop them under that dir and re-run.
contract FmspcTcbHelperV2ParityTest is TCBConstants, Test {
    FmspcTcbHelper internal v1;
    FmspcTcbHelperV2 internal candidate;

    function setUp() public {
        v1 = new FmspcTcbHelper();
        candidate = new FmspcTcbHelperV2();
    }

    function testParity_AllPcsFixtures() public {
        VmSafe.DirEntry[] memory entries = vm.readDir("test/tcb/fixtures/pcs");
        uint256 covered;
        for (uint256 i = 0; i < entries.length; i++) {
            string memory path = entries[i].path;
            if (!_endsWith(path, ".tcbInfo")) continue;
            string memory raw = vm.readFile(path);
            _assertParity(path, raw);
            covered++;
        }
        // 37 SGX + 14 TDX = 51 published fmspcs as of 2026-05.
        assertGe(covered, 51, "expected at least 51 PCS fixtures (run test/tcb/fixtures/pcs/fetch.sh)");
    }

    function testParity_EmbeddedSchemaV2Sgx() public {
        _assertParity("sgx_v2_tcbStr", string(sgx_v2_tcbStr));
    }

    function testParity_EmbeddedSchemaV3Sgx() public {
        _assertParity("sgx_v3_tcbStr", string(sgx_v3_tcbStr));
    }

    function testParity_EmbeddedSchemaV3Tdx() public {
        _assertParity("tdx_tcbStr", tdx_tcbStr);
    }

    /* -------- core assertion -------- */

    function _assertParity(string memory label, string memory rawStr) internal {
        // Reference (Solady) pipeline — same calls _ensureBasicParsed makes in V2.
        (TcbInfoBasic memory refBasic,
         string memory tcbLevelsString,
         string memory tdxModuleString,
         string memory tdxModuleIdentitiesString) = v1.parseTcbString(rawStr);

        TDXModule memory refModule;
        bool refHasModule;
        if (bytes(tdxModuleString).length > 0) {
            refModule = v1.parseTdxModule(tdxModuleString);
            refHasModule = true;
        }
        TCBLevelsObj[] memory refLevels = v1.parseTcbLevels(uint256(refBasic.version), tcbLevelsString);
        uint256 refLevelCount = refLevels.length;
        uint256 refIdentityCount;
        if (refBasic.id == TcbId.TDX) {
            bytes memory minimalTdxModule = bytes(
                "{\"mrsigner\":\"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\",\"attributes\":\"0000000000000000\",\"attributesMask\":\"FFFFFFFFFFFFFFFF\"}"
            );
            (, TDXModuleIdentity[] memory refIdentities) =
                v1.parseTcbTdxModules(string(minimalTdxModule), tdxModuleIdentitiesString);
            refIdentityCount = refIdentities.length;
        }

        // Candidate (hand-rolled) pipeline.
        bytes memory rawBytes = bytes(rawStr);
        (TcbInfoBasic memory candBasic,
         TDXModule memory candModule,
         bool candHasModule,
         uint32 candTdxObjStart,
         uint32 candTdxObjEnd) = candidate.extractBasics(rawBytes);
        (
            uint32 tcbStart,
            uint32 tcbEnd,
            uint32 idStart,
            uint32 idEnd,
            uint32 candLevelCount,
            uint32 candIdentityCount
        ) = candidate.findArrayBounds(rawBytes);

        // ---- TcbInfoBasic field-by-field ----
        assertEq(uint256(candBasic.tcbType), uint256(refBasic.tcbType), _msg(label, "tcbType"));
        assertEq(uint256(candBasic.id), uint256(refBasic.id), _msg(label, "id"));
        assertEq(uint256(candBasic.version), uint256(refBasic.version), _msg(label, "version"));
        assertEq(uint256(candBasic.issueDate), uint256(refBasic.issueDate), _msg(label, "issueDate"));
        assertEq(uint256(candBasic.nextUpdate), uint256(refBasic.nextUpdate), _msg(label, "nextUpdate"));
        assertEq(
            uint256(candBasic.evaluationDataNumber),
            uint256(refBasic.evaluationDataNumber),
            _msg(label, "evaluationDataNumber")
        );
        assertEq(candBasic.fmspc, refBasic.fmspc, _msg(label, "fmspc"));
        assertEq(candBasic.pceid, refBasic.pceid, _msg(label, "pceid"));

        // ---- TDXModule field-by-field ----
        assertEq(candHasModule, refHasModule, _msg(label, "hasTdxModule"));
        if (refHasModule) {
            assertEq(
                keccak256(candModule.mrsigner),
                keccak256(refModule.mrsigner),
                _msg(label, "tdxModule.mrsigner")
            );
            assertEq(candModule.attributes, refModule.attributes, _msg(label, "tdxModule.attributes"));
            assertEq(
                candModule.attributesMask,
                refModule.attributesMask,
                _msg(label, "tdxModule.attributesMask")
            );
        }

        // ---- counts ----
        assertEq(uint256(candLevelCount), refLevelCount, _msg(label, "tcbLevels count"));
        assertEq(uint256(candIdentityCount), refIdentityCount, _msg(label, "tdxModuleIdentities count"));

        // ---- string substrings (used by finalize's contentHash; V2 slices them from raw
        //      using these byte ranges instead of re-parsing with Solady) ----
        assertEq(
            keccak256(bytes(_sliceStr(rawBytes, tcbStart, tcbEnd))),
            keccak256(bytes(tcbLevelsString)),
            _msg(label, "tcbLevelsString slice")
        );
        if (candHasModule) {
            assertEq(
                keccak256(bytes(_sliceStr(rawBytes, candTdxObjStart, candTdxObjEnd))),
                keccak256(bytes(tdxModuleString)),
                _msg(label, "tdxModuleString slice")
            );
        } else {
            assertEq(bytes(tdxModuleString).length, 0, _msg(label, "tdxModuleString empty"));
        }
        if (idEnd > idStart) {
            assertEq(
                keccak256(bytes(_sliceStr(rawBytes, idStart, idEnd))),
                keccak256(bytes(tdxModuleIdentitiesString)),
                _msg(label, "tdxModuleIdentitiesString slice")
            );
        } else {
            assertEq(bytes(tdxModuleIdentitiesString).length, 0, _msg(label, "tdxModuleIdentitiesString empty"));
        }
    }

    function _sliceStr(bytes memory src, uint256 start, uint256 end) internal pure returns (string memory) {
        bytes memory out = new bytes(end - start);
        for (uint256 i = 0; i < end - start; i++) {
            out[i] = src[start + i];
        }
        return string(out);
    }

    /* -------- helpers -------- */

    function _endsWith(string memory s, string memory suffix) internal pure returns (bool) {
        bytes memory sb = bytes(s);
        bytes memory tb = bytes(suffix);
        if (sb.length < tb.length) return false;
        uint256 off = sb.length - tb.length;
        for (uint256 i = 0; i < tb.length; i++) {
            if (sb[off + i] != tb[i]) return false;
        }
        return true;
    }

    function _msg(string memory label, string memory field) internal pure returns (string memory) {
        return string(abi.encodePacked("parity mismatch [", label, "].", field));
    }
}
