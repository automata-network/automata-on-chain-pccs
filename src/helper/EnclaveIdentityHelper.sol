// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JSONHelperBase, JSONParserLib, LibString} from "./base/JSONHelperBase.sol";

/**
 * @param identityStr The Identity JSON body
 * @param signature The signature to be passed as bytes array
 */
struct EnclaveIdentityJsonObj {
    string identityStr;
    bytes signature;
}

/// @dev Parsed IdentityStr to an object, except for TCBLevels
struct IdentityObj {
    string id;
    uint256 version;
    string issueDate;
    string nextUpdate;
    uint256 tcbEvaluationDataNumber;
    string miscselect;
    string miscselectMask;
    string attributes;
    string attributesMask;
    string mrSigner;
    string isvprodid;
    string tcbLevelsObjStr;
}

contract EnclaveIdentityHelper is JSONHelperBase {
    using JSONParserLib for JSONParserLib.Item;
    using LibString for string;

    function getIssueDate(string calldata identityStr) external pure returns (string memory issueDate) {
        JSONParserLib.Item memory root = JSONParserLib.parse(identityStr);
        JSONParserLib.Item[] memory identityObj = root.children();

        for (uint256 i = 0; i < root.size(); i++) {
            JSONParserLib.Item memory current = identityObj[i];
            string memory decodedKey = JSONParserLib.decodeString(current.key());
            if (decodedKey.eq("issueDate")) {
                issueDate = JSONParserLib.decodeString(current.value());
                break;
            }
        }
    }

    // TODO: Implement full parser
}
