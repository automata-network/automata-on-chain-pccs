// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JSONParserLib} from "solady/utils/JSONParserLib.sol";
import {LibString} from "solady/utils/LibString.sol";
import {DateTimeUtils} from "../utils/DateTimeUtils.sol";

import {TcbId} from "./FmspcTcbHelper.sol";

/**
 * @dev This is a simple representation of the TCB Evaluation Data Numbers JSON as a Solidity object.
 * @param tcbEvaluationDataNumbers: tcbEvaluationDataNumbers JSON string object body
 * @param signature The signature to be passed as bytes array
 */
struct TcbEvalJsonObj {
    string tcbEvaluationDataNumbers;
    bytes signature;
}

/// @dev Solidity object representing TCB Evaluation Data Numbers
struct TcbEvalDataBasic {
    TcbId id; // "SGX" or "TDX"
    uint32 version;
    uint64 issueDate; // UNIX Epoch Timestamp in seconds
    uint64 nextUpdate; // UNIX Epoch Timestamp in seconds
}

struct TcbEvalNumber {
    uint32 tcbEvaluationDataNumber; // The evaluation data number
    uint64 tcbRecoveryEventDate; // UNIX Epoch Timestamp in seconds of the TCB recovery event
    uint64 tcbDate; // UNIX Epoch Timestamp in seconds
}

/**
 * @title TCB Evaluation Data Helper Contract
 * @notice This is a standalone contract that can be used by off-chain applications and smart contracts
 * to parse TCB Evaluation Data Numbers
 */
