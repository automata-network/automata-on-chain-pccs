// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {FmspcTcbDaoPortal} from "../../src/verax/portals/FmspcTcbDaoPortal.sol";
import {TCBConstants} from "./TCBConstants.t.sol";
import "../pcs/VeraxPcsSetupBase.t.sol";

contract VeraxIdentityPortalTest is VeraxPcsSetupBase, TCBConstants {
    FmspcTcbDaoPortal fmspcTcbPortal;

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);

        address[] memory blank;
        fmspcTcbPortal =
            new FmspcTcbDaoPortal(blank, address(router), address(pcs), address(fsmpcTcbLib), address(x509Lib));

        // register the portal
        portalRegistry.register(
            address(fmspcTcbPortal),
            "Intel On Chain FMPSC TCB Data Access Object Portal", // name
            "some-description", // description
            true, // isRevocable
            "some-owner" // ownerName
        );

        vm.stopPrank();
    }

    function testAttestFmspcTcb() public {
        uint256 tcbType = 0;
        string memory fmspc = "00606a000000";
        uint256 version = 3;

        TcbInfoJsonObj memory tcbInfoObj = TcbInfoJsonObj({tcbInfoStr: string(tcbStr), signature: signature});

        bytes32 attestationId = fmspcTcbPortal.upsertFmspcTcb(tcbInfoObj);
        assertTrue(attestationRegistry.isRegistered(attestationId));
        assertEq(
            fmspcTcbPortal.fmspcTcbInfoAttestations(keccak256(abi.encodePacked(tcbType, fmspc, version))), attestationId
        );
    }
}
