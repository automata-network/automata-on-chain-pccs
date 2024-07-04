// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../pcs/PCSSetupBase.t.sol";

import {TCBConstants} from "./TCBConstants.t.sol";

contract AutomataFmspcTcbDaoTest is PCSSetupBase, TCBConstants {
    function setUp() public override {
        super.setUp();
    }

    function testAttestFmspcTcb() public {
        uint8 tcbType = 0;
        string memory fmspc = "00606a000000";
        uint32 version = 2;

        TcbInfoJsonObj memory tcbInfoObj =
            TcbInfoJsonObj({tcbInfoStr: string(sgx_v2_tcbStr), signature: sgx_v2_signature});

        bytes32 attestationId = fmspcTcbDao.upsertFmspcTcb(tcbInfoObj);
        assertEq(
            fmspcTcbDao.fmspcTcbInfoAttestations(keccak256(abi.encodePacked(tcbType, fmspc, version))), attestationId
        );

        TcbInfoJsonObj memory fetched = fmspcTcbDao.getTcbInfo(tcbType, fmspc, version);
        assertEq(fetched.signature, tcbInfoObj.signature);
        assertEq(fmspcTcbDao.getCollateralHash(attestationId), sha256(bytes(tcbInfoObj.tcbInfoStr)));
    }

    function testAttestFmspcTcbSgxV3() public {
        // July 4th, 2024, 2:22:34 AM UTC
        vm.warp(1720059754);

        uint8 tcbType = 0;
        string memory fmspc = "10A06D070000";
        uint32 version = 3;

        TcbInfoJsonObj memory tcbInfoObj =
            TcbInfoJsonObj({tcbInfoStr: string(sgx_v3_tcbStr), signature: sgx_v3_signature});

        bytes32 attestationId = fmspcTcbDao.upsertFmspcTcb(tcbInfoObj);
        assertEq(
            fmspcTcbDao.fmspcTcbInfoAttestations(keccak256(abi.encodePacked(tcbType, fmspc, version))), attestationId
        );

        TcbInfoJsonObj memory fetched = fmspcTcbDao.getTcbInfo(tcbType, fmspc, version);
        assertEq(fetched.signature, tcbInfoObj.signature);
        assertEq(fmspcTcbDao.getCollateralHash(attestationId), sha256(bytes(tcbInfoObj.tcbInfoStr)));
    }

    function testTcbIssuerChain() public {
        (bytes memory fetchedSigning, bytes memory fetchedRoot) = fmspcTcbDao.getTcbIssuerChain();
        assertEq(keccak256(signingDer), keccak256(fetchedSigning));
        assertEq(keccak256(rootDer), keccak256(fetchedRoot));
    }
}
