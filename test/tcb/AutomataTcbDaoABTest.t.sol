// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../pcs/PCSSetupBase.t.sol";
import {TCBConstants} from "./TCBConstants.t.sol";
import {JSONParserLib} from "solady/utils/JSONParserLib.sol";
import {CA} from "../../src/Common.sol";
import {AutomataDaoStorage} from "../../src/automata_pccs/shared/AutomataDaoStorage.sol";
import {AutomataDaoStorageV2} from "../../src/automata_pccs/shared/AutomataDaoStorageV2.sol";
import {AutomataPcsDao} from "../../src/automata_pccs/AutomataPcsDao.sol";
import {AutomataFmspcTcbDaoVersioned} from "../../src/automata_pccs/versioned/AutomataFmspcTcbDaoVersioned.sol";
import {AutomataFmspcTcbDaoVersionedV2} from
    "../../src/automata_pccs/versioned/AutomataFmspcTcbDaoVersionedV2.sol";
import {AutomataFmspcTcbDaoVersionedV3} from
    "../../src/automata_pccs/versioned/AutomataFmspcTcbDaoVersionedV3.sol";
import {TcbInfoJsonObj, TCBLevelsObj, TDXModuleIdentity, TcbId} from "../../src/helpers/FmspcTcbHelper.sol";
import {FmspcTcbHelperV2} from "../../src/helpers/FmspcTcbHelperV2.sol";
import {FmspcTcbHelperV3} from "../../src/helpers/FmspcTcbHelperV3.sol";
import {FmspcTcbDaoV3} from "../../src/bases/FmspcTcbDaoV3.sol";
import {AlwaysTrueP256Verifier} from "../mock/AlwaysTrueP256Verifier.sol";

