// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JSONHelperBase, JSONParserLib, LibString} from "./base/JSONHelperBase.sol";
import {DateTimeUtils} from "../utils/DateTimeUtils.sol";

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

    function getIssueAndNextUpdateDates(string calldata identityStr) external pure returns (
        uint256 issueDate,
        uint256 nextUpdate
    ) {
        JSONParserLib.Item memory root = JSONParserLib.parse(identityStr);
        JSONParserLib.Item[] memory identityObj = root.children();

        bool issueDateFound;
        bool nextUpdateFound;

        for (uint256 i = 0; i < root.size(); i++) {
            JSONParserLib.Item memory current = identityObj[i];
            string memory decodedKey = JSONParserLib.decodeString(current.key());
            if (decodedKey.eq("issueDate")) {
                issueDate = DateTimeUtils.fromISOToTimestamp(JSONParserLib.decodeString(current.value()));
                issueDateFound = true;
            }
            if (decodedKey.eq("nextUpdate")) {
                nextUpdate = DateTimeUtils.fromISOToTimestamp(JSONParserLib.decodeString(current.value()));
                nextUpdateFound = true;
            }
            if (issueDateFound && nextUpdateFound) {
                break;
            }
        }
    }

    // TODO: Implement full parser
}