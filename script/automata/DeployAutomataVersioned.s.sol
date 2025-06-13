// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../utils/P256Configuration.sol";
import "../utils/Salt.sol";
import "../utils/DeploymentConfig.sol";

import {AutomataDaoStorage} from "../../src/automata_pccs/shared/AutomataDaoStorage.sol";
import {AutomataTcbEvalDao} from "../../src/automata_pccs/AutomataTcbEvalDao.sol";
import {AutomataFmspcTcbDaoVersioned} from "../../src/automata_pccs/versioned/AutomataFmspcTcbDaoVersioned.sol";
import {AutomataEnclaveIdentityDaoVersioned} from "../../src/automata_pccs/versioned/AutomataEnclaveIdentityDaoVersioned.sol";

contract DeployAutomataVersioned is DeploymentConfig, P256Configuration {
    address owner = vm.envAddress("OWNER");

    address x509Crl = readContractAddress("X509CRLHelper");
    address x509 = readContractAddress("PCKHelper");
    address enclaveIdentityHelper = readContractAddress("EnclaveIdentityHelper");
    address fmspcTcbHelper = readContractAddress("FmspcTcbHelper");

    modifier broadcastOwner() {
        vm.startBroadcast(owner);
        _;
        vm.stopBroadcast();
    }

    function deployTcbEvalDao() public broadcastOwner {
        address pccsStorageAddr = readContractAddress("AutomataDaoStorage");
        address pcsDaoAddr = readContractAddress("AutomataPcsDao");
        address tcbEvalHelper = readContractAddress("TcbEvalHelper");
        AutomataTcbEvalDao tcbEvalDao = new AutomataTcbEvalDao{salt: TCB_EVAL_DAO_SALT}(
            pccsStorageAddr, simulateVerify(), pcsDaoAddr, tcbEvalHelper, x509, x509Crl, owner
        );
        console.log("[LOG] AutomataTcbEvalDao deployed at: ", address(tcbEvalDao));
        writeToJson("AutomataTcbEvalDao", address(tcbEvalDao));
    }

    function deployEnclaveIdDaoVersioned(uint32 tcbEvaluationDataNumber) public broadcastOwner {
        address pccsStorageAddr = readContractAddress("AutomataDaoStorage");
        address pcsDaoAddr = readContractAddress("AutomataPcsDao");
        AutomataEnclaveIdentityDaoVersioned enclaveIdDao = new AutomataEnclaveIdentityDaoVersioned{salt: ENCLAVE_ID_DAO_SALT}(
            pccsStorageAddr, simulateVerify(), pcsDaoAddr, enclaveIdentityHelper, x509, x509Crl, owner, tcbEvaluationDataNumber
        );
        console.log("[LOG] AutomataEnclaveIdDaoVersioned deployed at: ", address(enclaveIdDao));
        writeToJsonVersioned("AutomataEnclaveIdentityDaoVersioned", tcbEvaluationDataNumber, address(enclaveIdDao));
    }

    function deployFmspcTcbDaoVersioned(uint32 tcbEvaluationDataNumber) public broadcastOwner {
        address pccsStorageAddr = readContractAddress("AutomataDaoStorage");
        address pcsDaoAddr = readContractAddress("AutomataPcsDao");
        AutomataFmspcTcbDaoVersioned fmspcTcbDao = new AutomataFmspcTcbDaoVersioned{salt: FMSPC_TCB_DAO_SALT}(
            pccsStorageAddr, simulateVerify(), pcsDaoAddr, fmspcTcbHelper, x509, x509Crl, owner, tcbEvaluationDataNumber
        );
        console.log("[LOG] AutomataFmspcTcbDaoVersioned deployed at: ", address(fmspcTcbDao));
        writeToJsonVersioned("AutomataFmspcTcbDaoVersioned", tcbEvaluationDataNumber, address(fmspcTcbDao));
    }
}