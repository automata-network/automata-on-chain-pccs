// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../utils/DeploymentConfig.sol";
import "../utils/Multichain.sol";

import {AutomataDaoStorage} from "../../src/automata_pccs/shared/AutomataDaoStorage.sol";
import {AutomataDaoStorageV2} from "../../src/automata_pccs/shared/AutomataDaoStorageV2.sol";

contract ConfigAutomataDao is DeploymentConfig, Multichain {
    address owner = vm.envAddress("OWNER");

    address pccsStorageAddr = readContractAddress("AutomataDaoStorage", true);
    address pccsStorageV2Addr = readContractAddress("AutomataDaoStorageV2", false);

    function grantDao(address dao) public {
        vm.broadcast(owner);

        AutomataDaoStorage pccsStorage = AutomataDaoStorage(pccsStorageAddr);
        pccsStorage.grantDao(dao);
    }

    function grantDaoV2(address dao) public {
        require(pccsStorageV2Addr != address(0), "Missing AutomataDaoStorageV2");
        vm.broadcast(owner);

        AutomataDaoStorageV2(pccsStorageV2Addr).grantDao(dao);
    }

    function revokeDao(address dao) public {
        vm.broadcast(owner);

        AutomataDaoStorage(pccsStorageAddr).revokeDao(dao);
    }

    function revokeDaoV2(address dao) public {
        require(pccsStorageV2Addr != address(0), "Missing AutomataDaoStorageV2");
        vm.broadcast(owner);

        AutomataDaoStorageV2(pccsStorageV2Addr).revokeDao(dao);
    }

    function setAuthorizedCaller(address caller, bool authorized) public multichain {
        AutomataDaoStorage pccsStorage = AutomataDaoStorage(pccsStorageAddr);
        bool authorizedCaller = pccsStorage.isAuthorizedCaller(caller);

        if (authorized != authorizedCaller) {
            vm.broadcast(owner);
            pccsStorage.setCallerAuthorization(caller, authorized);
        } else {
            console.log("Skip setAuthorizedCaller()");
        }
    }

    function setAuthorizedCallerV2(address caller, bool authorized) public multichain {
        require(pccsStorageV2Addr != address(0), "Missing AutomataDaoStorageV2");
        AutomataDaoStorageV2 pccsStorage = AutomataDaoStorageV2(pccsStorageV2Addr);
        bool authorizedCaller = pccsStorage.isAuthorizedCaller(caller);

        if (authorized != authorizedCaller) {
            vm.broadcast(owner);
            pccsStorage.setCallerAuthorization(caller, authorized);
        } else {
            console.log("Skip setAuthorizedCallerV2()");
        }
    }
}
