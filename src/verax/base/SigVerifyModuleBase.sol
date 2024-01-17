// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BytesUtils} from "../../utils/BytesUtils.sol";
import {X509Helper} from "../../helper/X509Helper.sol";
import {P256} from "p256-verifier/P256.sol";

abstract contract SigVerifyModuleBase {
    X509Helper public x509Helper;

    using BytesUtils for bytes;

    error Invalid_Signature();

    constructor(address _x509helper) {
        x509Helper = X509Helper(_x509helper);
    }

    function verifySignature(bytes32 digest, bytes memory signature, bytes memory signingCertBlob)
        internal
        view
        returns (bool verified)
    {
        if (signature.length != 64) {
            return false;
        }

        uint256 r = uint256(bytes32(signature.substring(0, 32)));
        uint256 s = uint256(bytes32(signature.substring(32, 32)));

        bytes memory pubKey = x509Helper.getSubjectPublicKey(signingCertBlob);
        if (pubKey.length != 64) {
            return false;
        }
        uint256 x = uint256(bytes32(pubKey.substring(0, 32)));
        uint256 y = uint256(bytes32(pubKey.substring(32, 32)));

        verified = P256.verifySignatureAllowMalleability(digest, r, s, x, y);
    }
}