contract TcbEvalHelper {
    using JSONParserLib for JSONParserLib.Item;
    using LibString for string;

    error TcbEval_Invalid();
    error TcbEval_Version_Invalid();
    error TcbEval_ID_Invalid();

    // Use bitmaps to represent the keys found in TCB Evaluation Data Numbers
    // Required keys: [id, version, issueDate, nextUpdate, tcbEvalNumbers]
    uint8 constant TCB_EVAL_ID_BIT = 1;
    uint8 constant TCB_EVAL_VERSION_BIT = 2;
    uint8 constant TCB_EVAL_ISSUE_DATE_BIT = 4;
    uint8 constant TCB_EVAL_NEXT_UPDATE_BIT = 8;
    uint8 constant TCB_EVAL_NUMBERS_BIT = 16;

    function tcbEvalNumbersToBytes(TcbEvalNumber[] calldata numbers) external pure returns (bytes memory serialized) {
        bytes memory result;
        for (uint256 i = 0; i < numbers.length; i++) {
            // Pack each TcbEvalNumber into a single 256-bit slot
            // tcbEvaluationDataNumber (32 bits) | tcbRecoveryEventDate (64 bits) | tcbDate (64 bits) | padding (96 bits)
            uint256 slot = uint256(numbers[i].tcbEvaluationDataNumber) << 224
                | uint256(numbers[i].tcbRecoveryEventDate) << 160 | uint256(numbers[i].tcbDate) << 96;
            result = abi.encodePacked(result, slot);
        }
        serialized = result;
    }

    function tcbEvalNumbersFromBytes(bytes calldata encoded) external pure returns (TcbEvalNumber[] memory numbers) {
        uint256 count = encoded.length / 32;
        numbers = new TcbEvalNumber[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 offset = i * 32;
            uint256 slot = uint256(bytes32(encoded[offset:offset + 32]));

            numbers[i].tcbEvaluationDataNumber = uint32(slot >> 224);
            numbers[i].tcbRecoveryEventDate = uint64(slot >> 160);
            numbers[i].tcbDate = uint64(slot >> 96);
        }
    }

    function parseTcbEvalString(string calldata tcbEvalStr)
        external
        pure
        returns (TcbEvalDataBasic memory tcbEvalData, string memory tcbEvalNumbersString)
    {
        JSONParserLib.Item memory root = JSONParserLib.parse(tcbEvalStr);
        JSONParserLib.Item[] memory rootObj = root.children();

        uint256 f;
        uint256 n = root.size();

        for (uint256 i = 0; i < n; i++) {
            JSONParserLib.Item memory current = rootObj[i];
            string memory decodedKey = JSONParserLib.decodeString(current.key());
            string memory val = current.value();

            if (f & TCB_EVAL_ID_BIT == 0 && decodedKey.eq("id")) {
                string memory idStr = JSONParserLib.decodeString(val);
                f |= TCB_EVAL_ID_BIT;
                if (idStr.eq("SGX")) {
                    tcbEvalData.id = TcbId.SGX;
                } else if (idStr.eq("TDX")) {
                    tcbEvalData.id = TcbId.TDX;
                } else {
                    revert TcbEval_ID_Invalid();
                }
            } else if (f & TCB_EVAL_VERSION_BIT == 0 && decodedKey.eq("version")) {
                tcbEvalData.version = uint32(JSONParserLib.parseUint(val));
                f |= TCB_EVAL_VERSION_BIT;
                if (tcbEvalData.version != 1) {
                    revert TcbEval_Version_Invalid();
                }
            } else if (f & TCB_EVAL_ISSUE_DATE_BIT == 0 && decodedKey.eq("issueDate")) {
                tcbEvalData.issueDate = uint64(DateTimeUtils.fromISOToTimestamp(JSONParserLib.decodeString(val)));
                f |= TCB_EVAL_ISSUE_DATE_BIT;
            } else if (f & TCB_EVAL_NEXT_UPDATE_BIT == 0 && decodedKey.eq("nextUpdate")) {
                tcbEvalData.nextUpdate = uint64(DateTimeUtils.fromISOToTimestamp(JSONParserLib.decodeString(val)));
                f |= TCB_EVAL_NEXT_UPDATE_BIT;
            } else if (f & TCB_EVAL_NUMBERS_BIT == 0 && decodedKey.eq("tcbEvalNumbers")) {
                tcbEvalNumbersString = val;
                f |= TCB_EVAL_NUMBERS_BIT;
            }
        }

        bool allFound = f == (2 ** n) - 1;
        if (!allFound) {
            revert TcbEval_Invalid();
        }
    }

    function parseTcbEvalNumbers(string calldata tcbEvalNumbersString)
        external
        pure
        returns (TcbEvalNumber[] memory tcbEvalNumbers)
    {
        JSONParserLib.Item memory root = JSONParserLib.parse(tcbEvalNumbersString);
        JSONParserLib.Item[] memory tcbEvalNumbersObj = root.children();
        uint256 arraySize = tcbEvalNumbersObj.length;
        tcbEvalNumbers = new TcbEvalNumber[](arraySize);

        // Iterating through the array
        for (uint256 i = 0; i < arraySize; i++) {
            JSONParserLib.Item[] memory tcbEvalObj = tcbEvalNumbersObj[i].children();
            // Iterating through individual tcb evaluation objects
            for (uint256 j = 0; j < tcbEvalNumbersObj[i].size(); j++) {
                string memory key = JSONParserLib.decodeString(tcbEvalObj[j].key());
                string memory value = tcbEvalObj[j].value();

                if (key.eq("tcbEvaluationDataNumber")) {
                    tcbEvalNumbers[i].tcbEvaluationDataNumber = uint32(JSONParserLib.parseUint(value));
                } else if (key.eq("tcbRecoveryEventDate")) {
                    tcbEvalNumbers[i].tcbRecoveryEventDate =
                        uint64(DateTimeUtils.fromISOToTimestamp(JSONParserLib.decodeString(value)));
                } else if (key.eq("tcbDate")) {
                    tcbEvalNumbers[i].tcbDate =
                        uint64(DateTimeUtils.fromISOToTimestamp(JSONParserLib.decodeString(value)));
                }
            }
        }
    }
}
