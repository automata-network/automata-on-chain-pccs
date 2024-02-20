// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JSONParserLib} from "solady/utils/JSONParserLib.sol";
import {LibString} from "solady/utils/LibString.sol";
import {DateTimeUtils} from "../utils/DateTimeUtils.sol";

/**
 * @title Solidity Object representing the TCBInfo JSON
 * @param tcbInfo: tcbInfoJson.tcbInfo string object body
 * @param signature The signature to be passed as bytes array
 */
struct TcbInfoJsonObj {
    string tcbInfoStr;
    bytes signature;
}

struct TCBLevelsObj {
    uint256 pcesvn;
    uint256[] cpusvnsArr;
    uint256 tcbDateTimestamp;
    TCBStatus status;
}

enum TCBStatus {
    OK,
    TCB_SW_HARDENING_NEEDED,
    TCB_CONFIGURATION_AND_SW_HARDENING_NEEDED,
    TCB_CONFIGURATION_NEEDED,
    TCB_OUT_OF_DATE,
    TCB_OUT_OF_DATE_CONFIGURATION_NEEDED,
    TCB_REVOKED,
    TCB_UNRECOGNIZED
}

/**
 * @title FMSPC TCB Helper Contract
 * @notice This is a standalone contract that can be used by off-chain applications and smart contracts
 * to parse TCBInfo Blob
 * @notice The TCBInfo Object itself may vary by their version and type.
 * @notice This contract only provides a simple parser that could only extract basic info about the TCBInfo
 * such as, its version, type, fmspc, issue date and next update.
 * @dev should consider extending this contract to implement parsers that could extract detailed TCBInfo
 * using logic that complies to the specific version and type.
 */
