// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "forge-std/Test.sol";
import {FmspcTcbHelper, TCBLevelsObj, TcbInfoBasic} from "../src/helpers/FmspcTcbHelper.sol";

contract DumpPacked is Test {
    function testDump() public {
        FmspcTcbHelper h = new FmspcTcbHelper();
        string memory raw = vm.readFile("test/tcb/fixtures/live_intel_eval19_inner.txt");
        (,string memory tcbLevelsString,,) = h.parseTcbString(raw);
        TCBLevelsObj[] memory levels = h.parseTcbLevels(3, tcbLevelsString);
        emit log_named_uint("num levels", levels.length);
        bytes memory packed0 = h.tcbLevelsObjToBytes(levels[0]);
        emit log_named_bytes("level0 packed", packed0);
        emit log_named_uint("level0 pcesvn", levels[0].pcesvn);
        emit log_named_uint("level0 tcbDate", levels[0].tcbDateTimestamp);
        emit log_named_uint("level0 status", uint256(uint8(uint256(levels[0].status))));
        for (uint i = 0; i < 16; i++) {
            emit log_named_uint(string.concat("sgx[", vm.toString(i), "]"), levels[0].sgxComponentCpuSvns[i]);
        }
        emit log_named_uint("tdx svns length", levels[0].tdxComponentCpuSvns.length);
    }
}