contract AutomataFmspcTcbDaoABTest is PCSSetupBase, TCBConstants {
    using JSONParserLib for JSONParserLib.Item;

    bytes6 internal constant CASE1_FMSPC = hex"00806f050000";
    bytes6 internal constant CASE23_FMSPC = hex"00606a000000";
    uint8 internal constant SGX_TCB_TYPE = 0;
    uint8 internal constant TDX_TCB_TYPE = 1;
    uint32 internal constant TEST_VERSION = 3;
    uint32 internal constant TEST_EVAL = 19;
    uint256 internal constant LEGACY_GAS_CAP = 1 << 24;

    AutomataDaoStorage storageSync;
    AutomataDaoStorage storageAsyncFallback;
    AutomataDaoStorage storageV3Fallback;
    AutomataDaoStorageV2 storageV2;
    AutomataDaoStorageV2 storageV3Backing;
    AutomataPcsDao pcsSync;
    AutomataPcsDao pcsAsync;
    AutomataPcsDao pcsV3;
    AutomataFmspcTcbDaoVersioned daoV1;
    AutomataFmspcTcbDaoVersionedV2 daoV2;
    AutomataFmspcTcbDaoVersionedV3 daoV3;
    FmspcTcbHelperV2 fmspcTcbLibV2;
    FmspcTcbHelperV3 fmspcTcbLibV3;
    AlwaysTrueP256Verifier verifierStub;
    address attester = address(0xBEEF);

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        verifierStub = new AlwaysTrueP256Verifier();
        fmspcTcbLibV2 = new FmspcTcbHelperV2();
        storageSync = new AutomataDaoStorage(admin);
        storageAsyncFallback = new AutomataDaoStorage(admin);

        pcsSync = new AutomataPcsDao(address(storageSync), address(verifierStub), address(x509Lib), address(x509CrlLib));
        pcsAsync =
            new AutomataPcsDao(address(storageAsyncFallback), address(verifierStub), address(x509Lib), address(x509CrlLib));

        daoV1 = new AutomataFmspcTcbDaoVersioned(
            address(storageSync),
            address(verifierStub),
            address(pcsSync),
            address(fmspcTcbLib),
            address(x509Lib),
            address(x509CrlLib),
            admin,
            TEST_EVAL
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

        fmspcTcbLibV3 = new FmspcTcbHelperV3();
        storageV3Fallback = new AutomataDaoStorage(admin);
        pcsV3 = new AutomataPcsDao(
            address(storageV3Fallback), address(verifierStub), address(x509Lib), address(x509CrlLib)
        );
        storageV3Backing = new AutomataDaoStorageV2(admin, address(storageV3Fallback));
        daoV3 = new AutomataFmspcTcbDaoVersionedV3(
            address(storageV3Backing),
            address(verifierStub),
            address(pcsV3),
            address(fmspcTcbLib),
            address(fmspcTcbLibV2),
            address(fmspcTcbLibV3),
            address(x509Lib),
            address(x509CrlLib),
            admin,
            TEST_EVAL
        );

        storageSync.grantDao(address(pcsSync));
        storageSync.grantDao(address(daoV1));
        storageSync.grantDao(admin);
        storageSync.setCallerAuthorization(admin, true);

        storageAsyncFallback.grantDao(address(pcsAsync));
        storageAsyncFallback.grantDao(address(storageV2));
        storageAsyncFallback.grantDao(admin);
        storageAsyncFallback.setCallerAuthorization(admin, true);

        storageV2.grantDao(admin);
        storageV2.grantDao(address(daoV2));
        storageV2.setCallerAuthorization(admin, true);

        storageV3Fallback.grantDao(address(pcsV3));
        storageV3Fallback.grantDao(address(storageV3Backing));
        storageV3Fallback.grantDao(admin);
        storageV3Fallback.setCallerAuthorization(admin, true);

        storageV3Backing.grantDao(admin);
        storageV3Backing.grantDao(address(daoV3));
        storageV3Backing.setCallerAuthorization(admin, true);

        daoV1.grantRoles(attester, daoV1.ATTESTER_ROLE());
        daoV2.grantRoles(attester, daoV2.ATTESTER_ROLE());
        daoV3.grantRoles(attester, daoV3.ATTESTER_ROLE());

        _seedPcs(pcsSync, storageSync);
        _seedPcs(pcsAsync, storageAsyncFallback);
        _seedPcs(pcsV3, storageV3Fallback);
        vm.stopPrank();
    }

    function testAB_SmallRealSgx_SyncAndAsyncMatch() public {
        vm.warp(1778889600); // 2026-05-15

        TcbInfoJsonObj memory tcbInfo = _loadFixture("case1_sgx_tcbinfo.json", "case1_sgx_signature.txt");
        bytes32 key = daoV1.FMSPC_TCB_KEY(SGX_TCB_TYPE, CASE1_FMSPC, TEST_VERSION);

        vm.prank(attester);
        daoV1.upsertFmspcTcb(tcbInfo);

        _asyncUpsert(keccak256("ab-small-sgx"), tcbInfo, SGX_TCB_TYPE, CASE1_FMSPC, 2048, 2);
        _asyncUpsertV3(keccak256("ab-small-sgx-v3"), tcbInfo, SGX_TCB_TYPE, CASE1_FMSPC);

        vm.startPrank(admin);
        TcbInfoJsonObj memory fetchedV1 = daoV1.getTcbInfo(SGX_TCB_TYPE, "00806F050000", TEST_VERSION);
        TcbInfoJsonObj memory fetchedV2 = daoV2.getTcbInfo(SGX_TCB_TYPE, "00806F050000", TEST_VERSION);
        TcbInfoJsonObj memory fetchedV3 = daoV3.getTcbInfo(SGX_TCB_TYPE, "00806F050000", TEST_VERSION);
        assertEq(fetchedV1.signature, tcbInfo.signature);
        assertEq(fetchedV2.signature, tcbInfo.signature);
        assertEq(fetchedV3.signature, tcbInfo.signature);
        assertEq(bytes(fetchedV1.tcbInfoStr), bytes(fetchedV2.tcbInfoStr));
        assertEq(bytes(fetchedV2.tcbInfoStr), bytes(fetchedV3.tcbInfoStr));
        // Byte-equality on the full encoded payload — V1 vs V2 vs V3 must be byte-identical.
        assertEq(daoV1.getAttestedData(key), daoV2.getAttestedData(key));
        assertEq(daoV2.getAttestedData(key), daoV3.getAttestedData(key));
        assertEq(daoV1.getCollateralHash(key), daoV2.getCollateralHash(key));
        assertEq(daoV2.getCollateralHash(key), daoV3.getCollateralHash(key));
        assertEq(daoV1.getCollateralHash(key), sha256(bytes(tcbInfo.tcbInfoStr)));
        vm.stopPrank();
    }

    function testAB_SmallRealTdx_SyncAndAsyncMatch() public {
        vm.warp(1778889600); // 2026-05-15

        TcbInfoJsonObj memory tcbInfo = _loadFixture("case1_tdx_tcbinfo.json", "case1_tdx_signature.txt");
        bytes32 key = daoV1.FMSPC_TCB_KEY(TDX_TCB_TYPE, CASE1_FMSPC, TEST_VERSION);

        vm.prank(attester);
        daoV1.upsertFmspcTcb(tcbInfo);
        _asyncUpsert(keccak256("ab-small-tdx"), tcbInfo, TDX_TCB_TYPE, CASE1_FMSPC, 2048, 2);
        _asyncUpsertV3(keccak256("ab-small-tdx-v3"), tcbInfo, TDX_TCB_TYPE, CASE1_FMSPC);

        vm.startPrank(admin);
        TcbInfoJsonObj memory fetchedV1 = daoV1.getTcbInfo(TDX_TCB_TYPE, "00806F050000", TEST_VERSION);
        TcbInfoJsonObj memory fetchedV2 = daoV2.getTcbInfo(TDX_TCB_TYPE, "00806F050000", TEST_VERSION);
        TcbInfoJsonObj memory fetchedV3 = daoV3.getTcbInfo(TDX_TCB_TYPE, "00806F050000", TEST_VERSION);
        assertEq(bytes(fetchedV1.tcbInfoStr), bytes(tcbInfo.tcbInfoStr));
        assertEq(bytes(fetchedV2.tcbInfoStr), bytes(tcbInfo.tcbInfoStr));
        assertEq(bytes(fetchedV3.tcbInfoStr), bytes(tcbInfo.tcbInfoStr));
        assertEq(fetchedV1.signature, tcbInfo.signature);
        assertEq(fetchedV2.signature, tcbInfo.signature);
        assertEq(fetchedV3.signature, tcbInfo.signature);
        assertEq(daoV1.getAttestedData(key), daoV2.getAttestedData(key));
        assertEq(daoV2.getAttestedData(key), daoV3.getAttestedData(key));
        assertEq(daoV1.getCollateralHash(key), daoV2.getCollateralHash(key));
        assertEq(daoV2.getCollateralHash(key), daoV3.getCollateralHash(key));
        vm.stopPrank();
    }

    function testAB_RollForward_OnlyValidityAndSignatureDiffer() public {
        vm.warp(1778889600); // 2026-05-15

        TcbInfoJsonObj memory first = _loadFixture("case2_sgx_2_tcbinfo.json", "case2_sgx_2_signature.txt");
        TcbInfoJsonObj memory second = _loadFixture("case2_sgx_1_tcbinfo.json", "case2_sgx_1_signature.txt");
        bytes32 key = daoV1.FMSPC_TCB_KEY(SGX_TCB_TYPE, CASE23_FMSPC, TEST_VERSION);

        vm.prank(attester);
        daoV1.upsertFmspcTcb(first);
        _asyncUpsert(keccak256("ab-roll-1"), first, SGX_TCB_TYPE, CASE23_FMSPC, 4096, 3);

        vm.startPrank(admin);
        bytes32 v1ContentHash0 = daoV1.getTcbInfoContentHash(key);
        bytes32 v2ContentHash0 = daoV2.getTcbInfoContentHash(key);
        bytes32 v1CollateralHash0 = daoV1.getCollateralHash(key);
        bytes32 v2CollateralHash0 = daoV2.getCollateralHash(key);
        vm.stopPrank();

        vm.prank(attester);
        daoV1.upsertFmspcTcb(second);
        _asyncUpsert(keccak256("ab-roll-2"), second, SGX_TCB_TYPE, CASE23_FMSPC, 4096, 3);

        vm.startPrank(admin);
        TcbInfoJsonObj memory fetchedV1 = daoV1.getTcbInfo(SGX_TCB_TYPE, "00606A000000", TEST_VERSION);
        TcbInfoJsonObj memory fetchedV2 = daoV2.getTcbInfo(SGX_TCB_TYPE, "00606A000000", TEST_VERSION);
        assertEq(bytes(fetchedV1.tcbInfoStr), bytes(second.tcbInfoStr));
        assertEq(bytes(fetchedV2.tcbInfoStr), bytes(second.tcbInfoStr));
        assertEq(fetchedV1.signature, second.signature);
        assertEq(fetchedV2.signature, second.signature);

        bytes32 v1ContentHash1 = daoV1.getTcbInfoContentHash(key);
        bytes32 v2ContentHash1 = daoV2.getTcbInfoContentHash(key);
        bytes32 v1CollateralHash1 = daoV1.getCollateralHash(key);
        bytes32 v2CollateralHash1 = daoV2.getCollateralHash(key);

        assertEq(v1ContentHash0, v1ContentHash1);
        assertEq(v2ContentHash0, v2ContentHash1);
        assertEq(v1ContentHash1, v2ContentHash1);
        assertTrue(v1CollateralHash0 != v1CollateralHash1);
        assertTrue(v2CollateralHash0 != v2CollateralHash1);
        assertEq(v1CollateralHash1, sha256(bytes(second.tcbInfoStr)));
        assertEq(v2CollateralHash1, sha256(bytes(second.tcbInfoStr)));
        assertEq(daoV1.getAttestedData(key), daoV2.getAttestedData(key));
        vm.stopPrank();
    }

    function testAB_LargeCollateral_LegacyFailsButAsyncSucceeds() public {
        vm.warp(1778889600); // 2026-05-15

        TcbInfoJsonObj memory large = _loadFixture("case3_sgx_tcbinfo.json", "case3_sgx_signature.txt");
        bytes32 key = daoV1.FMSPC_TCB_KEY(SGX_TCB_TYPE, CASE23_FMSPC, TEST_VERSION);

        vm.prank(attester);
        (bool success,) = address(daoV1).call{gas: LEGACY_GAS_CAP}(abi.encodeCall(daoV1.upsertFmspcTcb, (large)));
        assertFalse(success);

        _asyncUpsert(keccak256("ab-large"), large, SGX_TCB_TYPE, CASE23_FMSPC, 4096, 3);
        _asyncUpsertV3(keccak256("ab-large-v3"), large, SGX_TCB_TYPE, CASE23_FMSPC);

        vm.startPrank(admin);
        TcbInfoJsonObj memory fetched = daoV2.getTcbInfo(SGX_TCB_TYPE, "00606A000000", TEST_VERSION);
        TcbInfoJsonObj memory fetchedV3 = daoV3.getTcbInfo(SGX_TCB_TYPE, "00606A000000", TEST_VERSION);
        assertEq(bytes(fetched.tcbInfoStr), bytes(large.tcbInfoStr));
        assertEq(bytes(fetchedV3.tcbInfoStr), bytes(large.tcbInfoStr));
        assertEq(fetched.signature, large.signature);
        assertEq(fetchedV3.signature, large.signature);
        assertEq(daoV2.getCollateralHash(key), sha256(bytes(large.tcbInfoStr)));
        assertEq(daoV3.getCollateralHash(key), sha256(bytes(large.tcbInfoStr)));
        // V2 and V3 produce identical final stored payloads
        assertEq(daoV2.getAttestedData(key), daoV3.getAttestedData(key));
        vm.stopPrank();
    }

    /* ============================ V3 negative tests ============================ */

    function testV3_RejectsTamperedPackedLevel() public {
        vm.warp(1778889600);
        TcbInfoJsonObj memory tcbInfo = _loadFixture("case1_sgx_tcbinfo.json", "case1_sgx_signature.txt");
        V3Scratch memory s = _prepareV3Scratch(tcbInfo);
        bytes memory levelStream = _buildLevelStream(s);

        // Tamper: flip a byte in the first level's packed pcesvn position.
        // Stream layout per item: uint32(packedLen) | packed | u32 start | u32 end | bytes20 date
        // The first packed level begins at offset 4. pcesvn is at packed[14..16] (high 16 bits of slot 1).
        levelStream[4 + 15] ^= 0xff; // mutate low byte of pcesvn

        bytes32 refId = keccak256("v3-neg-tamper-packed");
        vm.startPrank(attester);
        daoV3.startAsyncUpsert(refId, tcbInfo.signature);
        for (uint256 cursor = 0; cursor < s.raw.length; cursor += 4096) {
            uint256 length = cursor + 4096 > s.raw.length ? s.raw.length - cursor : 4096;
            daoV3.uploadChunkData(refId, _slice(s.raw, cursor, length));
        }
        daoV3.uploadComponentsTemplate(refId, s.sgxTemplate, s.tdxTemplate);
        // V3 verifies levels at upload time, not finalize: the tampered packed bytes break
        // the serializer round-trip and the batch call reverts immediately.
        vm.expectRevert();
        daoV3.uploadParsedTcbLevelsBatchV3(refId, 0, s.levelStarts.length, levelStream);
        vm.stopPrank();
    }

    function testV3_RejectsTamperedByteRange() public {
        vm.warp(1778889600);
        TcbInfoJsonObj memory tcbInfo = _loadFixture("case1_sgx_tcbinfo.json", "case1_sgx_signature.txt");
        V3Scratch memory s = _prepareV3Scratch(tcbInfo);
        bytes memory levelStream = _buildLevelStream(s);

        // Tamper byteStart of the first level (offset = 4 + packedLen).
        // We need packedLen to find it.
        uint32 packedLen = uint32(bytes4(_slice(levelStream, 0, 4)));
        // Bump byteStart by +1 — breaks strict adjacency check (expected level0 start == arrStart+1).
        uint256 byteStartOffset = 4 + packedLen;
        levelStream[byteStartOffset + 3] = bytes1(uint8(levelStream[byteStartOffset + 3]) + 1); // little-endian-affecting

        bytes32 refId = keccak256("v3-neg-tamper-range");
        vm.startPrank(attester);
        daoV3.startAsyncUpsert(refId, tcbInfo.signature);
        for (uint256 cursor = 0; cursor < s.raw.length; cursor += 4096) {
            uint256 length = cursor + 4096 > s.raw.length ? s.raw.length - cursor : 4096;
            daoV3.uploadChunkData(refId, _slice(s.raw, cursor, length));
        }
        daoV3.uploadComponentsTemplate(refId, s.sgxTemplate, s.tdxTemplate);
        // Bumped byteStart breaks the per-batch adjacency check inside the helper.
        vm.expectRevert();
        daoV3.uploadParsedTcbLevelsBatchV3(refId, 0, s.levelStarts.length, levelStream);
        vm.stopPrank();
    }

    function testV3_RejectsMismatchedComponentsTemplate() public {
        vm.warp(1778889600);
        TcbInfoJsonObj memory tcbInfo = _loadFixture("case1_sgx_tcbinfo.json", "case1_sgx_signature.txt");
        V3Scratch memory s = _prepareV3Scratch(tcbInfo);
        bytes memory levelStream = _buildLevelStream(s);

        // Substitute a template that doesn't match the actual TCBInfo — e.g., empty array `[]`.
        bytes memory bogusTemplate = bytes("[]");

        bytes32 refId = keccak256("v3-neg-template");
        vm.startPrank(attester);
        daoV3.startAsyncUpsert(refId, tcbInfo.signature);
        for (uint256 cursor = 0; cursor < s.raw.length; cursor += 4096) {
            uint256 length = cursor + 4096 > s.raw.length ? s.raw.length - cursor : 4096;
            daoV3.uploadChunkData(refId, _slice(s.raw, cursor, length));
        }
        daoV3.uploadComponentsTemplate(refId, bogusTemplate, s.tdxTemplate);
        // The bogus template has no svn entries; helper's _spliceSvnsIntoTemplate fails.
        vm.expectRevert();
        daoV3.uploadParsedTcbLevelsBatchV3(refId, 0, s.levelStarts.length, levelStream);
        vm.stopPrank();
    }

    function testV3_RejectsMissingTemplate() public {
        vm.warp(1778889600);
        TcbInfoJsonObj memory tcbInfo = _loadFixture("case1_sgx_tcbinfo.json", "case1_sgx_signature.txt");
        V3Scratch memory s = _prepareV3Scratch(tcbInfo);
        bytes memory levelStream = _buildLevelStream(s);

        bytes32 refId = keccak256("v3-neg-missing-template");
        vm.startPrank(attester);
        daoV3.startAsyncUpsert(refId, tcbInfo.signature);
        for (uint256 cursor = 0; cursor < s.raw.length; cursor += 4096) {
            uint256 length = cursor + 4096 > s.raw.length ? s.raw.length - cursor : 4096;
            daoV3.uploadChunkData(refId, _slice(s.raw, cursor, length));
        }
        // Skip uploadComponentsTemplate. The template check fires at the start of the V3 level
        // batch upload, so we revert there.
        vm.expectRevert(FmspcTcbDaoV3.V3_Template_Missing.selector);
        daoV3.uploadParsedTcbLevelsBatchV3(refId, 0, s.levelStarts.length, levelStream);
        vm.stopPrank();
    }

    function testV3_RejectsTamperedTdxIdentity() public {
        vm.warp(1778889600);
        TcbInfoJsonObj memory tcbInfo = _loadFixture("case1_tdx_tcbinfo.json", "case1_tdx_signature.txt");
        V3Scratch memory s = _prepareV3Scratch(tcbInfo);
        bytes memory levelStream = _buildLevelStream(s);
        bytes memory idStream = _buildIdentityStream(s);

        // Tamper the first identity's packed bytes — flip a byte inside the mrsigner region (slot 2).
        // Layout: uint32 packedLen | packed | ...
        // packed[32..80] is mrsigner; flip byte 32.
        idStream[4 + 32] ^= 0xff;

        bytes32 refId = keccak256("v3-neg-tdx-id");
        vm.startPrank(attester);
        daoV3.startAsyncUpsert(refId, tcbInfo.signature);
        for (uint256 cursor = 0; cursor < s.raw.length; cursor += 4096) {
            uint256 length = cursor + 4096 > s.raw.length ? s.raw.length - cursor : 4096;
            daoV3.uploadChunkData(refId, _slice(s.raw, cursor, length));
        }
        daoV3.uploadComponentsTemplate(refId, s.sgxTemplate, s.tdxTemplate);
        daoV3.uploadParsedTcbLevelsBatchV3(refId, 0, s.levelStarts.length, levelStream);
        // Tampered mrsigner bytes diverge from the hex string carried in the stream — helper
        // detects the mismatch during per-batch verification.
        vm.expectRevert();
        daoV3.uploadParsedTdxModuleIdentitiesBatchV3(refId, 0, s.idStarts.length, idStream);
        vm.stopPrank();
    }

    function _asyncUpsert(
        bytes32 refId,
        TcbInfoJsonObj memory tcbInfo,
        uint8 tcbType,
        bytes6 fmspc,
        uint256 chunkSize,
        uint256 parseCount
    ) internal {
        bytes memory raw = bytes(tcbInfo.tcbInfoStr);
        string[] memory levelObjects = _extractObjectArray(tcbInfo.tcbInfoStr, "tcbLevels");
        string[] memory moduleIdentityObjects = _extractObjectArray(tcbInfo.tcbInfoStr, "tdxModuleIdentities");

        vm.startPrank(attester);
        daoV2.startAsyncUpsert(refId, tcbInfo.signature);

        for (uint256 cursor = 0; cursor < raw.length; cursor += chunkSize) {
            uint256 length = chunkSize;
            if (cursor + length > raw.length) {
                length = raw.length - cursor;
            }
            daoV2.uploadChunkData(refId, _slice(raw, cursor, length));
        }

        uint256 start;
        while (start < levelObjects.length) {
            string[] memory batch = _sliceStrings(levelObjects, start, parseCount);
            (uint256 parsed,,) = daoV2.uploadParsedTcbLevelsBatch(refId, start, batch);
            start += parsed;
        }

        start = 0;
        while (start < moduleIdentityObjects.length) {
            string[] memory batch = _sliceStrings(moduleIdentityObjects, start, parseCount);
            (uint256 parsed,,) = daoV2.uploadParsedTdxModuleIdentitiesBatch(refId, start, batch);
            start += parsed;
        }

        bytes32 key = daoV2.FMSPC_TCB_KEY(tcbType, fmspc, TEST_VERSION);
        bytes32 attestationId = storageV2.collateralPointer(key);
        daoV2.finalizeAsyncUpsert(attestationId, refId);
        vm.stopPrank();
    }

    /* ============================ V3 helpers ============================ */

    /// @dev Holds per-test scratch state for one V3 async upsert.
    struct V3Scratch {
        bytes raw;
        uint32 levelsArrStart;
        uint32 levelsArrEnd;
        uint32 idsArrStart;
        uint32 idsArrEnd;
        uint32[] levelStarts;
        uint32[] levelEnds;
        uint32[] idStarts;
        uint32[] idEnds;
        bytes sgxTemplate;
        bytes tdxTemplate;
    }

    function _asyncUpsertV3(bytes32 refId, TcbInfoJsonObj memory tcbInfo, uint8 tcbType, bytes6 fmspc)
        internal
        returns (bytes32 finalAttestationId)
    {
        V3Scratch memory s = _prepareV3Scratch(tcbInfo);

        vm.startPrank(attester);
        daoV3.startAsyncUpsert(refId, tcbInfo.signature);

        // Upload raw chunks (size 4096 to keep tx gas modest yet exercise multi-chunk).
        uint256 chunkSize = 4096;
        for (uint256 cursor = 0; cursor < s.raw.length; cursor += chunkSize) {
            uint256 length = chunkSize;
            if (cursor + length > s.raw.length) length = s.raw.length - cursor;
            daoV3.uploadChunkData(refId, _slice(s.raw, cursor, length));
        }

        daoV3.uploadComponentsTemplate(refId, s.sgxTemplate, s.tdxTemplate);
        daoV3.commitBasicsExtract(refId);
        daoV3.commitTcbLevelsRange(refId);
        if (s.idStarts.length > 0) {
            daoV3.commitTdxIdentitiesRange(refId);
        }

        bytes memory levelStream = _buildLevelStream(s);
        daoV3.uploadParsedTcbLevelsBatchV3(refId, 0, s.levelStarts.length, levelStream);

        if (s.idStarts.length > 0) {
            bytes memory idStream = _buildIdentityStream(s);
            daoV3.uploadParsedTdxModuleIdentitiesBatchV3(refId, 0, s.idStarts.length, idStream);
        }

        bytes32 key = daoV3.FMSPC_TCB_KEY(tcbType, fmspc, TEST_VERSION);
        finalAttestationId = storageV3Backing.collateralPointer(key);
        daoV3.finalizeAsyncUpsert(finalAttestationId, refId);
        vm.stopPrank();
    }

    function _prepareV3Scratch(TcbInfoJsonObj memory tcbInfo) internal view returns (V3Scratch memory s) {
        s.raw = bytes(tcbInfo.tcbInfoStr);
        (uint32 a, uint32 b, uint32 c, uint32 d,,) = fmspcTcbLibV3.findArrayBounds(s.raw);
        s.levelsArrStart = a;
        s.levelsArrEnd = b;
        s.idsArrStart = c;
        s.idsArrEnd = d;
        (s.levelStarts, s.levelEnds) = _braceScan(s.raw, s.levelsArrStart, s.levelsArrEnd);
        if (s.idsArrEnd > s.idsArrStart) {
            (s.idStarts, s.idEnds) = _braceScan(s.raw, s.idsArrStart, s.idsArrEnd);
        }
        // Pull components templates out of level[0]'s "tcb":{...} value
        s.sgxTemplate = _extractValueArrayBytes(s.raw, s.levelStarts[0], s.levelEnds[0], "\"sgxtcbcomponents\":");
        if (s.idStarts.length > 0) {
            s.tdxTemplate = _extractValueArrayBytes(s.raw, s.levelStarts[0], s.levelEnds[0], "\"tdxtcbcomponents\":");
        }
    }

    function _buildLevelStream(V3Scratch memory s) internal view returns (bytes memory stream) {
        bytes memory levelsJson = _slice(s.raw, s.levelsArrStart, s.levelsArrEnd - s.levelsArrStart);
        TCBLevelsObj[] memory levels = fmspcTcbLib.parseTcbLevels(uint256(TEST_VERSION), string(levelsJson));
        require(levels.length == s.levelStarts.length, "scan mismatch");
        for (uint256 i = 0; i < levels.length; i++) {
            bytes memory packed = fmspcTcbLib.tcbLevelsObjToBytes(levels[i]);
            bytes20 rawDate = _extractRawTcbDate(s.raw, s.levelStarts[i], s.levelEnds[i]);
            stream = bytes.concat(
                stream,
                abi.encodePacked(uint32(packed.length), packed, s.levelStarts[i], s.levelEnds[i], rawDate)
            );
        }
    }

    function _buildIdentityStream(V3Scratch memory s) internal view returns (bytes memory stream) {
        bytes memory idsJson = _slice(s.raw, s.idsArrStart, s.idsArrEnd - s.idsArrStart);
        bytes memory tdxModuleStr =
            bytes("{\"mrsigner\":\"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\",\"attributes\":\"0000000000000000\",\"attributesMask\":\"FFFFFFFFFFFFFFFF\"}");
        (, TDXModuleIdentity[] memory identities) =
            fmspcTcbLib.parseTcbTdxModules(string(tdxModuleStr), string(idsJson));
        require(identities.length == s.idStarts.length, "id scan mismatch");
        for (uint256 i = 0; i < identities.length; i++) {
            bytes memory packed = fmspcTcbLib.tdxModuleIdentityToBytes(identities[i]);
            bytes memory mrSignerHex = _extractFixedString(s.raw, s.idStarts[i], s.idEnds[i], "\"mrsigner\":\"", 96);
            bytes memory attrHex = _extractFixedString(s.raw, s.idStarts[i], s.idEnds[i], "\"attributes\":\"", 16);
            bytes memory attrMaskHex = _extractFixedString(s.raw, s.idStarts[i], s.idEnds[i], "\"attributesMask\":\"", 16);
            (bytes20[] memory nestedDates, bytes[][] memory nestedAdvisories) =
                _extractIdentityNestedFields(s.raw, s.idStarts[i], s.idEnds[i]);
            stream = bytes.concat(
                stream,
                abi.encodePacked(
                    uint32(packed.length),
                    packed,
                    s.idStarts[i],
                    s.idEnds[i],
                    mrSignerHex,
                    attrHex,
                    attrMaskHex,
                    uint32(nestedDates.length)
                )
            );
            for (uint256 j = 0; j < nestedDates.length; j++) {
                stream = bytes.concat(stream, abi.encodePacked(nestedDates[j], uint16(nestedAdvisories[j].length)));
                for (uint256 k = 0; k < nestedAdvisories[j].length; k++) {
                    stream = bytes.concat(
                        stream,
                        abi.encodePacked(uint16(nestedAdvisories[j][k].length), nestedAdvisories[j][k])
                    );
                }
            }
        }
    }

    function _braceScan(bytes memory raw, uint32 arrStart, uint32 arrEnd)
        internal
        pure
        returns (uint32[] memory starts, uint32[] memory ends)
    {
        require(raw[arrStart] == "[", "not array");
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

    /// @dev Extract a `key:[...]` array value (including outer brackets) inside a level object.
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
        if (hit == type(uint32).max) return bytes("");
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

    /// @dev Read `keyPrefix"value"` (fixed-length value) and return value bytes.
    function _extractFixedString(bytes memory raw, uint32 start, uint32 end, bytes memory key, uint32 valLen)
        internal
        pure
        returns (bytes memory)
    {
        uint32 keyLen = uint32(key.length);
        for (uint32 p = start; p + keyLen + valLen < end; p++) {
            bool m = true;
            for (uint32 j = 0; j < keyLen; j++) {
                if (raw[p + j] != key[j]) { m = false; break; }
            }
            if (m) return _slice(raw, p + keyLen, valLen);
        }
        revert("key not found");
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

    function _extractIdentityNestedFields(bytes memory raw, uint32 idStart, uint32 idEnd)
        internal
        pure
        returns (bytes20[] memory dates, bytes[][] memory advisories)
    {
        bytes memory key = bytes("\"tcbLevels\":");
        uint32 keyLen = uint32(key.length);
        uint32 hit = type(uint32).max;
        for (uint32 p = idStart; p + keyLen < idEnd; p++) {
            bool m = true;
            for (uint32 j = 0; j < keyLen; j++) {
                if (raw[p + j] != key[j]) { m = false; break; }
            }
            if (m) { hit = p; break; }
        }
        require(hit != type(uint32).max, "nested tcbLevels not found");
        uint32 arrStart = hit + keyLen;
        uint32 depth;
        uint32 arrEnd = arrStart;
        for (uint32 p = arrStart; p < idEnd; p++) {
            bytes1 c = raw[p];
            if (c == "[") depth++;
            else if (c == "]") {
                depth--;
                if (depth == 0) { arrEnd = p + 1; break; }
            } else if (c == '"') {
                p++;
                while (p < idEnd && raw[p] != '"') {
                    if (raw[p] == "\\") p++;
                    p++;
                }
            }
        }
        (uint32[] memory levelStarts, uint32[] memory levelEnds) = _braceScan(raw, arrStart, arrEnd);
        dates = new bytes20[](levelStarts.length);
        advisories = new bytes[][](levelStarts.length);
        for (uint256 i = 0; i < levelStarts.length; i++) {
            dates[i] = _extractRawTcbDate(raw, levelStarts[i], levelEnds[i]);
            advisories[i] = _extractAdvisoryIDs(raw, levelStarts[i], levelEnds[i]);
        }
    }

    function _extractAdvisoryIDs(bytes memory raw, uint32 start, uint32 end)
        internal
        pure
        returns (bytes[] memory ids)
    {
        bytes memory key = bytes("\"advisoryIDs\":[");
        uint32 keyLen = uint32(key.length);
        uint32 hit = type(uint32).max;
        for (uint32 p = start; p + keyLen < end; p++) {
            bool m = true;
            for (uint32 j = 0; j < keyLen; j++) {
                if (raw[p + j] != key[j]) { m = false; break; }
            }
            if (m) { hit = p; break; }
        }
        if (hit == type(uint32).max) return new bytes[](0);
        uint32 cursor = hit + keyLen;
        // count items
        uint32 count;
        uint32 p2 = cursor;
        while (p2 < end) {
            if (raw[p2] == "]") break;
            require(raw[p2] == '"', "expected quote");
            p2++;
            uint32 strStart = p2;
            while (p2 < end && raw[p2] != '"') p2++;
            require(p2 < end, "unterminated string");
            count++;
            p2++; // skip closing "
            strStart; // unused, just for count walk
            if (p2 < end && raw[p2] == ",") p2++;
        }
        ids = new bytes[](count);
        uint32 idx;
        cursor = hit + keyLen;
        while (cursor < end && idx < count) {
            require(raw[cursor] == '"', "expected quote 2");
            cursor++;
            uint32 strStart = cursor;
            while (cursor < end && raw[cursor] != '"') cursor++;
            ids[idx] = _slice(raw, strStart, cursor - strStart);
            idx++;
            cursor++;
            if (cursor < end && raw[cursor] == ",") cursor++;
        }
    }

    function _loadFixture(string memory tcbInfoPath, string memory signaturePath)
        internal
        view
        returns (TcbInfoJsonObj memory tcbInfo)
    {
        tcbInfo.tcbInfoStr = vm.readFile(string.concat("test/tcb/fixtures/", tcbInfoPath));
        string memory signatureHex = _trim(vm.readFile(string.concat("test/tcb/fixtures/", signaturePath)));
        tcbInfo.signature = vm.parseBytes(string.concat("0x", signatureHex));
    }

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

    function _trim(string memory value) internal pure returns (string memory) {
        bytes memory data = bytes(value);
        uint256 end = data.length;
        while (end > 0 && (data[end - 1] == "\n" || data[end - 1] == "\r" || data[end - 1] == " ")) {
            end--;
        }

        bytes memory out = new bytes(end);
        for (uint256 i = 0; i < end; i++) {
            out[i] = data[i];
        }
        return string(out);
    }

    function _extractObjectArray(string memory json, string memory fieldName)
        internal
        pure
        returns (string[] memory objects)
    {
        JSONParserLib.Item memory root = JSONParserLib.parse(json);
        JSONParserLib.Item[] memory fields = root.children();
        for (uint256 i = 0; i < fields.length; i++) {
            if (keccak256(bytes(JSONParserLib.decodeString(fields[i].key()))) == keccak256(bytes(fieldName))) {
                JSONParserLib.Item[] memory items = fields[i].children();
                objects = new string[](items.length);
                for (uint256 j = 0; j < items.length; j++) {
                    objects[j] = items[j].value();
                }
                return objects;
            }
        }
        return new string[](0);
    }

    function _sliceStrings(string[] memory items, uint256 start, uint256 maxLength)
        internal
        pure
        returns (string[] memory batch)
    {
        uint256 length = maxLength;
        if (start + length > items.length) {
            length = items.length - start;
        }
        batch = new string[](length);
        for (uint256 i = 0; i < length; i++) {
            batch[i] = items[start + i];
        }
    }
}
