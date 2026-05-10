// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../utils/P256Configuration.sol";
import "../../utils/Salt.sol";
import "../../utils/DeploymentConfig.sol";
import "../../utils/Multichain.sol";

import {AutomataDaoStorage} from "../../../src/automata_pccs/shared/AutomataDaoStorage.sol";
import {AutomataDaoStorageV2} from "../../../src/automata_pccs/shared/AutomataDaoStorageV2.sol";
import {AutomataTcbEvalDao} from "../../../src/automata_pccs/AutomataTcbEvalDao.sol";
import {AutomataFmspcTcbDaoVersioned} from "../../../src/automata_pccs/versioned/AutomataFmspcTcbDaoVersioned.sol";
import {AutomataFmspcTcbDaoVersionedV2} from "../../../src/automata_pccs/versioned/AutomataFmspcTcbDaoVersionedV2.sol";
import {AutomataEnclaveIdentityDaoVersioned} from "../../../src/automata_pccs/versioned/AutomataEnclaveIdentityDaoVersioned.sol";

contract DeployAutomataVersioned is DeploymentConfig, P256Configuration, Multichain {
    address owner = vm.envAddress("OWNER");

    address x509Crl = readContractAddress("X509CRLHelper", true);
    address x509 = readContractAddress("PCKHelper", true);
    address enclaveIdentityHelper = readContractAddress("EnclaveIdentityHelper", true);
    address fmspcTcbHelper = readContractAddress("FmspcTcbHelper", true);

    function _useCreate2Deploy() internal returns (bool) {
        return vm.envOr("USE_CREATE2", true);
    }

    function _skipPostDeployGrants() internal returns (bool) {
        return vm.envOr("SKIP_POST_DEPLOY_GRANTS", false);
    }

    function _resolveFmspcTcbHelperForV2() internal returns (address helper) {
        helper = readContractAddress("FmspcTcbHelperV2", false);
        if (helper == address(0)) {
            helper = fmspcTcbHelper;
        }
    }

    function deployTcbEvalDao() public multichain {
        address pccsStorageAddr = readContractAddress("AutomataDaoStorage", true);
        address pcsDaoAddr = readContractAddress("AutomataPcsDao", true);
        address tcbEvalHelper = readContractAddress("TcbEvalHelper", true);

        vm.startBroadcast(owner);

        AutomataTcbEvalDao tcbEvalDao = new AutomataTcbEvalDao{salt: TCB_EVAL_DAO_SALT}(
            pccsStorageAddr, simulateVerify(), pcsDaoAddr, tcbEvalHelper, x509, x509Crl, owner
        );

        AutomataDaoStorage pccsStorage = AutomataDaoStorage(pccsStorageAddr);
        pccsStorage.grantDao(address(tcbEvalDao));

        vm.stopBroadcast();

        console.log("[LOG] AutomataTcbEvalDao deployed at: ", address(tcbEvalDao));
        writeToJson("AutomataTcbEvalDao", address(tcbEvalDao));
    }

    function deployEnclaveIdDaoVersioned(uint32 tcbEvaluationDataNumber) public multichain {
        address pccsStorageAddr = readContractAddress("AutomataDaoStorage", true);
        address pcsDaoAddr = readContractAddress("AutomataPcsDao", true);

        vm.startBroadcast(owner);

        AutomataEnclaveIdentityDaoVersioned enclaveIdDao = new AutomataEnclaveIdentityDaoVersioned{salt: ENCLAVE_ID_DAO_SALT}(
            pccsStorageAddr, simulateVerify(), pcsDaoAddr, enclaveIdentityHelper, x509, x509Crl, owner, tcbEvaluationDataNumber
        );

        AutomataDaoStorage pccsStorage = AutomataDaoStorage(pccsStorageAddr);
        pccsStorage.grantDao(address(enclaveIdDao));

        console.log("[LOG] AutomataEnclaveIdDaoVersioned deployed at: ", address(enclaveIdDao));
        writeToJsonVersioned("AutomataEnclaveIdentityDaoVersioned", tcbEvaluationDataNumber, address(enclaveIdDao));

        vm.stopBroadcast();
    }

    function deployFmspcTcbDaoVersioned(uint32 tcbEvaluationDataNumber) public multichain {
        address pccsStorageAddr = readContractAddress("AutomataDaoStorage", true);
        address pcsDaoAddr = readContractAddress("AutomataPcsDao", true);

        vm.startBroadcast(owner);

        AutomataFmspcTcbDaoVersioned fmspcTcbDao = new AutomataFmspcTcbDaoVersioned{salt: FMSPC_TCB_DAO_SALT}(
            pccsStorageAddr, simulateVerify(), pcsDaoAddr, fmspcTcbHelper, x509, x509Crl, owner, tcbEvaluationDataNumber
        );

        AutomataDaoStorage pccsStorage = AutomataDaoStorage(pccsStorageAddr);
        pccsStorage.grantDao(address(fmspcTcbDao));

        console.log("[LOG] AutomataFmspcTcbDaoVersioned deployed at: ", address(fmspcTcbDao));
        writeToJsonVersioned("AutomataFmspcTcbDaoVersioned", tcbEvaluationDataNumber, address(fmspcTcbDao));

        vm.stopBroadcast();
    }

    function deployStorageV2() public multichain {
        address fallbackStorageAddr = readContractAddress("AutomataDaoStorage", true);

        vm.startBroadcast(owner);

        AutomataDaoStorageV2 storageV2 = _useCreate2Deploy()
            ? new AutomataDaoStorageV2{salt: PCCS_STORAGE_V2_SALT}(owner, fallbackStorageAddr)
            : new AutomataDaoStorageV2(owner, fallbackStorageAddr);

        AutomataDaoStorage(fallbackStorageAddr).grantDao(address(storageV2));

        console.log("[LOG] AutomataDaoStorageV2 deployed at: ", address(storageV2));
        writeToJson("AutomataDaoStorageV2", address(storageV2));

        vm.stopBroadcast();
    }

    function deployFmspcTcbDaoVersionedV2(uint32 tcbEvaluationDataNumber) public multichain {
        address pccsStorageV2Addr = readContractAddress("AutomataDaoStorageV2", true);
        address pcsDaoAddr = readContractAddress("AutomataPcsDao", true);

        vm.startBroadcast(owner);

        AutomataFmspcTcbDaoVersionedV2 fmspcTcbDao = _useCreate2Deploy()
            ? new AutomataFmspcTcbDaoVersionedV2{salt: FMSPC_TCB_DAO_V2_SALT}(
                pccsStorageV2Addr,
                simulateVerify(),
                pcsDaoAddr,
                _resolveFmspcTcbHelperForV2(),
                x509,
                x509Crl,
                owner,
                tcbEvaluationDataNumber
            )
            : new AutomataFmspcTcbDaoVersionedV2(
                pccsStorageV2Addr,
                simulateVerify(),
                pcsDaoAddr,
                _resolveFmspcTcbHelperForV2(),
                x509,
                x509Crl,
                owner,
                tcbEvaluationDataNumber
            );

        if (!_skipPostDeployGrants()) {
            AutomataDaoStorageV2(pccsStorageV2Addr).grantDao(address(fmspcTcbDao));
        }

        console.log("[LOG] AutomataFmspcTcbDaoVersionedV2 deployed at: ", address(fmspcTcbDao));
        writeToJsonVersioned("AutomataFmspcTcbDaoVersionedV2", tcbEvaluationDataNumber, address(fmspcTcbDao));

        vm.stopBroadcast();
    }
}
