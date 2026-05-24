// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../pcs/PCSSetupBase.t.sol";
import {CA} from "../../src/Common.sol";
import {AutomataDaoStorage} from "../../src/automata_pccs/shared/AutomataDaoStorage.sol";
import {AutomataDaoStorageV2} from "../../src/automata_pccs/shared/AutomataDaoStorageV2.sol";
import {AutomataPcsDao} from "../../src/automata_pccs/AutomataPcsDao.sol";
import {AutomataFmspcTcbDaoVersionedV2} from
    "../../src/automata_pccs/versioned/AutomataFmspcTcbDaoVersionedV2.sol";
import {FmspcTcbDaoV2} from "../../src/bases/FmspcTcbDaoV2.sol";
import {TcbInfoJsonObj, TCBLevelsObj, TcbId} from "../../src/helpers/FmspcTcbHelper.sol";
import {FmspcTcbHelperV2, TcbInfoRanges} from "../../src/helpers/FmspcTcbHelperV2.sol";
import {AlwaysTrueP256Verifier} from "../mock/AlwaysTrueP256Verifier.sol";

/// @notice Replays the V2 async upsert against the LIVE Intel response we captured at
/// test/tcb/fixtures/live_intel_eval19_inner.txt to reproduce the on-chain revert seen in the
/// fork-aeneid e2e run. If this test reverts in the same place, foundry's trace gives us the
/// exact location.
contract AutomataTcbDaoV2LiveTest is PCSSetupBase {
    uint32 internal constant TEST_EVAL = 19;
    uint8 internal constant SGX_TCB_TYPE = 0;
    bytes6 internal constant LIVE_FMSPC = hex"00606a000000";
    uint32 internal constant TEST_VERSION = 3;

    AutomataDaoStorage storageAsyncFallback;
    AutomataDaoStorageV2 storageV2;
    AutomataPcsDao pcsAsync;
    AutomataFmspcTcbDaoVersionedV2 daoV2;
    FmspcTcbHelperV2 fmspcTcbLibV2;
    AlwaysTrueP256Verifier verifierStub;
    address attester = address(0xBEEF);

    function setUp() public override {
        super.setUp();
        vm.startPrank(admin);

        verifierStub = new AlwaysTrueP256Verifier();
        fmspcTcbLibV2 = new FmspcTcbHelperV2();

        storageAsyncFallback = new AutomataDaoStorage(admin);
        pcsAsync = new AutomataPcsDao(
            address(storageAsyncFallback), address(verifierStub), address(x509Lib), address(x509CrlLib)
        );
        storageV2 = new AutomataDaoStorageV2(admin, address(storageAsyncFallback));
        daoV2 = new AutomataFmspcTcbDaoVersionedV2(
            address(storageV2),
            address(verifierStub),
            address(pcsAsync),
            address(fmspcTcbLib),
            address(fmspcTcbLibV2),
            address(x509Lib),
            address(x509CrlLib),
            admin,
            TEST_EVAL
        );

        storageAsyncFallback.grantDao(address(pcsAsync));
        storageAsyncFallback.grantDao(address(storageV2));
        storageAsyncFallback.grantDao(admin);
        storageAsyncFallback.setCallerAuthorization(admin, true);

        storageV2.grantDao(admin);
        storageV2.grantDao(address(daoV2));
        storageV2.setCallerAuthorization(admin, true);

        daoV2.grantRoles(attester, daoV2.ATTESTER_ROLE());
        _seedPcs(pcsAsync, storageAsyncFallback);
        vm.stopPrank();
    }

    function testLive_V2_FreshUpsertReproducesE2eFailure() public {
        // The live Intel payload nextUpdate is 2026-06-19; warp to a date inside that window.
        vm.warp(1779292924); // 2026-05-20 16:02:04Z (matches the live issueDate)

        string memory raw = vm.readFile("test/tcb/fixtures/live_intel_eval19_inner.txt");
        string memory sigHex = vm.readFile("test/tcb/fixtures/live_intel_eval19_sig.txt");
        bytes memory signature = vm.parseBytes(string.concat("0x", sigHex));

        bytes32 refId = keccak256("live-v2-test");
        vm.startPrank(attester);
        daoV2.startAsyncUpsert(refId, signature);

        // Upload raw in 4KB chunks (mirrors the QPL chunking).
        bytes memory rawBytes = bytes(raw);
        for (uint256 cursor = 0; cursor < rawBytes.length; cursor += 4096) {
            uint256 length = cursor + 4096 > rawBytes.length ? rawBytes.length - cursor : 4096;
            daoV2.uploadChunkData(refId, _slice(rawBytes, cursor, length));
        }

        // Use V2 helper's depth-1 scanner to get array bounds.
        TcbInfoRanges memory ranges;
        {
            (uint32 a, uint32 b, uint32 c, uint32 d,,) = fmspcTcbLibV2.findArrayBounds(rawBytes);
            ranges = TcbInfoRanges(a, b, c, d);
        }
        // Pull sgxComponents template from level[0] via brace scan.
        (uint32[] memory starts, uint32[] memory ends) =
            _braceScan(rawBytes, ranges.tcbLevelsArrayStart, ranges.tcbLevelsArrayEnd);
        bytes memory sgxTpl =
            _extractValueArrayBytes(rawBytes, starts[0], ends[0], "\"sgxtcbcomponents\":");
        // No TDX in this fixture.
        daoV2.uploadComponentsTemplate(refId, sgxTpl, bytes(""));
        // Use the staged commit trio (Tier 1) — keeps per-tx gas well under the cap.
        daoV2.commitBasicsExtract(refId);
        daoV2.commitTcbLevelsRange(refId);
        // SGX path — no tdxModuleIdentities tx needed.

        // Build the level stream.
        bytes memory tcbLevelsJson = _slice(rawBytes, ranges.tcbLevelsArrayStart, ranges.tcbLevelsArrayEnd - ranges.tcbLevelsArrayStart);
        TCBLevelsObj[] memory levels = fmspcTcbLib.parseTcbLevels(uint256(TEST_VERSION), string(tcbLevelsJson));
        assertEq(levels.length, starts.length, "level count mismatch");

        bytes memory levelStream;
        for (uint256 i = 0; i < levels.length; i++) {
            bytes memory packed = fmspcTcbLib.tcbLevelsObjToBytes(levels[i]);
            bytes20 rawDate = _extractRawTcbDate(rawBytes, starts[i], ends[i]);
            levelStream = bytes.concat(
                levelStream,
                abi.encodePacked(uint32(packed.length), packed, starts[i], ends[i], rawDate)
            );
        }

        daoV2.uploadParsedTcbLevelsBatch(refId, 0, starts.length, levelStream);

        bytes32 key = daoV2.FMSPC_TCB_KEY(SGX_TCB_TYPE, LIVE_FMSPC, TEST_VERSION);
        bytes32 attestationId = storageV2.collateralPointer(key);
        daoV2.finalizeAsyncUpsert(attestationId, refId);
        vm.stopPrank();
    }

    // --- helpers (copied from AutomataTcbDaoABTest pattern) ---

    function _slice(bytes memory data, uint256 start, uint256 length) internal pure returns (bytes memory out) {
        out = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            out[i] = data[start + i];
        }
    }

    function _seedPcs(AutomataPcsDao pcsDao, AutomataDaoStorage backingStorage) internal {
        pcsDao.upsertPcsCertificates(CA.ROOT, rootDer);
        pcsDao.upsertRootCACrl(rootCrlDer);
        pcsDao.upsertPcsCertificates(CA.SIGNING, signingDer);
        pcsDao.upsertPcsCertificates(CA.PLATFORM, platformDer);
        bytes32 pcsKey = pcsDao.PCS_KEY(CA.SIGNING, false);
        bytes32 validityKey = keccak256(abi.encodePacked(pcsKey, "pcsValidity"));
        uint256 slot = (uint256(uint64(block.timestamp - 1 days)) << 64) | uint64(block.timestamp + 3650 days);
        backingStorage.attest(validityKey, abi.encode(slot), bytes32(0));
    }

    function _braceScan(bytes memory raw, uint32 arrStart, uint32 arrEnd)
        internal
        pure
        returns (uint32[] memory starts, uint32[] memory ends)
    {
        uint32 count;
        uint32 depth;
        for (uint32 p = arrStart + 1; p < arrEnd - 1; p++) {
            bytes1 c = raw[p];
            if (c == "{") {
                if (depth == 0) count++;
                depth++;
            } else if (c == "}") {
                depth--;
            } else if (c == '"') {
                p++;
                while (p < arrEnd - 1 && raw[p] != '"') {
                    if (raw[p] == "\\") p++;
                    p++;
                }
            }
        }
        starts = new uint32[](count);
        ends = new uint32[](count);
        uint32 idx;
        uint32 d2;
        uint32 curStart;
        for (uint32 p = arrStart + 1; p < arrEnd - 1; p++) {
            bytes1 c = raw[p];
            if (c == "{") {
                if (d2 == 0) curStart = p;
                d2++;
            } else if (c == "}") {
                d2--;
                if (d2 == 0) {
                    starts[idx] = curStart;
                    ends[idx] = p + 1;
                    idx++;
                }
            } else if (c == '"') {
                p++;
                while (p < arrEnd - 1 && raw[p] != '"') {
                    if (raw[p] == "\\") p++;
                    p++;
                }
            }
        }
    }

    function _extractValueArrayBytes(bytes memory raw, uint32 start, uint32 end, bytes memory key)
        internal
        pure
        returns (bytes memory)
    {
        uint32 keyLen = uint32(key.length);
        uint32 hit = type(uint32).max;
        for (uint32 p = start; p + keyLen < end; p++) {
            bool m = true;
            for (uint32 j = 0; j < keyLen; j++) {
                if (raw[p + j] != key[j]) { m = false; break; }
            }
            if (m) { hit = p; break; }
        }
        require(hit != type(uint32).max, "key not found");
        uint32 arrStart = hit + keyLen;
        require(raw[arrStart] == "[", "value not array");
        uint32 depth;
        for (uint32 p = arrStart; p < end; p++) {
            bytes1 c = raw[p];
            if (c == "[") depth++;
            else if (c == "]") {
                depth--;
                if (depth == 0) return _slice(raw, arrStart, (p + 1) - arrStart);
            } else if (c == '"') {
                p++;
                while (p < end && raw[p] != '"') {
                    if (raw[p] == "\\") p++;
                    p++;
                }
            }
        }
        revert("array end not found");
    }

    function _extractRawTcbDate(bytes memory raw, uint32 start, uint32 end) internal pure returns (bytes20 rawDate) {
        bytes memory key = bytes("\"tcbDate\":\"");
        uint32 keyLen = uint32(key.length);
        for (uint32 p = start; p + keyLen + 20 < end; p++) {
            bool m = true;
            for (uint32 j = 0; j < keyLen; j++) {
                if (raw[p + j] != key[j]) { m = false; break; }
            }
            if (m) {
                uint32 dateStart = p + keyLen;
                for (uint32 k = 0; k < 20; k++) {
                    rawDate |= bytes20(uint160(uint8(raw[dateStart + k])) << uint160(8 * (19 - k)));
                }
                return rawDate;
            }
        }
        revert("tcbDate not found");
    }
}
