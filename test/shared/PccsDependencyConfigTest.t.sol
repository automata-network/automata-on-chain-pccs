// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {TestSetupBase} from "../TestSetupBase.t.sol";
import {
    IPccsDependencyConfig,
    PccsDependencyConfig
} from "../../src/automata_pccs/shared/PccsDependencyConfig.sol";
import {AutomataDaoStorageV2} from "../../src/automata_pccs/shared/AutomataDaoStorageV2.sol";
import {AutomataPcsDaoV2} from "../../src/automata_pccs/AutomataPcsDaoV2.sol";
import {AutomataPckDaoV2} from "../../src/automata_pccs/AutomataPckDaoV2.sol";
import {AutomataTcbEvalDao} from "../../src/automata_pccs/AutomataTcbEvalDao.sol";
import {
    AutomataEnclaveIdentityDaoVersioned
} from "../../src/automata_pccs/versioned/AutomataEnclaveIdentityDaoVersioned.sol";
import {
    AutomataFmspcTcbDaoVersionedV2
} from "../../src/automata_pccs/versioned/AutomataFmspcTcbDaoVersionedV2.sol";
import {X509CRLHelperV2} from "../../src/helpers/X509CRLHelperV2.sol";
import {TcbEvalHelper} from "../../src/helpers/TcbEvalHelper.sol";
import {FmspcTcbHelperV2} from "../../src/helpers/FmspcTcbHelperV2.sol";

contract FixedCrlPcs {
    address public immutable crlLib;

    constructor(address helper) {
        crlLib = helper;
    }
}

