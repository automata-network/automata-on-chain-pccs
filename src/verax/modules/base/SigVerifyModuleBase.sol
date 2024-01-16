// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BytesUtils} from "../../../utils/BytesUtils.sol";
import {P256} from "p256-verifier/P256.sol";

interface IX509Helper {
    function getSubjectPublicKey(bytes memory der) external pure returns (bytes memory pubKey);
}

abstract contract SigVerifyModuleBase {
    IX509Helper public X509Helper;

    using BytesUtils for bytes;

    constructor(address _x509helper) {
        X509Helper = IX509Helper(_x509helper);
    }

    function verifyJsonBodySignature(string memory body, bytes memory signature, bytes memory signingCertBlob)
        internal
        view
        returns (bool verified)
    {
        if (signature.length != 64) {
            return false;
        }

        bytes32 digest = sha256(abi.encodePacked(body));

        uint256 r = uint256(bytes32(signature.substring(0, 32)));
        uint256 s = uint256(bytes32(signature.substring(32, 32)));

        bytes memory pubKey = X509Helper.getSubjectPublicKey(signingCertBlob);
        uint256 x = uint256(bytes32(pubKey.substring(0, 32)));
        uint256 y = uint256(bytes32(pubKey.substring(32, 32)));

        verified = P256.verifySignatureAllowMalleability(digest, r, s, x, y);
    }
}
