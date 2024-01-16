// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SigVerifyModuleBase} from "./base/SigVerifyModuleBase.sol";
import {
    AbstractModule,
    AttestationPayload
} from "@consensys/linea-attestation-registry-contracts/abstracts/AbstractModule.sol";

contract FmspcTcbModule is SigVerifyModuleBase, AbstractModule {
    constructor(address _x509helper) SigVerifyModuleBase(_x509helper) {}

    function run(
        AttestationPayload memory attestationPayload,
        bytes memory validationPayload,
        address, /* txSender */
        uint256 /* value */
    ) public view override {
        (,,,, string memory tcbInfo, bytes memory signature) =
            abi.decode(attestationPayload.attestationData, (uint256, uint256, uint256, uint256, string, bytes));
        bytes32 digest = sha256(abi.encodePacked(tcbInfo));
        bool sigVerified = verifySignature(digest, signature, validationPayload);
        if (!sigVerified) {
            revert Invalid_Signature();
        }
    }
}
