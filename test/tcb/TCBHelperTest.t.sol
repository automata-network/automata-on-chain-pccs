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