contract FmspcTcbHelper {
    using JSONParserLib for JSONParserLib.Item;
    using LibString for string;

    error TCBInfo_Invalid();

    // https://github.com/intel/SGXDataCenterAttestationPrimitives/blob/e7604e02331b3377f3766ed3653250e03af72d45/QuoteVerification/QVL/Src/AttestationLibrary/src/CertVerification/X509Constants.h#L64
    uint256 constant TCB_CPUSVN_SIZE = 16;

    // 1.1M gas
    function parseTcbString(string calldata tcbInfoStr)
        external
        pure
        returns (uint256 tcbType, string memory fmspc, uint256 version, uint256 issueDate, uint256 nextUpdate)
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
                issueDate = DateTimeUtils.fromISOToTimestamp(JSONParserLib.decodeString(current.value()));
                issueDateFound = true;
            }
            if (decodedKey.eq("nextUpdate")) {
                nextUpdate = DateTimeUtils.fromISOToTimestamp(JSONParserLib.decodeString(current.value()));
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

    // 4.18M gas
    function parseTcbLevels(string calldata tcbInfoStr)
        external
        pure
        returns (uint256 version, TCBLevelsObj[] memory tcbLevels)
    {
        JSONParserLib.Item memory root = JSONParserLib.parse(tcbInfoStr);
        JSONParserLib.Item[] memory tcbInfoObj = root.children();

        bool versionFound;
        bool tcbLevelsFound;
        string memory tcbLevelsStr;

        for (uint256 i = 0; i < root.size(); i++) {
            JSONParserLib.Item memory current = tcbInfoObj[i];
            string memory decodedKey = JSONParserLib.decodeString(current.key());
            if (decodedKey.eq("version")) {
                version = JSONParserLib.parseUint(current.value());
                versionFound = true;
            }
            if (decodedKey.eq("tcbLevels")) {
                tcbLevelsStr = current.value();
                tcbLevelsFound = true;
            }
            if (versionFound && tcbLevelsFound) {
                break;
            }
        }

        if (versionFound && tcbLevelsFound) {
            tcbLevels = _parseTCBLevels(version, tcbLevelsStr);
        } else {
            revert TCBInfo_Invalid();
        }
    }

    function _parseTCBLevels(uint256 version, string memory tcbLevelsStr)
        private
        pure
        returns (TCBLevelsObj[] memory tcbLevels)
    {
        JSONParserLib.Item memory tcbLevelsParent = JSONParserLib.parse(tcbLevelsStr);
        JSONParserLib.Item[] memory tcbLevelsObj = tcbLevelsParent.children();
        uint256 tcbLevelsSize = tcbLevelsParent.size();
        tcbLevels = new TCBLevelsObj[](tcbLevelsSize);

        // iterating through the array
        for (uint256 i = 0; i < tcbLevelsSize; i++) {
            JSONParserLib.Item[] memory tcbObj = tcbLevelsObj[i].children();
            // iterating through individual tcb objects
            for (uint256 j = 0; j < tcbLevelsObj[i].size(); j++) {
                string memory tcbKey = JSONParserLib.decodeString(tcbObj[j].key());
                if (tcbKey.eq("tcb")) {
                    string memory tcbStr = tcbObj[j].value();
                    JSONParserLib.Item memory tcbParent = JSONParserLib.parse(tcbStr);
                    JSONParserLib.Item[] memory tcbComponents = tcbParent.children();
                    if (version == 2) {
                        (tcbLevels[i].cpusvnsArr, tcbLevels[i].pcesvn) = _parseV2Tcb(tcbComponents);
                    } else if (version == 3) {
                        (tcbLevels[i].cpusvnsArr, tcbLevels[i].pcesvn) = _parseV3Tcb(tcbComponents);
                    } else {
                        revert TCBInfo_Invalid();
                    }
                } else if (tcbKey.eq("tcbDate")) {
                    tcbLevels[i].tcbDateTimestamp =
                        DateTimeUtils.fromISOToTimestamp(JSONParserLib.decodeString(tcbObj[j].value()));
                } else if (tcbKey.eq("tcbStatus")) {
                    string memory decodedValue = JSONParserLib.decodeString(tcbObj[j].value());
                    if (decodedValue.eq("UpToDate")) {
                        tcbLevels[i].status = TCBStatus.OK;
                    } else if (decodedValue.eq("OutOfDate")) {
                        tcbLevels[i].status = TCBStatus.TCB_OUT_OF_DATE;
                    } else if (decodedValue.eq("OutOfDateConfigurationNeeded")) {
                        tcbLevels[i].status = TCBStatus.TCB_OUT_OF_DATE_CONFIGURATION_NEEDED;
                    } else if (decodedValue.eq("ConfigurationNeeded")) {
                        tcbLevels[i].status = TCBStatus.TCB_CONFIGURATION_NEEDED;
                    } else if (decodedValue.eq("ConfigurationAndSWHardeningNeeded")) {
                        tcbLevels[i].status = TCBStatus.TCB_CONFIGURATION_AND_SW_HARDENING_NEEDED;
                    } else if (decodedValue.eq("SWHardeningNeeded")) {
                        tcbLevels[i].status = TCBStatus.TCB_SW_HARDENING_NEEDED;
                    } else if (decodedValue.eq("Revoked")) {
                        tcbLevels[i].status = TCBStatus.TCB_REVOKED;
                    } else {
                        tcbLevels[i].status = TCBStatus.TCB_UNRECOGNIZED;
                    }
                }
            }
        }
    }

    function _parseV2Tcb(JSONParserLib.Item[] memory tcbComponents)
        private
        pure
        returns (uint256[] memory cpusvns, uint256 pcesvn)
    {
        cpusvns = new uint256[](TCB_CPUSVN_SIZE);
        uint256 cpusvnCounter = 0;
        for (uint256 i = 0; i < tcbComponents.length; i++) {
            string memory key = JSONParserLib.decodeString(tcbComponents[i].key());
            uint256 value = JSONParserLib.parseUint(tcbComponents[i].value());
            if (key.eq("pcesvn")) {
                pcesvn = value;
            } else {
                cpusvns[cpusvnCounter++] = value;
            }
        }
        if (cpusvnCounter != TCB_CPUSVN_SIZE) {
            revert TCBInfo_Invalid();
        }
    }

    function _parseV3Tcb(JSONParserLib.Item[] memory tcbComponents)
        private
        pure
        returns (uint256[] memory cpusvns, uint256 pcesvn)
    {
        cpusvns = new uint256[](TCB_CPUSVN_SIZE);
        uint256 cpusvnCounter;
        for (uint256 i = 0; i < tcbComponents.length; i++) {
            string memory key = JSONParserLib.decodeString(tcbComponents[i].key());
            if (key.eq("pcesvn")) {
                pcesvn = JSONParserLib.parseUint(tcbComponents[i].value());
            } else {
                JSONParserLib.Item[] memory componentArr = tcbComponents[i].children();
                for (uint256 j = 0; j < tcbComponents[i].size(); j++) {
                    JSONParserLib.Item[] memory component = componentArr[j].children();
                    for (uint256 k = 0; k < componentArr[j].size(); k++) {
                        key = JSONParserLib.decodeString(component[k].key());
                        if (key.eq("svn")) {
                            cpusvns[cpusvnCounter++] = JSONParserLib.parseUint(component[k].value());
                        }
                    }
                }
            }
        }
        if (cpusvnCounter != TCB_CPUSVN_SIZE) {
            revert TCBInfo_Invalid();
        }
    }
}
