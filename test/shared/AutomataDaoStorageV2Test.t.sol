// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {AutomataDaoStorageV2} from "../../src/automata_pccs/shared/AutomataDaoStorageV2.sol";

contract AutomataDaoStorageV2Test is Test {
    AutomataDaoStorageV2 storageV2;

    function setUp() public {
        storageV2 = new AutomataDaoStorageV2(address(this), address(0));
        storageV2.grantDao(address(this));
    }

    function testWriteAttestationPreservesExactBytesAcrossSlots() public {
        bytes32 refId = keccak256("raw");
        storageV2.startAsyncWithLength(refId, 96);

        storageV2.writeAttestation(refId, 0, bytes("abc"));
        storageV2.writeAttestation(refId, 30, bytes("12345"));
        storageV2.writeAttestation(refId, 63, bytes("xyz"));

        bytes memory expected = new bytes(96);
        expected[0] = "a";
        expected[1] = "b";
        expected[2] = "c";
        expected[30] = "1";
        expected[31] = "2";
        expected[32] = "3";
        expected[33] = "4";
        expected[34] = "5";
        expected[63] = "x";
        expected[64] = "y";
        expected[65] = "z";

        assertEq(storageV2.readRef(refId), expected);
    }

    function testWriteAttestationRejectsOutOfBoundsWrite() public {
        bytes32 refId = keccak256("oob");
        storageV2.startAsyncWithLength(refId, 64);

        vm.expectRevert(bytes("WRITE_OOB"));
        storageV2.writeAttestation(refId, 63, bytes("ab"));
    }
}
