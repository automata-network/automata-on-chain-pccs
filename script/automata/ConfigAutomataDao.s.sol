// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {AutomataDaoStorage} from "../../src/automata_pccs/shared/AutomataDaoStorage.sol";

contract ConfigAutomataDao is Script {
    uint256 privateKey = vm.envUint("PRIVATE_KEY");

    address pccsStorageAddr = vm.envAddress("PCCS_STORAGE");
    address pcsDaoAddr = vm.envAddress("PCS_DAO");
    address pckDaoAddr = vm.envAddress("PCK_DAO");
    address fmspcTcbDaoAddr = vm.envAddress("FMSPC_TCB_DAO");
    address enclaveIdDaoAddr = vm.envAddress("ENCLAVE_ID_DAO");

    function updateStorageDao() public {
        vm.broadcast(privateKey);

        AutomataDaoStorage pccsStorage = AutomataDaoStorage(pccsStorageAddr);
        pccsStorage.updateDao(pcsDaoAddr, pckDaoAddr, fmspcTcbDaoAddr, enclaveIdDaoAddr);
    }

    function revokeDao(address dao) public {
        vm.broadcast(privateKey);

        AutomataDaoStorage(pccsStorageAddr).revokeDao(dao);
    }
}