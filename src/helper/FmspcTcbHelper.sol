// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JSONParserLib} from "solady/utils/JSONParserLib.sol";
import {LibString} from "solady/utils/LibString.sol";

/**
 * @param tcbInfo: tcbInfoJson.tcbInfo JSON string
 * @param signature The signature to be passed as bytes array
 */
struct TcbInfoJsonObj {
    string tcbInfoStr;
    bytes signature;
}

/**
 * @title FMSPC TCB Helper Contract
 * @notice This is a standalone contract that can be used by off-chain applications and smart contracts
 * to parse TCBInfo Blob and perform ECDSA Signature verification
 */

contract FmspcTcbHelper {
    using JSONParserLib for JSONParserLib.Item;
    using LibString for string;

    error TCBInfo_Invalid();

    function verifyTcbSignature(bytes calldata tcbInfo, bytes calldata signature, bytes calldata signingCertBlob)
        external
        view
        returns (bool verified)
    {
        // TODO
    }

    function parseTcbString(string memory tcbInfoStr)
        external
        pure
        returns (
            uint256 tcbType,
            string memory fmspc,
            uint256 version,
            string memory issueDate,
            string memory nextUpdate
        )
    {
        JSONParserLib.Item memory root = JSONParserLib.parse(tcbInfoStr);
        JSONParserLib.Item[] memory tcbInfoObj = root.children();

        bool tcbTypeFound;
        bool fmspcFound;
        bool versionFound;
        bool issueDateFound;
        bool nextUpdateFound;
        bool allFound;

        for (uint256 y = 0; y < root.size(); y++) {
            JSONParserLib.Item memory current = tcbInfoObj[y];
            string memory decodedKey = JSONParserLib.decodeString(current.key());
            if (decodedKey.eq("tcbType")) {
                tcbType = JSONParserLib.parseUint(current.value());
                tcbTypeFound = true;
            }
            if (decodedKey.eq("fmspc")) {
                fmspc = JSONParserLib.decodeString(current.value());
                fmspcFound = true;
            }
            if (decodedKey.eq("version")) {
                version = JSONParserLib.parseUint(current.value());
                versionFound = true;
            }
            if (decodedKey.eq("issueDate")) {
                issueDate = JSONParserLib.decodeString(current.value());
                issueDateFound = true;
            }
            if (decodedKey.eq("nextUpdate")) {
                nextUpdate = JSONParserLib.decodeString(current.value());
                nextUpdateFound = true;
            }
            allFound = (tcbTypeFound && fmspcFound && versionFound && issueDateFound && nextUpdateFound);
            if (allFound) {
                break;
            }
        }

        if (!allFound) {
            revert TCBInfo_Invalid();
        }
    }
}
