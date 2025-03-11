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

    address x509Crl = readContractAddress("X509CRLHelper");
    address x509 = readContractAddress("PCKHelper");
    address enclaveIdentityHelper = readContractAddress("EnclaveIdentityHelper");
    address fmspcTcbHelper = readContractAddress("FmspcTcbHelper");

    modifier broadcastOwner() {
        vm.startBroadcast(owner);
        _;
        vm.stopBroadcast();
    }

    function deployAll(bool shouldDeployStorage) public broadcastOwner {
        AutomataDaoStorage pccsStorage;
        if (shouldDeployStorage) {
            pccsStorage = new AutomataDaoStorage{salt: PCCS_STORAGE_SALT}(owner);
            console.log("[LOG] AutomataDaoStorage deployed at ", address(pccsStorage));
            writeToJson("AutomataDaoStorage", address(pccsStorage));
        } else {
            address pccsStorageAddr = readContractAddress("AutomataDaoStorage");
            pccsStorage = AutomataDaoStorage(pccsStorageAddr);
        }

        // Deploy PcsDao
        AutomataPcsDao pcsDao = new AutomataPcsDao{salt: PCS_DAO_SALT}(address(pccsStorage), simulateVerify(), x509, x509Crl);
        console.log("[LOG] AutomataPcsDao deployed at: ", address(pcsDao));
        writeToJson("AutomataPcsDao", address(pcsDao));

        // Deploy PckDao
        AutomataPckDao pckDao =
            new AutomataPckDao{salt: PCK_DAO_SALT}(address(pccsStorage), simulateVerify(), address(pcsDao), x509, x509Crl);
        console.log("[LOG] AutomataPckDao deployed at: ", address(pckDao));
        writeToJson("AutomataPckDao", address(pckDao));

        // Deploy EnclaveIdDao
        AutomataEnclaveIdentityDao enclaveIdDao = new AutomataEnclaveIdentityDao{salt: ENCLAVE_ID_DAO_SALT}(
            address(pccsStorage), simulateVerify(), address(pcsDao), enclaveIdentityHelper, x509, x509Crl
        );
        console.log("[LOG] AutomataEnclaveIdDao deployed at: ", address(enclaveIdDao));
        writeToJson("AutomataEnclaveIdentityDao", address(enclaveIdDao));

        // Deploy FmspcDao
        AutomataFmspcTcbDao fmspcTcbDao =
            new AutomataFmspcTcbDao{salt: FMSPC_TCB_DAO_SALT}(address(pccsStorage), simulateVerify(), address(pcsDao), fmspcTcbHelper, x509, x509Crl);
        console.log("[LOG] AutomataFmspcTcbDao deployed at: ", address(fmspcTcbDao));
        writeToJson("AutomataFmspcTcbDao", address(fmspcTcbDao));

        // grants the DAOs permission to write to storage
        pccsStorage.grantDao(address(pcsDao));
        pccsStorage.grantDao(address(pckDao));
        pccsStorage.grantDao(address(enclaveIdDao));
        pccsStorage.grantDao(address(fmspcTcbDao));
    }

    function deployStorage() public broadcastOwner {
        AutomataDaoStorage pccsStorage = new AutomataDaoStorage{salt: PCCS_STORAGE_SALT}(owner);
        console.log("[LOG] AutomataDaoStorage deployed at ", address(pccsStorage));
        writeToJson("AutomataDaoStorage", address(pccsStorage));
    }

    function deployPcs() public broadcastOwner {
        address pccsStorageAddr = readContractAddress("PCCS_STORAGE");
        AutomataPcsDao pcsDao = new AutomataPcsDao{salt: PCS_DAO_SALT}(pccsStorageAddr, simulateVerify(), x509, x509Crl);
        console.log("[LOG] AutomataPcsDao deployed at: ", address(pcsDao));
        writeToJson("AutomataPcsDao", address(pcsDao));
    }

    function deployPck() public broadcastOwner {
        address pccsStorageAddr = readContractAddress("PCCS_STORAGE");
        address pcsDaoAddr = readContractAddress("PCS_DAO");
        AutomataPckDao pckDao = new AutomataPckDao{salt: PCK_DAO_SALT}(pccsStorageAddr, simulateVerify(), pcsDaoAddr, x509, x509Crl);
        console.log("[LOG] AutomataPckDao deployed at: ", address(pckDao));
        writeToJson("AutomataPckDao", address(pckDao));
    }

    function deployEnclaveIdDao() public broadcastOwner {
        address pccsStorageAddr = readContractAddress("PCCS_STORAGE");
        address pcsDaoAddr = readContractAddress("PCS_DAO");
        AutomataEnclaveIdentityDao enclaveIdDao =
            new AutomataEnclaveIdentityDao{salt: ENCLAVE_ID_DAO_SALT}(pccsStorageAddr, simulateVerify(), pcsDaoAddr, enclaveIdentityHelper, x509, x509Crl);
        console.log("[LOG] AutomataEnclaveIdDao deployed at: ", address(enclaveIdDao));
        writeToJson("AutomataEnclaveIdentityDao", address(enclaveIdDao));
    }

    function deployFmspcTcbDao() public broadcastOwner {
        address pccsStorageAddr = readContractAddress("PCCS_STORAGE");
        address pcsDaoAddr = readContractAddress("PCS_DAO");
        AutomataFmspcTcbDao fmspcTcbDao =
            new AutomataFmspcTcbDao{salt: FMSPC_TCB_DAO_SALT}(pccsStorageAddr, simulateVerify(), pcsDaoAddr, fmspcTcbHelper, x509, x509Crl);
        console.log("[LOG] AutomataFmspcTcbDao deployed at: ", address(fmspcTcbDao));
        writeToJson("AutomataFmspcTcbDao", address(fmspcTcbDao));
    }
}
