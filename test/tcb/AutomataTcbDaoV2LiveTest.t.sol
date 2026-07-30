// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../pcs/PCSSetupBase.t.sol";
import {AutomataDaoStorage} from "../../src/automata_pccs/shared/AutomataDaoStorage.sol";
import {AutomataDaoStorageV2} from "../../src/automata_pccs/shared/AutomataDaoStorageV2.sol";
import {AutomataPcsDao} from "../../src/automata_pccs/AutomataPcsDao.sol";
import {AutomataFmspcTcbDaoVersionedV2} from "../../src/automata_pccs/versioned/AutomataFmspcTcbDaoVersionedV2.sol";
import {PccsDependencyConfig} from "../../src/automata_pccs/shared/PccsDependencyConfig.sol";
import {FmspcTcbDaoV2} from "../../src/bases/FmspcTcbDaoV2.sol";
import {FmspcTcbHelperV2} from "../../src/helpers/FmspcTcbHelperV2.sol";
import {TcbId} from "../../src/helpers/FmspcTcbHelper.sol";
import {AlwaysTrueP256Verifier} from "../mock/AlwaysTrueP256Verifier.sol";

contract FmspcTcbDaoV2CompletenessHarness is AutomataFmspcTcbDaoVersionedV2 {
    constructor(address dependencyConfig)
        AutomataFmspcTcbDaoVersionedV2(
            address(1), address(2), dependencyConfig, address(4), address(5), address(6), address(this), 19
        )
    {}

    function setCompletenessState(
        bytes32 refId,
        TcbId tcbId,
        uint32 totalLevels,
        uint32 parsedLevels,
        uint32 levelsStreamLength,
        uint256 levelsStreamCursor,
        uint32 levelsRawEnd,
        uint32 levelsRawCursor,
        uint32 totalIdentities,
        uint32 parsedIdentities,
        uint32 identitiesStreamLength,
        uint256 identitiesStreamCursor,
        uint32 identitiesRawEnd,
        uint32 identitiesRawCursor
    ) external {
        AsyncUpsertState storage state = _asyncUpserts[refId];
        state.basicUploaded = true;
        state.basic.id = tcbId;
        state.totalLevels = totalLevels;
        state.parsedLevels = parsedLevels;
        state.levelsStreamLength = levelsStreamLength;
        state.levelsStreamCursor = levelsStreamCursor;
        state.ranges.tcbLevelsArrayEnd = levelsRawEnd;
        state.levelsRawCursor = levelsRawCursor;
        state.totalModuleIdentities = totalIdentities;
        state.parsedModuleIdentities = parsedIdentities;
        state.identitiesStreamLength = identitiesStreamLength;
        state.identitiesStreamCursor = identitiesStreamCursor;
        state.ranges.tdxIdentitiesArrayEnd = identitiesRawEnd;
        state.identitiesRawCursor = identitiesRawCursor;
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
    uint8 internal constant LEVEL_FLAG_HAS_ADVISORY_FIELD = 1;
    uint8 internal constant FIELD_ID = 0;
    uint8 internal constant FIELD_VERSION = 1;
    uint8 internal constant FIELD_TCB_LEVELS = 10;
    address internal asyncAttester = address(0x69);

    AutomataDaoStorage storageAsyncFallback;
    AutomataDaoStorageV2 storageV2;
    AutomataPcsDao pcsAsync;
    PccsDependencyConfig asyncDependencyConfig;
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
        asyncDependencyConfig = new PccsDependencyConfig(admin);
        asyncDependencyConfig.initialize(address(pcsAsync), address(x509CrlLib));
        storageV2 = new AutomataDaoStorageV2(admin, address(storageAsyncFallback));
        daoV2 = new AutomataFmspcTcbDaoVersionedV2(
            address(storageV2),
            address(verifierStub),
            address(asyncDependencyConfig),
            address(fmspcTcbLib),
            address(fmspcTcbLibV2),
            address(x509Lib),
            admin,
            TEST_EVAL
        );
        daoV2.grantRoles(asyncAttester, daoV2.ATTESTER_ROLE());

        vm.stopPrank();
    }

    function testLive_V2_UsesOptimizedAsyncProtocol() public {
        assertEq(daoV2.asyncUpsertProtocolVersion(), 2);
    }

    function testV2_StartAsyncUpsertRejectsZeroRefId() public {
        vm.expectRevert(FmspcTcbDaoV2.Async_Upsert_Invalid_Range.selector);
        vm.prank(asyncAttester);
        daoV2.startAsyncUpsert(bytes32(0), hex"01", 32);
    }

    function testV2_ParseCompleteRequiresLevelsStreamToReachExpectedLength() public {
        FmspcTcbDaoV2CompletenessHarness harness =
            new FmspcTcbDaoV2CompletenessHarness(address(asyncDependencyConfig));
        bytes32 refId = keccak256("sgx-incomplete-level-stream");

        harness.setCompletenessState(refId, TcbId.SGX, 2, 2, 96, 64, 100, 99, 0, 0, 0, 0, 0, 0);
        assertFalse(harness.parseComplete(refId));

        harness.setCompletenessState(refId, TcbId.SGX, 2, 2, 96, 96, 100, 99, 0, 0, 0, 0, 0, 0);
        assertTrue(harness.parseComplete(refId));
    }

    function testV2_ParseCompleteRequiresLevelsRawCursorToReachArrayEnd() public {
        FmspcTcbDaoV2CompletenessHarness harness =
            new FmspcTcbDaoV2CompletenessHarness(address(asyncDependencyConfig));
        bytes32 refId = keccak256("sgx-incomplete-level-raw");

        harness.setCompletenessState(refId, TcbId.SGX, 2, 2, 96, 96, 100, 98, 0, 0, 0, 0, 0, 0);
        assertFalse(harness.parseComplete(refId));

        harness.setCompletenessState(refId, TcbId.SGX, 2, 2, 96, 96, 100, 99, 0, 0, 0, 0, 0, 0);
        assertTrue(harness.parseComplete(refId));
    }

    function testV2_ParseCompleteRequiresTdxIdentityStreamToReachExpectedLength() public {
        FmspcTcbDaoV2CompletenessHarness harness =
            new FmspcTcbDaoV2CompletenessHarness(address(asyncDependencyConfig));
        bytes32 refId = keccak256("tdx-incomplete-identity-stream");

        harness.setCompletenessState(refId, TcbId.TDX, 2, 2, 96, 96, 100, 99, 1, 1, 128, 64, 200, 199);
        assertFalse(harness.parseComplete(refId));

        harness.setCompletenessState(refId, TcbId.TDX, 2, 2, 96, 96, 100, 99, 1, 1, 128, 128, 200, 199);
        assertTrue(harness.parseComplete(refId));
    }

    function testV2_ParseCompleteRequiresTdxIdentityRawCursorToReachArrayEnd() public {
        FmspcTcbDaoV2CompletenessHarness harness =
            new FmspcTcbDaoV2CompletenessHarness(address(asyncDependencyConfig));
        bytes32 refId = keccak256("tdx-incomplete-identity-raw");

        harness.setCompletenessState(refId, TcbId.TDX, 2, 2, 96, 96, 100, 99, 1, 1, 128, 128, 200, 198);
        assertFalse(harness.parseComplete(refId));

        harness.setCompletenessState(refId, TcbId.TDX, 2, 2, 96, 96, 100, 99, 1, 1, 128, 128, 200, 199);
        assertTrue(harness.parseComplete(refId));
    }

    function testV2_HelperRejectsMissingRequiredComponentSvnOrder() public {
        bytes memory payload =
            _singleSgxLevelPayload(_componentLayout(0, 1, 2, bytes("platform"), bytes("microcode")), 0, bytes(""));

        vm.expectRevert(FmspcTcbHelperV2.Async_Upsert_Invalid_Order.selector);
        fmspcTcbLibV2.buildAsyncTcbLevelsBatch(3, payload, 1, false);
    }

    function testV2_HelperRejectsUnsafeJsonStringValue() public {
        bytes memory payload = _singleSgxLevelPayload(
            _componentLayout(1, 2, 3, bytes('platform","svn":7,"type":"microcode'), bytes("microcode")), 0, bytes("")
        );

        vm.expectRevert(FmspcTcbHelperV2.TCBInfo_Invalid.selector);
        fmspcTcbLibV2.buildAsyncTcbLevelsBatch(3, payload, 1, false);
    }

    function testV2_HelperRejectsAdvisoryIdsWithoutAdvisoryFieldFlag() public {
        bytes memory payload = _singleSgxLevelPayload(
            _componentLayout(1, 2, 3, bytes("platform"), bytes("microcode")), 0, bytes("INTEL-SA-00000")
        );

        vm.expectRevert(FmspcTcbHelperV2.TCBInfo_Invalid.selector);
        fmspcTcbLibV2.buildAsyncTcbLevelsBatch(3, payload, 1, false);
    }

    function testV2_HelperRejectsVersion2ExplicitId() public {
        bytes memory order = new bytes(11);
        order[FIELD_ID] = bytes1(uint8(1));

        vm.expectRevert(FmspcTcbHelperV2.Async_Upsert_Invalid_Order.selector);
        fmspcTcbLibV2.requireBasicTopOrder(
            order, 1, 2, true, bytes20("2024-01-01T00:00:00Z"), bytes20("2025-01-01T00:00:00Z")
        );
    }

    function testV2_HelperRejectsNonContiguousTopLevelLayout() public {
        bytes memory order = new bytes(11);
        uint32[11] memory offsets;
        uint32[11] memory ends;

        order[FIELD_VERSION] = bytes1(uint8(1));
        order[FIELD_TCB_LEVELS] = bytes1(uint8(2));
        offsets[FIELD_VERSION] = 1;
        ends[FIELD_VERSION] = 13;
        offsets[FIELD_TCB_LEVELS] = 15;
        ends[FIELD_TCB_LEVELS] = 29;

        vm.expectRevert(FmspcTcbHelperV2.Async_Upsert_Invalid_Range.selector);
        fmspcTcbLibV2.requireTopLevelLayout(offsets, ends, order, 30);
    }

    function testV2_HelperRejectsLongTdxModuleIdentityId() public {
        bytes memory payload = abi.encodePacked(
            uint32(0), uint32(1), bytes5(hex"0102030405"), bytes1(uint8(32)), bytes32("tdx-module-identity-id-too-long")
        );

        vm.expectRevert(FmspcTcbHelperV2.TCBInfo_Invalid.selector);
        fmspcTcbLibV2.buildAsyncTdxModuleIdentitiesBatch(payload, 1, false);
    }

    function _singleSgxLevelPayload(bytes memory sgxLayout, uint8 flags, bytes memory advisory)
        private
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(
            bytes1(uint8(0)),
            sgxLayout,
            uint32(0),
            uint32(1),
            flags == LEVEL_FLAG_HAS_ADVISORY_FIELD ? bytes4(hex"01020304") : bytes4(hex"01020300"),
            bytes3(hex"010200"),
            bytes1(flags),
            bytes16(0),
            uint32(0),
            bytes20("2024-01-01T00:00:00Z"),
            bytes1(uint8(0)),
            _advisoryPayload(advisory)
        );
    }

    function _componentLayout(
        uint8 svnOrder,
        uint8 categoryOrder,
        uint8 typeOrder,
        bytes memory category,
        bytes memory componentType
    ) private pure returns (bytes memory out) {
        for (uint256 i = 0; i < 16; i++) {
            out = abi.encodePacked(
                out,
                bytes1(svnOrder),
                bytes1(categoryOrder),
                bytes1(typeOrder),
                uint16(category.length),
                category,
                uint16(componentType.length),
                componentType
            );
        }
    }

    function _advisoryPayload(bytes memory advisory) private pure returns (bytes memory) {
        if (advisory.length == 0) {
            return abi.encodePacked(uint32(0));
        }
        return abi.encodePacked(uint32(1), uint16(advisory.length), advisory);
    }
}
