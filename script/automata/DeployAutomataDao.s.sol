// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../utils/P256Configuration.sol";
import "../utils/Salt.sol";
import "../utils/DeploymentConfig.sol";

import {AutomataDaoStorage} from "../../src/automata_pccs/shared/AutomataDaoStorage.sol";
import {AutomataFmspcTcbDao} from "../../src/automata_pccs/AutomataFmspcTcbDao.sol";
import {AutomataEnclaveIdentityDao} from "../../src/automata_pccs/AutomataEnclaveIdentityDao.sol";
import {AutomataPcsDao} from "../../src/automata_pccs/AutomataPcsDao.sol";
import {AutomataPckDao} from "../../src/automata_pccs/AutomataPckDao.sol";

contract DeployAutomataDao is DeploymentConfig, P256Configuration {
    address owner = vm.envAddress("OWNER");

    address x509Crl = readContractAddress("X509CRLHelper", true);
    address x509 = readContractAddress("PCKHelper", true);
    address enclaveIdentityHelper = readContractAddress("EnclaveIdentityHelper", true);
    address fmspcTcbHelper = readContractAddress("FmspcTcbHelper", true);

    function run() public override {
        deployAll(true, false);
    }

    modifier broadcastOwner() {
        vm.startBroadcast(owner);
        _;
        vm.stopBroadcast();
    }

    function deployAll(bool shouldDeployStorage, bool legacy) public broadcastOwner {
        AutomataDaoStorage pccsStorage;
        if (shouldDeployStorage) {
            pccsStorage = new AutomataDaoStorage{salt: PCCS_STORAGE_SALT}(owner);
            console.log("[LOG] AutomataDaoStorage deployed at ", address(pccsStorage));
            writeToJson("AutomataDaoStorage", address(pccsStorage));
        } else {
            address pccsStorageAddr = readContractAddress("AutomataDaoStorage", true);
            pccsStorage = AutomataDaoStorage(pccsStorageAddr);
        }

        // Deploy PcsDao
        AutomataPcsDao pcsDao =
            new AutomataPcsDao{salt: PCS_DAO_SALT}(address(pccsStorage), simulateVerify(), x509, x509Crl);
        console.log("[LOG] AutomataPcsDao deployed at: ", address(pcsDao));
        writeToJson("AutomataPcsDao", address(pcsDao));

        // Deploy PckDao
        AutomataPckDao pckDao = new AutomataPckDao{salt: PCK_DAO_SALT}(
            address(pccsStorage), simulateVerify(), address(pcsDao), x509, x509Crl
        );
        console.log("[LOG] AutomataPckDao deployed at: ", address(pckDao));
        writeToJson("AutomataPckDao", address(pckDao));

        if (legacy) {
            // Deploy EnclaveIdDao
            AutomataEnclaveIdentityDao enclaveIdDao = new AutomataEnclaveIdentityDao{salt: ENCLAVE_ID_DAO_SALT}(
                address(pccsStorage), simulateVerify(), address(pcsDao), enclaveIdentityHelper, x509, x509Crl
            );
            console.log("[LOG] AutomataEnclaveIdDao deployed at: ", address(enclaveIdDao));
            writeToJson("AutomataEnclaveIdentityDao", address(enclaveIdDao));

            // Deploy FmspcDao
            AutomataFmspcTcbDao fmspcTcbDao = new AutomataFmspcTcbDao{salt: FMSPC_TCB_DAO_SALT}(
                address(pccsStorage), simulateVerify(), address(pcsDao), fmspcTcbHelper, x509, x509Crl
            );
            console.log("[LOG] AutomataFmspcTcbDao deployed at: ", address(fmspcTcbDao));
            writeToJson("AutomataFmspcTcbDao", address(fmspcTcbDao));

            pccsStorage.grantDao(address(enclaveIdDao));
            pccsStorage.grantDao(address(fmspcTcbDao));
        }

        // grants the DAOs permission to write to storage
        pccsStorage.grantDao(address(pcsDao));
        pccsStorage.grantDao(address(pckDao));
    }

    function deployStorage() public broadcastOwner {
        AutomataDaoStorage pccsStorage = new AutomataDaoStorage{salt: PCCS_STORAGE_SALT}(owner);
        console.log("[LOG] AutomataDaoStorage deployed at ", address(pccsStorage));
        writeToJson("AutomataDaoStorage", address(pccsStorage));
    }

    function deployPcs() public broadcastOwner {
        address pccsStorageAddr = readContractAddress("AutomataDaoStorage", true);
        AutomataPcsDao pcsDao = new AutomataPcsDao{salt: PCS_DAO_SALT}(pccsStorageAddr, simulateVerify(), x509, x509Crl);
        console.log("[LOG] AutomataPcsDao deployed at: ", address(pcsDao));
        writeToJson("AutomataPcsDao", address(pcsDao));

        AutomataDaoStorage(pccsStorageAddr).grantDao(address(pcsDao));
    }

    function deployPck() public broadcastOwner {
        address pccsStorageAddr = readContractAddress("AutomataDaoStorage", true);
        address pcsDaoAddr = readContractAddress("AutomataPcsDao", true);
        AutomataPckDao pckDao =
            new AutomataPckDao{salt: PCK_DAO_SALT}(pccsStorageAddr, simulateVerify(), pcsDaoAddr, x509, x509Crl);
        console.log("[LOG] AutomataPckDao deployed at: ", address(pckDao));
        writeToJson("AutomataPckDao", address(pckDao));

        AutomataDaoStorage(pccsStorageAddr).grantDao(address(pckDao));
    }

    function deployEnclaveIdDao() public broadcastOwner {
        address pccsStorageAddr = readContractAddress("AutomataDaoStorage", true);
        address pcsDaoAddr = readContractAddress("AutomataPcsDao", true);
        AutomataEnclaveIdentityDao enclaveIdDao = new AutomataEnclaveIdentityDao{salt: ENCLAVE_ID_DAO_SALT}(
            pccsStorageAddr, simulateVerify(), pcsDaoAddr, enclaveIdentityHelper, x509, x509Crl
        );
        console.log("[LOG] AutomataEnclaveIdDao deployed at: ", address(enclaveIdDao));
        writeToJson("AutomataEnclaveIdentityDao", address(enclaveIdDao));

        AutomataDaoStorage(pccsStorageAddr).grantDao(address(enclaveIdDao));
    }

    function deployFmspcTcbDao() public broadcastOwner {
        address pccsStorageAddr = readContractAddress("AutomataDaoStorage", true);
        address pcsDaoAddr = readContractAddress("AutomataPcsDao", true);
        AutomataFmspcTcbDao fmspcTcbDao = new AutomataFmspcTcbDao{salt: FMSPC_TCB_DAO_SALT}(
            pccsStorageAddr, simulateVerify(), pcsDaoAddr, fmspcTcbHelper, x509, x509Crl
        );
        console.log("[LOG] AutomataFmspcTcbDao deployed at: ", address(fmspcTcbDao));
        writeToJson("AutomataFmspcTcbDao", address(fmspcTcbDao));

        AutomataDaoStorage(pccsStorageAddr).grantDao(address(fmspcTcbDao));
    }
}
