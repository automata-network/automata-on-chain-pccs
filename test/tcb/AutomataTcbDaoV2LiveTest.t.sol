// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../pcs/PCSSetupBase.t.sol";
import {AutomataDaoStorage} from "../../src/automata_pccs/shared/AutomataDaoStorage.sol";
import {AutomataDaoStorageV2} from "../../src/automata_pccs/shared/AutomataDaoStorageV2.sol";
import {AutomataPcsDao} from "../../src/automata_pccs/AutomataPcsDao.sol";
import {AutomataFmspcTcbDaoVersionedV2} from "../../src/automata_pccs/versioned/AutomataFmspcTcbDaoVersionedV2.sol";
import {FmspcTcbHelperV2} from "../../src/helpers/FmspcTcbHelperV2.sol";
import {TcbId} from "../../src/helpers/FmspcTcbHelper.sol";
import {AlwaysTrueP256Verifier} from "../mock/AlwaysTrueP256Verifier.sol";

contract FmspcTcbDaoV2CompletenessHarness is AutomataFmspcTcbDaoVersionedV2 {
    constructor()
        AutomataFmspcTcbDaoVersionedV2(
            address(1),
            address(2),
            address(3),
            address(4),
            address(5),
            address(6),
            address(7),
            address(this),
            19
        )
    {}

    function setCompletenessState(
        bytes32 refId,
        TcbId tcbId,
        uint32 totalLevels,
        uint32 parsedLevels,
        uint32 levelsStreamLength,
        uint256 levelsStreamCursor,
        uint32 totalIdentities,
        uint32 parsedIdentities,
        uint32 identitiesStreamLength,
        uint256 identitiesStreamCursor
    ) external {
        AsyncUpsertState storage state = _asyncUpserts[refId];
        state.basicUploaded = true;
        state.basic.id = tcbId;
        state.totalLevels = totalLevels;
        state.parsedLevels = parsedLevels;
        state.levelsStreamLength = levelsStreamLength;
        state.levelsStreamCursor = levelsStreamCursor;
        state.totalModuleIdentities = totalIdentities;
        state.parsedModuleIdentities = parsedIdentities;
        state.identitiesStreamLength = identitiesStreamLength;
        state.identitiesStreamCursor = identitiesStreamCursor;
    }

    function parseComplete(bytes32 refId) external view returns (bool) {
        return _parseComplete(_asyncUpserts[refId]);
    }
}

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

    function testV2_ParseCompleteRequiresLevelsStreamToReachExpectedLength() public {
        FmspcTcbDaoV2CompletenessHarness harness = new FmspcTcbDaoV2CompletenessHarness();
        bytes32 refId = keccak256("sgx-incomplete-level-stream");

        harness.setCompletenessState(refId, TcbId.SGX, 2, 2, 96, 64, 0, 0, 0, 0);
        assertFalse(harness.parseComplete(refId));

        harness.setCompletenessState(refId, TcbId.SGX, 2, 2, 96, 96, 0, 0, 0, 0);
        assertTrue(harness.parseComplete(refId));
    }

    function testV2_ParseCompleteRequiresTdxIdentityStreamToReachExpectedLength() public {
        FmspcTcbDaoV2CompletenessHarness harness = new FmspcTcbDaoV2CompletenessHarness();
        bytes32 refId = keccak256("tdx-incomplete-identity-stream");

        harness.setCompletenessState(refId, TcbId.TDX, 2, 2, 96, 96, 1, 1, 128, 64);
        assertFalse(harness.parseComplete(refId));

        harness.setCompletenessState(refId, TcbId.TDX, 2, 2, 96, 96, 1, 1, 128, 128);
        assertTrue(harness.parseComplete(refId));
    }
}
