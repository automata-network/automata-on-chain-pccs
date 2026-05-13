// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {CA} from "../../src/Common.sol";
import {AutomataDaoStorage} from "../../src/automata_pccs/shared/AutomataDaoStorage.sol";
import {AutomataDaoStorageV2} from "../../src/automata_pccs/shared/AutomataDaoStorageV2.sol";
import {AutomataPcsDao} from "../../src/automata_pccs/AutomataPcsDao.sol";
import {AutomataFmspcTcbDaoVersioned} from "../../src/automata_pccs/versioned/AutomataFmspcTcbDaoVersioned.sol";
import {AutomataFmspcTcbDaoVersionedV2} from "../../src/automata_pccs/versioned/AutomataFmspcTcbDaoVersionedV2.sol";
import {FmspcTcbHelper} from "../../src/helpers/FmspcTcbHelper.sol";
import {FmspcTcbHelperV2} from "../../src/helpers/FmspcTcbHelperV2.sol";
import {X509CRLHelper} from "../../src/helpers/X509CRLHelper.sol";
import {PCKHelper} from "../../src/helpers/PCKHelper.sol";
import {AlwaysTrueP256Verifier} from "../../test/mock/AlwaysTrueP256Verifier.sol";
import {PCSConstants} from "../../test/pcs/PCSConstants.t.sol";

contract DeployLocalTcbBench is Script, PCSConstants {
    uint32 internal constant TEST_EVAL = 19;
    address internal constant ATTESTER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    string internal constant OUTPUT_PATH = "./script/bench/local-tcb-bench.json";

    function run() external {
        address admin = ATTESTER;
        vm.warp(1718785993);
        vm.startBroadcast();

        AlwaysTrueP256Verifier verifierStub = new AlwaysTrueP256Verifier();
        FmspcTcbHelper fmspcTcbLib = new FmspcTcbHelper();
        FmspcTcbHelperV2 fmspcTcbLibV2 = new FmspcTcbHelperV2();
        X509CRLHelper x509CrlLib = new X509CRLHelper();
        PCKHelper x509Lib = new PCKHelper();

        AutomataDaoStorage storageSync = new AutomataDaoStorage(admin);
        AutomataDaoStorage storageAsyncFallback = new AutomataDaoStorage(admin);

        AutomataPcsDao pcsSync =
            new AutomataPcsDao(address(storageSync), address(verifierStub), address(x509Lib), address(x509CrlLib));
        AutomataPcsDao pcsAsync = new AutomataPcsDao(
            address(storageAsyncFallback), address(verifierStub), address(x509Lib), address(x509CrlLib)
        );

        AutomataFmspcTcbDaoVersioned daoV1 = new AutomataFmspcTcbDaoVersioned(
            address(storageSync),
            address(verifierStub),
            address(pcsSync),
            address(fmspcTcbLib),
            address(x509Lib),
            address(x509CrlLib),
            admin,
            TEST_EVAL
        );

        AutomataDaoStorageV2 storageV2 = new AutomataDaoStorageV2(admin, address(storageAsyncFallback));
        AutomataFmspcTcbDaoVersionedV2 daoV2 = new AutomataFmspcTcbDaoVersionedV2(
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

        daoV1.grantRoles(ATTESTER, daoV1.ATTESTER_ROLE());
        daoV2.grantRoles(ATTESTER, daoV2.ATTESTER_ROLE());

        _seedPcs(pcsSync, storageSync);
        _seedPcs(pcsAsync, storageAsyncFallback);

        vm.stopBroadcast();

        string memory benchJson;
        benchJson = vm.serializeAddress("bench", "storage_sync", address(storageSync));
        benchJson = vm.serializeAddress("bench", "storage_async_fallback", address(storageAsyncFallback));
        benchJson = vm.serializeAddress("bench", "storage_v2", address(storageV2));
        benchJson = vm.serializeAddress("bench", "pcs_sync", address(pcsSync));
        benchJson = vm.serializeAddress("bench", "pcs_async", address(pcsAsync));
        benchJson = vm.serializeAddress("bench", "dao_v1", address(daoV1));
        benchJson = vm.serializeAddress("bench", "dao_v2", address(daoV2));
        vm.writeJson(benchJson, OUTPUT_PATH);
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

}
