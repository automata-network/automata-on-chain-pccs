// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JSONParserLib} from "solady/utils/JSONParserLib.sol";
import {LibString} from "solady/utils/LibString.sol";
import {DateTimeUtils} from "../utils/DateTimeUtils.sol";

enum EnclaveId {
    QE,
    QVE,
    TD_QE
}

/**
 * @title Solidity Structure representing the EnclaveIdentity JSON
 * @param identityStr Identity string object body
 * @param signature The signature to be passed as bytes array
 */
struct EnclaveIdentityJsonObj {
    string identityStr;
    bytes signature;
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
    Tcb[] tcb;
}

enum EnclaveIdTcbStatus {
    SGX_ENCLAVE_REPORT_ISVSVN_NOT_SUPPORTED,
    OK,
    SGX_ENCLAVE_REPORT_ISVSVN_REVOKED,
    SGX_ENCLAVE_REPORT_ISVSVN_OUT_OF_DATE
}

struct Tcb {
    uint16 isvsvn;
    uint256 dateTimestamp;
    EnclaveIdTcbStatus status;
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

    function parseIdentityString(string calldata identityStr) external pure returns (IdentityObj memory identity) {
        identity = _parseIdentity(identityStr);
    }

    function _parseIdentity(string calldata identityStr) private pure returns (IdentityObj memory identity) {
        JSONParserLib.Item memory root = JSONParserLib.parse(identityStr);
        JSONParserLib.Item[] memory identityObj = root.children();

        for (uint256 i = 0; i < root.size(); i++) {
            JSONParserLib.Item memory current = identityObj[i];
            string memory decodedKey = JSONParserLib.decodeString(current.key());

            if (decodedKey.eq("issueDate")) {
                identity.issueDateTimestamp =
                    DateTimeUtils.fromISOToTimestamp(JSONParserLib.decodeString(current.value()));
            }
            if (decodedKey.eq("nextUpdate")) {
                identity.nextUpdateTimestamp =
                    DateTimeUtils.fromISOToTimestamp(JSONParserLib.decodeString(current.value()));
            }
            if (decodedKey.eq("id")) {
                string memory idStr = JSONParserLib.decodeString(current.value());
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
                identity.tcb = _parseTcb(current.value());
            }
        }
    }

    function _parseTcb(string memory tcbLevelsStr) internal pure returns (Tcb[] memory tcb) {
        JSONParserLib.Item memory tcbLevelsParent = JSONParserLib.parse(tcbLevelsStr);
        JSONParserLib.Item[] memory tcbLevels = tcbLevelsParent.children();
        uint256 tcbLevelsSize = tcbLevelsParent.size();
        tcb = new Tcb[](tcbLevelsSize);
        for (uint256 i = 0; i < tcbLevelsSize; i++) {
            uint256 tcbLevelsChildSize = tcbLevels[i].size();
            JSONParserLib.Item[] memory tcbObj = tcbLevels[i].children();
            for (uint256 j = 0; j < tcbLevelsChildSize; j++) {
                string memory tcbKey = JSONParserLib.decodeString(tcbObj[j].key());
                if (tcbKey.eq("tcb")) {
                    JSONParserLib.Item[] memory tcbChild = tcbObj[j].children();
                    string memory childKey = JSONParserLib.decodeString(tcbChild[0].key());
                    if (childKey.eq("isvsvn")) {
                        tcb[i].isvsvn = uint16(JSONParserLib.parseUint(tcbChild[0].value()));
                    }
                } else if (tcbKey.eq("tcbDate")) {
                    tcb[i].dateTimestamp =
                        DateTimeUtils.fromISOToTimestamp(JSONParserLib.decodeString(tcbObj[j].value()));
                } else if (tcbKey.eq("tcbStatus")) {
                    string memory decodedValue = JSONParserLib.decodeString(tcbObj[j].value());
                    if (decodedValue.eq("UpToDate")) {
                        tcb[i].status = EnclaveIdTcbStatus.OK;
                    } else if (decodedValue.eq("Revoked")) {
                        tcb[i].status = EnclaveIdTcbStatus.SGX_ENCLAVE_REPORT_ISVSVN_REVOKED;
                    } else if (decodedValue.eq("OutOfDate")) {
                        tcb[i].status = EnclaveIdTcbStatus.SGX_ENCLAVE_REPORT_ISVSVN_OUT_OF_DATE;
                    }
                }
            }
        }
    }
}
