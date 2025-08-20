// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../utils/DeploymentConfig.sol";

import {AutomataDaoStorage} from "../../src/automata_pccs/shared/AutomataDaoStorage.sol";
import {AutomataFmspcTcbDao} from "../../src/automata_pccs/AutomataFmspcTcbDao.sol";
import {AutomataEnclaveIdentityDao} from "../../src/automata_pccs/AutomataEnclaveIdentityDao.sol";
import {AutomataPcsDao} from "../../src/automata_pccs/AutomataPcsDao.sol";
import {AutomataPckDao} from "../../src/automata_pccs/AutomataPckDao.sol";

contract ConfigAutomataDao is DeploymentConfig {
    address owner = vm.envAddress("OWNER");

    address pccsStorageAddr = readContractAddress("AutomataDaoStorage", true);

    function grantDao(address dao) public {
        vm.broadcast(owner);

        AutomataDaoStorage pccsStorage = AutomataDaoStorage(pccsStorageAddr);
        pccsStorage.grantDao(dao);
    }

    function revokeDao(address dao) public {
        vm.broadcast(owner);

        AutomataDaoStorage(pccsStorageAddr).revokeDao(dao);
    }

    function setAuthorizedCaller(address caller, bool authorized) public {
        vm.broadcast(owner);

        AutomataDaoStorage(pccsStorageAddr).setCallerAuthorization(caller, authorized);
    }
}
