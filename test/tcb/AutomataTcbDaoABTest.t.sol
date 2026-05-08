// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../pcs/PCSSetupBase.t.sol";
import {TCBConstants} from "./TCBConstants.t.sol";
import {CA} from "../../src/Common.sol";
import {AutomataDaoStorage} from "../../src/automata_pccs/shared/AutomataDaoStorage.sol";
import {AutomataDaoStorageV2} from "../../src/automata_pccs/shared/AutomataDaoStorageV2.sol";
import {AutomataPcsDao} from "../../src/automata_pccs/AutomataPcsDao.sol";
import {AutomataFmspcTcbDaoVersioned} from "../../src/automata_pccs/versioned/AutomataFmspcTcbDaoVersioned.sol";
import {AutomataFmspcTcbDaoVersionedV2} from
    "../../src/automata_pccs/versioned/AutomataFmspcTcbDaoVersionedV2.sol";
import {TcbInfoJsonObj} from "../../src/helpers/FmspcTcbHelper.sol";
import {AlwaysTrueP256Verifier} from "../mock/AlwaysTrueP256Verifier.sol";

contract AutomataFmspcTcbDaoABTest is PCSSetupBase, TCBConstants {
    bytes6 internal constant CASE1_FMSPC = hex"00806f050000";
    bytes6 internal constant CASE23_FMSPC = hex"00606a000000";
    uint8 internal constant SGX_TCB_TYPE = 0;
    uint8 internal constant TDX_TCB_TYPE = 1;
    uint32 internal constant TEST_VERSION = 3;
    uint32 internal constant TEST_EVAL = 19;
    uint256 internal constant LEGACY_GAS_CAP = 1 << 24;

    AutomataDaoStorage storageSync;
    AutomataDaoStorage storageAsyncFallback;
    AutomataDaoStorageV2 storageV2;
    AutomataPcsDao pcsSync;
    AutomataPcsDao pcsAsync;
    AutomataFmspcTcbDaoVersioned daoV1;
    AutomataFmspcTcbDaoVersionedV2 daoV2;
    AlwaysTrueP256Verifier verifierStub;
    address attester = address(0xBEEF);

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        verifierStub = new AlwaysTrueP256Verifier();
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

        daoV1.grantRoles(attester, daoV1.ATTESTER_ROLE());
        daoV2.grantRoles(attester, daoV2.ATTESTER_ROLE());

        _seedPcs(pcsSync, storageSync);
        _seedPcs(pcsAsync, storageAsyncFallback);
        vm.stopPrank();
    }

    function testAB_SmallRealSgx_SyncAndAsyncMatch() public {
        vm.warp(1778889600); // 2026-05-15

        TcbInfoJsonObj memory tcbInfo = _loadFixture("case1_sgx_tcbinfo.json", "case1_sgx_signature.txt");
        bytes32 key = daoV1.FMSPC_TCB_KEY(SGX_TCB_TYPE, CASE1_FMSPC, TEST_VERSION);

        vm.prank(attester);
        daoV1.upsertFmspcTcb(tcbInfo);

        _asyncUpsert(keccak256("ab-small-sgx"), tcbInfo, SGX_TCB_TYPE, CASE1_FMSPC, 2048, 2);

        vm.startPrank(admin);
        TcbInfoJsonObj memory fetchedV1 = daoV1.getTcbInfo(SGX_TCB_TYPE, "00806F050000", TEST_VERSION);
        TcbInfoJsonObj memory fetchedV2 = daoV2.getTcbInfo(SGX_TCB_TYPE, "00806F050000", TEST_VERSION);
        assertEq(fetchedV1.signature, tcbInfo.signature);
        assertEq(fetchedV2.signature, tcbInfo.signature);
        assertEq(bytes(fetchedV1.tcbInfoStr), bytes(fetchedV2.tcbInfoStr));
        assertEq(fetchedV1.signature, fetchedV2.signature);
        assertEq(daoV1.getAttestedData(key), daoV2.getAttestedData(key));
        assertEq(daoV1.getCollateralHash(key), daoV2.getCollateralHash(key));
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

        vm.startPrank(admin);
        TcbInfoJsonObj memory fetchedV1 = daoV1.getTcbInfo(TDX_TCB_TYPE, "00806F050000", TEST_VERSION);
        TcbInfoJsonObj memory fetchedV2 = daoV2.getTcbInfo(TDX_TCB_TYPE, "00806F050000", TEST_VERSION);
        assertEq(bytes(fetchedV1.tcbInfoStr), bytes(tcbInfo.tcbInfoStr));
        assertEq(bytes(fetchedV2.tcbInfoStr), bytes(tcbInfo.tcbInfoStr));
        assertEq(fetchedV1.signature, tcbInfo.signature);
        assertEq(fetchedV2.signature, tcbInfo.signature);
        assertEq(daoV1.getAttestedData(key), daoV2.getAttestedData(key));
        assertEq(daoV1.getCollateralHash(key), daoV2.getCollateralHash(key));
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

        vm.startPrank(admin);
        TcbInfoJsonObj memory fetched = daoV2.getTcbInfo(SGX_TCB_TYPE, "00606A000000", TEST_VERSION);
        assertEq(bytes(fetched.tcbInfoStr), bytes(large.tcbInfoStr));
        assertEq(fetched.signature, large.signature);
        assertEq(daoV2.getCollateralHash(key), sha256(bytes(large.tcbInfoStr)));
        assertEq(
            keccak256(daoV2.getAttestedData(key)), keccak256(storageV2.readAttestation(storageV2.collateralPointer(key)))
        );
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

        vm.startPrank(attester);
        daoV2.startAsyncUpsert(refId, tcbInfo.signature);

        for (uint256 cursor = 0; cursor < raw.length; cursor += chunkSize) {
            uint256 length = chunkSize;
            if (cursor + length > raw.length) {
                length = raw.length - cursor;
            }
            daoV2.uploadChunckData(refId, _slice(raw, cursor, length));
        }

        bool complete;
        while (!complete) {
            (,,,, uint256 parsedLevels, uint256 totalLevels, uint256 parsedModuleIdentities,) =
                daoV2.asyncUpsertProgress(refId);
            uint256 start = parsedLevels < totalLevels ? parsedLevels : parsedModuleIdentities;
            (, , bool done) = daoV2.parseTCBInfo(refId, start, parseCount);
            complete = done;
        }

        bytes32 key = daoV2.FMSPC_TCB_KEY(tcbType, fmspc, TEST_VERSION);
        bytes32 attestationId = storageV2.collateralPointer(key);
        daoV2.finalizeAsyncUpsert(attestationId, refId);
        vm.stopPrank();
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
}
