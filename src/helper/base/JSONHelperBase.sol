// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JSONParserLib} from "solady/utils/JSONParserLib.sol";
import {LibString} from "solady/utils/LibString.sol";
import {BytesUtils} from "../../utils/BytesUtils.sol";
import {P256} from "p256-verifier/P256.sol";

abstract contract JSONHelperBase {
    using BytesUtils for bytes;

    function verifyJsonBodySignature(string calldata tcbInfoStr, bytes calldata signature, bytes calldata signingCertBlob)
        external
        view
        returns (bool verified)
    {
        if (signature.length != 64) {
            return false;
        }

        bytes32 digest = sha256(abi.encodePacked(tcbInfoStr));

        uint256 r = uint256(bytes32(signature.substring(0, 32)));
        uint256 s = uint256(bytes32(signature.substring(32, 32)));

        // TODO: parse signingCertBlob to get the public key
        uint256 gx;
        uint256 gy;

        verified = P256.verifySignatureAllowMalleability(digest, r, s, gx, gy);
    }
}