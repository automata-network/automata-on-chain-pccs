// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../../src/helpers/FmspcTcbHelper.sol";
import "./TCBConstants.t.sol";
import "./TDXConstants.t.sol";

contract IdentityHelperTest is TCBConstants, TDXConstants, Test {
    FmspcTcbHelper fmspcTcbLib;

    function setUp() public {
        fmspcTcbLib = new FmspcTcbHelper();
    }

    function testTcbLevelsSerialization() public {

        string memory str = "{\"id\":\"SGX\",\"version\":3,\"issueDate\":\"2024-11-22T15:44:38Z\",\"nextUpdate\":\"2024-12-22T15:44:38Z\",\"fmspc\":\"00606A000000\",\"pceId\":\"0000\",\"tcbType\":0,\"tcbEvaluationDataNumber\":17,\"tcbLevels\":[{\"tcb\":{\"sgxtcbcomponents\":[{\"svn\":14,\"category\":\"BIOS\",\"type\":\"Early Microcode Update\"},{\"svn\":14,\"category\":\"OS/VMM\",\"type\":\"SGX Late Microcode Update\"},{\"svn\":3,\"category\":\"OS/VMM\",\"type\":\"TXT SINIT\"},{\"svn\":3,\"category\":\"BIOS\"},{\"svn\":255},{\"svn\":255},{\"svn\":1},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0}],\"pcesvn\":13},\"tcbDate\":\"2024-03-13T00:00:00Z\",\"tcbStatus\":\"SWHardeningNeeded\",\"advisoryIDs\":[\"INTEL-SA-00615\"]},{\"tcb\":{\"sgxtcbcomponents\":[{\"svn\":14,\"category\":\"BIOS\",\"type\":\"Early Microcode Update\"},{\"svn\":14,\"category\":\"OS/VMM\",\"type\":\"SGX Late Microcode Update\"},{\"svn\":3,\"category\":\"OS/VMM\",\"type\":\"TXT SINIT\"},{\"svn\":3,\"category\":\"BIOS\"},{\"svn\":255},{\"svn\":255},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0}],\"pcesvn\":13},\"tcbDate\":\"2024-03-13T00:00:00Z\",\"tcbStatus\":\"ConfigurationAndSWHardeningNeeded\",\"advisoryIDs\":[\"INTEL-SA-00657\",\"INTEL-SA-00767\",\"INTEL-SA-00615\"]},{\"tcb\":{\"sgxtcbcomponents\":[{\"svn\":12,\"category\":\"BIOS\",\"type\":\"Early Microcode Update\"},{\"svn\":12,\"category\":\"OS/VMM\",\"type\":\"SGX Late Microcode Update\"},{\"svn\":3,\"category\":\"OS/VMM\",\"type\":\"TXT SINIT\"},{\"svn\":3,\"category\":\"BIOS\"},{\"svn\":255},{\"svn\":255},{\"svn\":1},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0}],\"pcesvn\":13},\"tcbDate\":\"2023-08-09T00:00:00Z\",\"tcbStatus\":\"OutOfDate\",\"advisoryIDs\":[\"INTEL-SA-00960\",\"INTEL-SA-00657\",\"INTEL-SA-00767\",\"INTEL-SA-00615\"]},{\"tcb\":{\"sgxtcbcomponents\":[{\"svn\":12,\"category\":\"BIOS\",\"type\":\"Early Microcode Update\"},{\"svn\":12,\"category\":\"OS/VMM\",\"type\":\"SGX Late Microcode Update\"},{\"svn\":3,\"category\":\"OS/VMM\",\"type\":\"TXT SINIT\"},{\"svn\":3,\"category\":\"BIOS\"},{\"svn\":255},{\"svn\":255},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0}],\"pcesvn\":13},\"tcbDate\":\"2023-08-09T00:00:00Z\",\"tcbStatus\":\"OutOfDateConfigurationNeeded\",\"advisoryIDs\":[\"INTEL-SA-00657\",\"INTEL-SA-00767\",\"INTEL-SA-00960\",\"INTEL-SA-00615\"]},{\"tcb\":{\"sgxtcbcomponents\":[{\"svn\":11,\"category\":\"BIOS\",\"type\":\"Early Microcode Update\"},{\"svn\":11,\"category\":\"OS/VMM\",\"type\":\"SGX Late Microcode Update\"},{\"svn\":3,\"category\":\"OS/VMM\",\"type\":\"TXT SINIT\"},{\"svn\":3,\"category\":\"BIOS\"},{\"svn\":255},{\"svn\":255},{\"svn\":1},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0}],\"pcesvn\":13},\"tcbDate\":\"2023-02-15T00:00:00Z\",\"tcbStatus\":\"OutOfDate\",\"advisoryIDs\":[\"INTEL-SA-00828\",\"INTEL-SA-00837\",\"INTEL-SA-00657\",\"INTEL-SA-00767\",\"INTEL-SA-00960\",\"INTEL-SA-00615\"]},{\"tcb\":{\"sgxtcbcomponents\":[{\"svn\":11,\"category\":\"BIOS\",\"type\":\"Early Microcode Update\"},{\"svn\":11,\"category\":\"OS/VMM\",\"type\":\"SGX Late Microcode Update\"},{\"svn\":3,\"category\":\"OS/VMM\",\"type\":\"TXT SINIT\"},{\"svn\":3,\"category\":\"BIOS\"},{\"svn\":255},{\"svn\":255},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0}],\"pcesvn\":13},\"tcbDate\":\"2023-02-15T00:00:00Z\",\"tcbStatus\":\"OutOfDateConfigurationNeeded\",\"advisoryIDs\":[\"INTEL-SA-00828\",\"INTEL-SA-00837\",\"INTEL-SA-00657\",\"INTEL-SA-00767\",\"INTEL-SA-00960\",\"INTEL-SA-00615\"]},{\"tcb\":{\"sgxtcbcomponents\":[{\"svn\":7,\"category\":\"BIOS\",\"type\":\"Early Microcode Update\"},{\"svn\":9,\"category\":\"OS/VMM\",\"type\":\"SGX Late Microcode Update\"},{\"svn\":3,\"category\":\"OS/VMM\",\"type\":\"TXT SINIT\"},{\"svn\":3,\"category\":\"BIOS\"},{\"svn\":255},{\"svn\":255},{\"svn\":1},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0}],\"pcesvn\":13},\"tcbDate\":\"2022-08-10T00:00:00Z\",\"tcbStatus\":\"OutOfDate\",\"advisoryIDs\":[\"INTEL-SA-00657\",\"INTEL-SA-00730\",\"INTEL-SA-00738\",\"INTEL-SA-00767\",\"INTEL-SA-00828\",\"INTEL-SA-00837\",\"INTEL-SA-00960\",\"INTEL-SA-00615\"]},{\"tcb\":{\"sgxtcbcomponents\":[{\"svn\":7,\"category\":\"BIOS\",\"type\":\"Early Microcode Update\"},{\"svn\":9,\"category\":\"OS/VMM\",\"type\":\"SGX Late Microcode Update\"},{\"svn\":3,\"category\":\"OS/VMM\",\"type\":\"TXT SINIT\"},{\"svn\":3,\"category\":\"BIOS\"},{\"svn\":255},{\"svn\":255},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0}],\"pcesvn\":13},\"tcbDate\":\"2022-08-10T00:00:00Z\",\"tcbStatus\":\"OutOfDateConfigurationNeeded\",\"advisoryIDs\":[\"INTEL-SA-00657\",\"INTEL-SA-00730\",\"INTEL-SA-00738\",\"INTEL-SA-00767\",\"INTEL-SA-00828\",\"INTEL-SA-00837\",\"INTEL-SA-00960\",\"INTEL-SA-00615\"]},{\"tcb\":{\"sgxtcbcomponents\":[{\"svn\":4,\"category\":\"BIOS\",\"type\":\"Early Microcode Update\"},{\"svn\":4,\"category\":\"OS/VMM\",\"type\":\"SGX Late Microcode Update\"},{\"svn\":3,\"category\":\"OS/VMM\",\"type\":\"TXT SINIT\"},{\"svn\":3,\"category\":\"BIOS\"},{\"svn\":255},{\"svn\":255},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0}],\"pcesvn\":11},\"tcbDate\":\"2021-11-10T00:00:00Z\",\"tcbStatus\":\"OutOfDate\",\"advisoryIDs\":[\"INTEL-SA-00586\",\"INTEL-SA-00614\",\"INTEL-SA-00615\",\"INTEL-SA-00657\",\"INTEL-SA-00730\",\"INTEL-SA-00738\",\"INTEL-SA-00767\",\"INTEL-SA-00828\",\"INTEL-SA-00837\",\"INTEL-SA-00960\"]},{\"tcb\":{\"sgxtcbcomponents\":[{\"svn\":4,\"category\":\"BIOS\",\"type\":\"Early Microcode Update\"},{\"svn\":4,\"category\":\"OS/VMM\",\"type\":\"SGX Late Microcode Update\"},{\"svn\":3,\"category\":\"OS/VMM\",\"type\":\"TXT SINIT\"},{\"svn\":3,\"category\":\"BIOS\"},{\"svn\":255},{\"svn\":255},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0}],\"pcesvn\":10},\"tcbDate\":\"2020-11-11T00:00:00Z\",\"tcbStatus\":\"OutOfDate\",\"advisoryIDs\":[\"INTEL-SA-00477\",\"INTEL-SA-00586\",\"INTEL-SA-00614\",\"INTEL-SA-00615\",\"INTEL-SA-00657\",\"INTEL-SA-00730\",\"INTEL-SA-00738\",\"INTEL-SA-00767\",\"INTEL-SA-00828\",\"INTEL-SA-00837\",\"INTEL-SA-00960\"]},{\"tcb\":{\"sgxtcbcomponents\":[{\"svn\":4,\"category\":\"BIOS\",\"type\":\"Early Microcode Update\"},{\"svn\":4,\"category\":\"OS/VMM\",\"type\":\"SGX Late Microcode Update\"},{\"svn\":3,\"category\":\"OS/VMM\",\"type\":\"TXT SINIT\"},{\"svn\":3,\"category\":\"BIOS\"},{\"svn\":255},{\"svn\":255},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0}],\"pcesvn\":5},\"tcbDate\":\"2018-01-04T00:00:00Z\",\"tcbStatus\":\"OutOfDate\",\"advisoryIDs\":[\"INTEL-SA-00106\",\"INTEL-SA-00115\",\"INTEL-SA-00135\",\"INTEL-SA-00203\",\"INTEL-SA-00220\",\"INTEL-SA-00233\",\"INTEL-SA-00270\",\"INTEL-SA-00293\",\"INTEL-SA-00320\",\"INTEL-SA-00329\",\"INTEL-SA-00381\",\"INTEL-SA-00389\",\"INTEL-SA-00477\",\"INTEL-SA-00586\",\"INTEL-SA-00614\",\"INTEL-SA-00615\",\"INTEL-SA-00657\",\"INTEL-SA-00730\",\"INTEL-SA-00738\",\"INTEL-SA-00767\",\"INTEL-SA-00828\",\"INTEL-SA-00837\",\"INTEL-SA-00960\"]}]}";

        TcbInfoBasic memory tcbInfo = fmspcTcbLib.parseTcbString(str);
        (uint256 version, TCBLevelsObj[] memory tcbLevels) = fmspcTcbLib.parseTcbLevels(str);

        TCBLevelsObj memory tcb = tcbLevels[1];

        bytes memory serialized = fmspcTcbLib.tcbLevelsObjToBytes(tcb);

        TCBLevelsObj memory ret = fmspcTcbLib.tcbLevelsObjFromBytes(serialized);

        assertEq(tcb.pcesvn, ret.pcesvn);
        assertEq(tcb.tcbDateTimestamp, ret.tcbDateTimestamp);
        assertEq(uint8(tcb.status), uint8(ret.status));
        
        for (uint256 i = 0; i < 16; i++) {
            assertEq(tcb.sgxComponentCpuSvns[i], ret.sgxComponentCpuSvns[i]);
            assertEq(tcb.tdxSvns[i], ret.tdxSvns[i]);
        }

        for (uint256 j = 0; j < tcb.advisoryIDs.length; j++) {
            assertEq(
                keccak256(bytes(tcb.advisoryIDs[j])), 
                keccak256(bytes(ret.advisoryIDs[j]))
            );
        }
    }

    function testTcbStringBasicParser() public {
        TcbInfoBasic memory tcbInfo = fmspcTcbLib.parseTcbString(string(tdx_tcbStr));
        assertEq(tcbInfo.tcbType, 0);
        assertEq(uint8(tcbInfo.id), uint8(TcbId.TDX));

        assertEq(keccak256(abi.encodePacked(tcbInfo.fmspc)), keccak256(hex"90C06f000000"));
        assertEq(tcbInfo.version, 3);
        assertEq(tcbInfo.issueDate, 1715843417);
        assertEq(tcbInfo.nextUpdate, 1718435417);
    }

    function testV3TcbLevelsParser() public {
        (uint256 version, TCBLevelsObj[] memory tcbLevels) = fmspcTcbLib.parseTcbLevels(string(tdx_tcbStr));
        assertEq(version, 3);

        // TODO: add test cases for the remaining tcblevels
        _assertTcbLevel(
            tcbLevels[0],
            [2, 2, 2, 2, 3, 1, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0],
            [4, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            13,
            1710288000,
            TCBStatus.OK
        );
    }

    function testTdxModulesParser() public {
        (TDXModule memory module, TDXModuleIdentity[] memory moduleIdentities) =
            fmspcTcbLib.parseTcbTdxModules(string(tdx_tcbStr));

        // module assertions
        assertEq(keccak256(module.mrsigner), keccak256(mrsigner));
        assertEq(module.attributes, attributes);
        assertEq(module.attributesMask, attributesMask);

        // module identity assertions
        TDXModuleIdentity memory moduleIdentity = moduleIdentities[0];
        assertEq(keccak256(bytes(moduleIdentity.id)), keccak256(bytes(moduleIdentitiesId)));
        assertEq(keccak256(moduleIdentity.mrsigner), keccak256(mrsigner));
        assertEq(moduleIdentity.attributes, attributes);
        assertEq(moduleIdentity.attributesMask, attributesMask);
        _assertTdxTcbLevels(
            moduleIdentity.tcbLevels,
            [4, 2],
            [uint256(1710288000), uint256(1691539200)],
            [TCBStatus.OK, TCBStatus.TCB_OUT_OF_DATE]
        );
    }

    function _assertTcbLevel(
        TCBLevelsObj memory tcbLevel,
        uint8[16] memory expectedCpuSvns,
        uint8[16] memory expectedTdxSvns,
        uint256 expectedPcesvn,
        uint256 expectedTimestamp,
        TCBStatus expectedStatus
    ) private {
        assertEq(tcbLevel.pcesvn, expectedPcesvn);
        assertEq(tcbLevel.tcbDateTimestamp, expectedTimestamp);
        assertEq(uint8(tcbLevel.status), uint8(expectedStatus));
        for (uint256 i = 0; i < 16; i++) {
            assertEq(tcbLevel.sgxComponentCpuSvns[i], expectedCpuSvns[i]);
            assertEq(tcbLevel.tdxSvns[i], expectedTdxSvns[i]);
        }
    }

    function _assertTdxTcbLevels(
        TDXModuleTCBLevelsObj[] memory tcbLevelsArr,
        uint8[2] memory isvsvnArr,
        uint256[2] memory timestampArr,
        TCBStatus[2] memory statusArr
    ) private {
        uint256 n = tcbLevelsArr.length;
        require(n == isvsvnArr.length, "isvsvn length incorrect");
        require(n == timestampArr.length, "timestamp length incorrect");
        require(n == statusArr.length, "status length incorrect");

        for (uint256 i = 0; i < n; i++) {
            assertEq(tcbLevelsArr[i].isvsvn, isvsvnArr[i]);
            assertEq(tcbLevelsArr[i].tcbDateTimestamp, timestampArr[i]);
            assertEq(uint8(tcbLevelsArr[i].status), uint8(statusArr[i]));
        }
    }
}
