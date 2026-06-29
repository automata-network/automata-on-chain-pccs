// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {IFmspcTcbDao, TcbInfoJsonObj} from "../../src/interfaces/IFmspcTcbDao.sol";

contract LegacyFmspcSyncUpsert is Script {
    function run() external returns (bytes32 attestationId) {
        address dao = vm.envAddress("LEGACY_FMSPC_DAO");
        string memory tcbInfoStr = vm.envString("LEGACY_TCB_INFO_JSON");
        bytes memory signature = vm.parseBytes(vm.envString("LEGACY_TCB_INFO_SIGNATURE"));

        vm.startBroadcast();
        attestationId = IFmspcTcbDao(dao).upsertFmspcTcb(TcbInfoJsonObj({tcbInfoStr: tcbInfoStr, signature: signature}));
        vm.stopBroadcast();
    }
}
