// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../utils/P256Configuration.sol";
import "../utils/Salt.sol";
import "../utils/DeploymentConfig.sol";

import {CA} from "../../src/Common.sol";
import {X509CRLHelperV2} from "../../src/helpers/X509CRLHelperV2.sol";
import {AutomataDaoStorage} from "../../src/automata_pccs/shared/AutomataDaoStorage.sol";
import {PccsDependencyConfig} from "../../src/automata_pccs/shared/PccsDependencyConfig.sol";
import {AutomataPcsDaoV2} from "../../src/automata_pccs/AutomataPcsDaoV2.sol";
import {AutomataPckDaoV2} from "../../src/automata_pccs/AutomataPckDaoV2.sol";

/**
 * @notice Deploys the CRL V2 helper and DAOs against the existing shared
 * AutomataDaoStorage. Existing collateral and legacy DAOs are left untouched.
 */
contract DeployCrlV2 is DeploymentConfig, P256Configuration {
    address internal owner = vm.envAddress("OWNER");

    error Runtime_Code_Hash_Mismatch(string component, bytes32 expected, bytes32 actual);

    function run() public override {
        address storageAddr = readContractAddress("AutomataDaoStorage", true);
        address pckHelperAddr = readContractAddress("PCKHelper", true);

        vm.startBroadcast(owner);

        X509CRLHelperV2 crlHelper = new X509CRLHelperV2{salt: X509_CRL_HELPER_V2_SALT}(owner);
        PccsDependencyConfig dependencyConfig =
            new PccsDependencyConfig{salt: PCCS_DEPENDENCY_CONFIG_SALT}(owner);
        AutomataPcsDaoV2 pcsDao = new AutomataPcsDaoV2{salt: PCS_DAO_V2_SALT}(
            storageAddr, simulateVerify(), pckHelperAddr, address(dependencyConfig)
        );
        dependencyConfig.initialize(address(pcsDao), address(crlHelper));
        AutomataPckDaoV2 pckDao = new AutomataPckDaoV2{salt: PCK_DAO_V2_SALT}(
            storageAddr, simulateVerify(), address(dependencyConfig), pckHelperAddr
        );

        AutomataDaoStorage storageContract = AutomataDaoStorage(storageAddr);
        storageContract.grantDao(address(pcsDao));
        storageContract.grantDao(address(pckDao));
        crlHelper.setAuthorizedIndexer(address(pcsDao), true);

        vm.stopBroadcast();

        console.log("[LOG] X509CRLHelperV2 deployed at: ", address(crlHelper));
        console.log("[LOG] PccsDependencyConfig deployed at: ", address(dependencyConfig));
        console.log("[LOG] AutomataPcsDaoV2 deployed at: ", address(pcsDao));
        console.log("[LOG] AutomataPckDaoV2 deployed at: ", address(pckDao));
        writeToJson("X509CRLHelperV2", address(crlHelper));
        writeToJson("PccsDependencyConfig", address(dependencyConfig));
        writeToJson("AutomataPcsDaoV2", address(pcsDao));
        writeToJson("AutomataPckDaoV2", address(pckDao));
    }

    /// @notice Atomically validates and indexes a CRL already stored by V1.
    /// The expected hash prevents indexing stale collateral if it changes
    /// between the deployment read and this transaction.
    function indexStoredCrl(CA ca, bytes32 expectedDerHash) public {
        AutomataPcsDaoV2 pcsDao = AutomataPcsDaoV2(readContractAddress("AutomataPcsDaoV2", true));
        vm.broadcast(owner);
        pcsDao.indexStoredCrl(ca, expectedDerHash);
    }

    /// @notice Compares every recorded V2 runtime against a locally-created
    /// reference with the expected constructor arguments and current build.
    /// The reference deployments are simulation-only and are never broadcast.
    function validateExistingRuntime() public {
        address storageAddr = readContractAddress("AutomataDaoStorage", true);
        address pckHelperAddr = readContractAddress("PCKHelper", true);
        address crlHelperAddr = readContractAddress("X509CRLHelperV2", true);
        address dependencyConfigAddr = readContractAddress("PccsDependencyConfig", true);
        address pcsDaoAddr = readContractAddress("AutomataPcsDaoV2", true);
        address pckDaoAddr = readContractAddress("AutomataPckDaoV2", true);
        address p256 = simulateVerify();

        X509CRLHelperV2 expectedCrlHelper = new X509CRLHelperV2(owner);
        PccsDependencyConfig expectedDependencyConfig = new PccsDependencyConfig(owner);
        AutomataPcsDaoV2 expectedPcsDao =
            new AutomataPcsDaoV2(storageAddr, p256, pckHelperAddr, dependencyConfigAddr);
        AutomataPckDaoV2 expectedPckDao =
            new AutomataPckDaoV2(storageAddr, p256, dependencyConfigAddr, pckHelperAddr);

        _requireRuntimeCode("X509CRLHelperV2", crlHelperAddr, address(expectedCrlHelper));
        _requireRuntimeCode("PccsDependencyConfig", dependencyConfigAddr, address(expectedDependencyConfig));
        _requireRuntimeCode("AutomataPcsDaoV2", pcsDaoAddr, address(expectedPcsDao));
        _requireRuntimeCode("AutomataPckDaoV2", pckDaoAddr, address(expectedPckDao));
    }

    function _requireRuntimeCode(string memory component, address actual, address expected) private view {
        bytes32 actualHash = actual.codehash;
        bytes32 expectedHash = expected.codehash;
        if (actualHash != expectedHash) {
            revert Runtime_Code_Hash_Mismatch(component, expectedHash, actualHash);
        }
    }
}
