// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {EnclaveIdentityDaoPortal} from "../../src/verax/portals/EnclaveIdentityDaoPortal.sol";
import {IdentityConstants} from "./IdentityConstants.t.sol";
import "../pcs/VeraxPcsSetupBase.t.sol";

contract VeraxIdentityPortalTest is VeraxPcsSetupBase, IdentityConstants {
    EnclaveIdentityDaoPortal enclaveIdentityPortal;

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);

        address[] memory blank;
        enclaveIdentityPortal = new EnclaveIdentityDaoPortal(
            blank, address(router), address(pcs), address(enclaveIdentityLib), address(x509Lib)
        );

        // register the portal
        portalRegistry.register(
            address(enclaveIdentityPortal),
            "Intel On Chain Enclave Identity Data Access Object Portal", // name
            "some-description", // description
            true, // isRevocable
            "some-owner" // ownerName
        );

        vm.stopPrank();
    }

    function testAttestEnclaveIdentity() public {
        // I am actually not sure what ID is here, need to circle back on this
        uint256 id = 1;
        uint256 version = 4;

        EnclaveIdentityJsonObj memory enclaveIdentityObj =
            EnclaveIdentityJsonObj({identityStr: string(identityStr), signature: signature});

        bytes32 attestationId = enclaveIdentityPortal.upsertEnclaveIdentity(id, version, enclaveIdentityObj);
        assertTrue(attestationRegistry.isRegistered(attestationId));
        assertEq(
            enclaveIdentityPortal.enclaveIdentityAttestations(keccak256(abi.encodePacked(id, version))), attestationId
        );
    }
}
