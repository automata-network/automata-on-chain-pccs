// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {AutomataDaoStorage} from "../../src/automata_pccs/shared/AutomataDaoStorage.sol";
import {AutomataFmspcTcbDao} from "../../src/automata_pccs/AutomataFmspcTcbDao.sol";
import {AutomataEnclaveIdentityDao} from "../../src/automata_pccs/AutomataEnclaveIdentityDao.sol";
import {AutomataPcsDao} from "../../src/automata_pccs/AutomataPcsDao.sol";
import {AutomataPckDao} from "../../src/automata_pccs/AutomataPckDao.sol";

contract DeployAutomataDao is Script {
    uint256 privateKey = vm.envUint("PRIVATE_KEY");

    address pccsStorageAddr = vm.envAddress("PCCS_STORAGE");
    address pcsDaoAddr = vm.envAddress("PCS_DAO");

    address x509Crl = vm.envAddress("X509_CRL_HELPER");
    address x509 = vm.envAddress("X509_HELPER");
    address enclaveIdentityHelper = vm.envAddress("ENCLAVE_IDENTITY_HELPER");
    address fmspcTcbHelper = vm.envAddress("FMSPC_TCB_HELPER");

    function deployStorage() public {
        vm.broadcast(privateKey);

        AutomataDaoStorage pccsStorage = new AutomataDaoStorage();

        console.log("AutomataDaoStorage deployed at ", address(pccsStorage));
    }

    function deployPcs() public {
        vm.broadcast(privateKey);

        AutomataPcsDao pcsDao = new AutomataPcsDao(pccsStorageAddr, x509, x509Crl);

        console.log("AutomataPcsDao deployed at: ", address(pcsDao));
    }

    function deployPck() public {
        vm.broadcast(privateKey);

        AutomataPckDao pckDao = new AutomataPckDao(pccsStorageAddr, pcsDaoAddr, x509, x509Crl);

        console.log("AutomataPckDao deployed at: ", address(pckDao));
    }

    function deployEnclaveIdDao() public {
        vm.broadcast(privateKey);

        AutomataEnclaveIdentityDao enclaveIdDao =
            new AutomataEnclaveIdentityDao(pccsStorageAddr, pcsDaoAddr, enclaveIdentityHelper, x509);

        console.log("AutomataEnclaveIdDao deployed at: ", address(enclaveIdDao));
    }

    function deployFmspcTcbDao() public {
        vm.broadcast(privateKey);

        AutomataFmspcTcbDao fmspcTcbDao = new AutomataFmspcTcbDao(pccsStorageAddr, pcsDaoAddr, fmspcTcbHelper, x509);

        console.log("AutomataFmspcTcbDao deployed at: ", address(fmspcTcbDao));
    }
}
