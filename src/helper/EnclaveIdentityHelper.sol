// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JSONParserLib} from "solady/utils/JSONParserLib.sol";
import {LibString} from "solady/utils/LibString.sol";
import {DateTimeUtils} from "../utils/DateTimeUtils.sol";

/**
 * @title Solidity Structure representing the EnclaveIdentity JSON
 * @param identityStr Identity string object body
 * @param signature The signature to be passed as bytes array
 */
struct EnclaveIdentityJsonObj {
    string identityStr;
    bytes signature;
}

enum EnclaveId {
    QE,
    QVE,
    TD_QE
}

/// @dev Parsed IdentityStr to an object, except for TCBLevels
struct IdentityObj {
    EnclaveId id;
    uint256 version;
    uint256 issueDateTimestamp; // UNIX Epoch Timestamp in seconds
    uint256 nextUpdateTimestamp; // UNIX Epoch Timestamp in seconds
    uint256 tcbEvaluationDataNumber;
    bytes4 miscselect;
    bytes4 miscselectMask;
    bytes16 attributes;
    bytes16 attributesMask;
    bytes32 mrsigner;
    uint16 isvprodid;
    string rawTcbLevelsObjStr;
}

/**
 * @title Enclave Identity Helper Contract
 * @notice This is a standalone contract that can be used by off-chain applications and smart contracts
 * to parse Enclave Identity Blob
 */
contract EnclaveIdentityHelper {
    using JSONParserLib for JSONParserLib.Item;
    using LibString for string;

    error Invalid_ID();

    // 245k gas
    function getIdentitySummary(string calldata identityStr)
        external
        pure
        returns (uint256 issueDate, uint256 nextUpdate, EnclaveId id)
    {
        IdentityObj memory identity = _parseIdentity(identityStr, false);
        issueDate = identity.issueDateTimestamp;
        nextUpdate = identity.nextUpdateTimestamp;
        id = identity.id;
    }

    function parseIdentityString(string calldata identityStr) external pure returns (IdentityObj memory identity) {
        identity = _parseIdentity(identityStr, true);
    }

    function _parseIdentity(string calldata identityStr, bool parseFully)
        private
        pure
        returns (IdentityObj memory identity)
    {
        JSONParserLib.Item memory root = JSONParserLib.parse(identityStr);
        JSONParserLib.Item[] memory identityObj = root.children();

        for (uint256 i = 0; i < root.size(); i++) {
            JSONParserLib.Item memory current = identityObj[i];
            string memory decodedKey = JSONParserLib.decodeString(current.key());

            // gas-saving: break the loop as long as the three conditions below have met
            // only used by getIdentitySummary()
            bool issueDateFound;
            bool nextUpdateFound;
            bool idFound;

            if (decodedKey.eq("issueDate")) {
                identity.issueDateTimestamp =
                    DateTimeUtils.fromISOToTimestamp(JSONParserLib.decodeString(current.value()));
                issueDateFound = true;
            }
            if (decodedKey.eq("nextUpdate")) {
                identity.nextUpdateTimestamp =
                    DateTimeUtils.fromISOToTimestamp(JSONParserLib.decodeString(current.value()));
                nextUpdateFound = true;
            }
            if (decodedKey.eq("id")) {
                string memory idStr = JSONParserLib.decodeString(current.value());
                idFound = true;
                if (LibString.eq(idStr, "QE")) {
                    identity.id = EnclaveId.QE;
                } else if (LibString.eq(idStr, "QVE")) {
                    identity.id = EnclaveId.QVE;
                } else if (LibString.eq(idStr, "TD_QE")) {
                    identity.id = EnclaveId.TD_QE;
                } else {
                    revert Invalid_ID();
                }
            }
            if (parseFully) {
                if (decodedKey.eq("version")) {
                    identity.version = JSONParserLib.parseUint(current.value());
                }
                if (decodedKey.eq("tcbEvaluationDataNumber")) {
                    identity.tcbEvaluationDataNumber = JSONParserLib.parseUint(current.value());
                }
                if (decodedKey.eq("miscselect")) {
                    uint256 val = JSONParserLib.parseUintFromHex(JSONParserLib.decodeString(current.value()));
                    identity.miscselect = bytes4(uint32(val));
                }
                if (decodedKey.eq("miscselectMask")) {
                    uint256 val = JSONParserLib.parseUintFromHex(JSONParserLib.decodeString(current.value()));
                    identity.miscselectMask = bytes4(uint32(val));
                }
                if (decodedKey.eq("attributes")) {
                    uint256 val = JSONParserLib.parseUintFromHex(JSONParserLib.decodeString(current.value()));
                    identity.attributes = bytes16(uint128(val));
                }
                if (decodedKey.eq("attributesMask")) {
                    uint256 val = JSONParserLib.parseUintFromHex(JSONParserLib.decodeString(current.value()));
                    identity.attributesMask = bytes16(uint128(val));
                }
                if (decodedKey.eq("mrsigner")) {
                    uint256 val = JSONParserLib.parseUintFromHex(JSONParserLib.decodeString(current.value()));
                    identity.mrsigner = bytes32(val);
                }
                if (decodedKey.eq("isvprodid")) {
                    identity.isvprodid = uint16(JSONParserLib.parseUint(current.value()));
                }
                if (decodedKey.eq("tcbLevels")) {
                    identity.rawTcbLevelsObjStr = current.value();
                }
            } else if (issueDateFound && nextUpdateFound && idFound) {
                break;
            }
        }
    }
}
