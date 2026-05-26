// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../pcs/PCSSetupBase.t.sol";
import {AutomataDaoStorage} from "../../src/automata_pccs/shared/AutomataDaoStorage.sol";
import {AutomataDaoStorageV2} from "../../src/automata_pccs/shared/AutomataDaoStorageV2.sol";
import {AutomataPcsDao} from "../../src/automata_pccs/AutomataPcsDao.sol";
import {AutomataFmspcTcbDaoVersionedV2} from "../../src/automata_pccs/versioned/AutomataFmspcTcbDaoVersionedV2.sol";
import {FmspcTcbHelperV2} from "../../src/helpers/FmspcTcbHelperV2.sol";
import {AlwaysTrueP256Verifier} from "../mock/AlwaysTrueP256Verifier.sol";

/// @notice Keeps the live-fixture harness compiling while the end-to-end coverage
/// moves to the QPL-driven async V2 flow. The old replay used the removed
/// chunk/commit ABI and is intentionally not kept as a compatibility path.
contract AutomataTcbDaoV2LiveTest is PCSSetupBase {
    uint32 internal constant TEST_EVAL = 19;

    AutomataDaoStorage storageAsyncFallback;
    AutomataDaoStorageV2 storageV2;
    AutomataPcsDao pcsAsync;
    AutomataFmspcTcbDaoVersionedV2 daoV2;
    FmspcTcbHelperV2 fmspcTcbLibV2;
    AlwaysTrueP256Verifier verifierStub;

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

        vm.stopPrank();
    }

    function testLive_V2_UsesOptimizedAsyncProtocol() public {
        assertEq(daoV2.asyncUpsertProtocolVersion(), 2);
    }
}