contract PccsDependencyConfigTest is TestSetupBase {
    address internal stranger = address(0xBEEF);

    PccsDependencyConfig internal config;
    X509CRLHelperV2 internal crlV2A;
    X509CRLHelperV2 internal crlV2B;
    AutomataPcsDaoV2 internal pcsV2A;
    AutomataPcsDaoV2 internal pcsV2B;
    AutomataPckDaoV2 internal pckV2;
    AutomataTcbEvalDao internal tcbEvalV2;
    AutomataEnclaveIdentityDaoVersioned internal enclaveIdentityV2;
    AutomataFmspcTcbDaoVersionedV2 internal fmspcV2;

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        crlV2A = new X509CRLHelperV2(admin);
        crlV2B = new X509CRLHelperV2(admin);
        config = new PccsDependencyConfig(admin);
        pcsV2A = new AutomataPcsDaoV2(address(pccsStorage), P256_VERIFIER, address(x509Lib), address(config));
        config.initialize(address(pcsV2A), address(crlV2A));
        pcsV2B = new AutomataPcsDaoV2(address(pccsStorage), P256_VERIFIER, address(x509Lib), address(config));

        pckV2 = new AutomataPckDaoV2(address(pccsStorage), P256_VERIFIER, address(config), address(x509Lib));
        tcbEvalV2 = new AutomataTcbEvalDao(
            address(pccsStorage),
            P256_VERIFIER,
            address(config),
            address(new TcbEvalHelper()),
            address(x509Lib),
            admin
        );
        enclaveIdentityV2 = new AutomataEnclaveIdentityDaoVersioned(
            address(pccsStorage),
            P256_VERIFIER,
            address(config),
            address(enclaveIdentityLib),
            address(x509Lib),
            admin,
            20
        );
        fmspcV2 = new AutomataFmspcTcbDaoVersionedV2(
            address(new AutomataDaoStorageV2(admin, address(pccsStorage))),
            P256_VERIFIER,
            address(config),
            address(fmspcTcbLib),
            address(new FmspcTcbHelperV2()),
            address(x509Lib),
            admin,
            20
        );
        vm.stopPrank();
    }

    function testInitializesOnceAndExposesExplicitState() public {
        assertEq(uint8(config.dependencyConfigState()), uint8(PccsDependencyConfig.ConfigState.Active));
        assertEq(config.pcsDao(), address(pcsV2A));
        assertEq(config.crlHelper(), address(crlV2A));
        assertEq(config.CONFIG_DELAY(), 3 hours);

        vm.prank(admin);
        vm.expectRevert(PccsDependencyConfig.Already_Initialized.selector);
        config.initialize(address(pcsV2A), address(crlV2A));
    }

    function testOnlyOwnerCanInitializeScheduleAndCancel() public {
        PccsDependencyConfig uninitialized = new PccsDependencyConfig(admin);

        vm.prank(stranger);
        vm.expectRevert();
        uninitialized.initialize(address(pcsV2A), address(crlV2A));

        vm.prank(stranger);
        vm.expectRevert();
        config.scheduleDependencyConfig(address(pcsV2B), address(crlV2B));

        vm.prank(admin);
        config.scheduleDependencyConfig(address(pcsV2B), address(crlV2B));

        vm.prank(stranger);
        vm.expectRevert();
        config.cancelDependencyConfig();
    }

    function testRejectsMissingCodeAndMismatchedPcsHelperBinding() public {
        PccsDependencyConfig uninitialized = new PccsDependencyConfig(admin);

        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(PccsDependencyConfig.Invalid_Config_Address.selector, address(0)));
        uninitialized.initialize(address(0), address(crlV2A));

        vm.expectRevert(abi.encodeWithSelector(PccsDependencyConfig.Invalid_Config_Address.selector, stranger));
        uninitialized.initialize(stranger, address(crlV2A));

        FixedCrlPcs fixedPcs = new FixedCrlPcs(address(crlV2A));
        vm.expectRevert(
            abi.encodeWithSelector(
                PccsDependencyConfig.Invalid_Pcs_Crl_Binding.selector,
                address(fixedPcs),
                address(crlV2B),
                address(crlV2A)
            )
        );
        uninitialized.initialize(address(fixedPcs), address(crlV2B));
        vm.stopPrank();
    }

    function testScheduleDoesNotChangeConsumersAndCannotBeReplaced() public {
        uint64 expectedExecutableAt = uint64(block.timestamp + 3 hours);

        vm.prank(admin);
        config.scheduleDependencyConfig(address(pcsV2B), address(crlV2B));

        assertEq(uint8(config.dependencyConfigState()), uint8(PccsDependencyConfig.ConfigState.Pending));
        assertEq(config.pendingPcsDao(), address(pcsV2B));
        assertEq(config.pendingCrlHelper(), address(crlV2B));
        assertEq(config.pendingExecutableAt(), expectedExecutableAt);
        _assertAllConsumers(address(pcsV2A), address(crlV2A));

        vm.prank(admin);
        vm.expectRevert(PccsDependencyConfig.Pending_Config_Exists.selector);
        config.scheduleDependencyConfig(address(pcsV2A), address(crlV2A));
    }

    function testExecuteIsPermissionlessOnlyAfterExactlyThreeHoursAndSwitchesAtomically() public {
        vm.prank(admin);
        config.scheduleDependencyConfig(address(pcsV2B), address(crlV2B));
        uint64 executableAt = config.pendingExecutableAt();

        vm.warp(executableAt - 1);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(PccsDependencyConfig.Config_Not_Ready.selector, executableAt));
        config.executeDependencyConfig();
        _assertAllConsumers(address(pcsV2A), address(crlV2A));

        vm.warp(executableAt);
        assertEq(uint8(config.dependencyConfigState()), uint8(PccsDependencyConfig.ConfigState.Ready));
        vm.prank(stranger);
        config.executeDependencyConfig();

        assertEq(uint8(config.dependencyConfigState()), uint8(PccsDependencyConfig.ConfigState.Active));
        assertEq(config.pendingExecutableAt(), 0);
        _assertAllConsumers(address(pcsV2B), address(crlV2B));

        vm.expectRevert(PccsDependencyConfig.No_Pending_Config.selector);
        config.executeDependencyConfig();
    }

    function testCancelLeavesCurrentPairActiveAndClearsPendingState() public {
        vm.prank(admin);
        config.scheduleDependencyConfig(address(pcsV2B), address(crlV2B));

        vm.prank(admin);
        config.cancelDependencyConfig();

        assertEq(uint8(config.dependencyConfigState()), uint8(PccsDependencyConfig.ConfigState.Active));
        assertEq(config.pendingPcsDao(), address(0));
        assertEq(config.pendingCrlHelper(), address(0));
        assertEq(config.pendingExecutableAt(), 0);
        _assertAllConsumers(address(pcsV2A), address(crlV2A));

        vm.warp(block.timestamp + 3 hours);
        vm.expectRevert(PccsDependencyConfig.No_Pending_Config.selector);
        config.executeDependencyConfig();
    }

    function testCannotScheduleBeforeInitialization() public {
        PccsDependencyConfig uninitialized = new PccsDependencyConfig(admin);

        vm.prank(admin);
        vm.expectRevert(PccsDependencyConfig.Not_Initialized.selector);
        uninitialized.scheduleDependencyConfig(address(pcsV2B), address(crlV2B));
    }

    function _assertAllConsumers(address expectedPcs, address expectedCrl) private {
        assertEq(address(pcsV2A.crlLib()), expectedCrl);
        assertEq(address(pcsV2B.crlLib()), expectedCrl);
        assertEq(address(pckV2.Pcs()), expectedPcs);
        assertEq(address(pckV2.crlLib()), expectedCrl);
        assertEq(address(tcbEvalV2.Pcs()), expectedPcs);
        assertEq(tcbEvalV2.crlLibAddr(), expectedCrl);
        assertEq(address(enclaveIdentityV2.Pcs()), expectedPcs);
        assertEq(enclaveIdentityV2.crlLibAddr(), expectedCrl);
        assertEq(address(fmspcV2.Pcs()), expectedPcs);
        assertEq(fmspcV2.crlLibAddr(), expectedCrl);
    }
}
