// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {TcbEvalHelper, TcbEvalDataBasic, TcbEvalNumber, TcbId} from "src/helpers/TcbEvalHelper.sol";

contract TcbEvalHelperTest is Test {
    TcbEvalHelper internal tcbEvalHelper;
    // string internal tcbEvalJsonContent; // Full content of tcbeval.json - not used directly
    string internal tcbEvaluationDataNumbersStr; // Extracted "tcbEvaluationDataNumbers" object string
    string internal tcbEvalNumbersArrayStr; // Extracted "tcbEvalNumbers" array string

    function setUp() public {
        tcbEvalHelper = new TcbEvalHelper();

        // Hardcoded JSON strings based on test/eval/tcbeval.json
        tcbEvaluationDataNumbersStr = string(
            abi.encodePacked(
                '{"id":"SGX","version":1,"issueDate":"2025-06-02T02:43:30Z","nextUpdate":"2025-07-02T02:43:30Z","tcbEvalNumbers":',
                '[{"tcbEvaluationDataNumber":19,"tcbRecoveryEventDate":"2025-05-13T00:00:00Z","tcbDate":"2025-05-14T00:00:00Z"},',
                '{"tcbEvaluationDataNumber":18,"tcbRecoveryEventDate":"2024-11-12T00:00:00Z","tcbDate":"2024-11-13T00:00:00Z"},',
                '{"tcbEvaluationDataNumber":17,"tcbRecoveryEventDate":"2024-03-12T00:00:00Z","tcbDate":"2024-03-13T00:00:00Z"}]',
                '}'
            )
        );

        tcbEvalNumbersArrayStr = string(
            abi.encodePacked(
                '[{"tcbEvaluationDataNumber":19,"tcbRecoveryEventDate":"2025-05-13T00:00:00Z","tcbDate":"2025-05-14T00:00:00Z"},',
                '{"tcbEvaluationDataNumber":18,"tcbRecoveryEventDate":"2024-11-12T00:00:00Z","tcbDate":"2024-11-13T00:00:00Z"},',
                '{"tcbEvaluationDataNumber":17,"tcbRecoveryEventDate":"2024-03-12T00:00:00Z","tcbDate":"2024-03-13T00:00:00Z"}]'
            )
        );
    }

    function test_ParseTcbEvalString() public {
        (TcbEvalDataBasic memory basicData, string memory numbersStr) = tcbEvalHelper
            .parseTcbEvalString(tcbEvaluationDataNumbersStr);

        assertEq(uint8(basicData.id), uint8(TcbId.SGX), "ID mismatch");
        assertEq(basicData.version, 1, "Version mismatch");
        assertEq(basicData.issueDate, 1748832210, "IssueDate mismatch"); // "2025-06-02T02:43:30Z"
        assertEq(basicData.nextUpdate, 1751424210, "NextUpdate mismatch"); // "2025-07-02T02:43:30Z"
        assertEq(keccak256(abi.encodePacked(numbersStr)), keccak256(abi.encodePacked(tcbEvalNumbersArrayStr)), "tcbEvalNumbersString mismatch");
    }

    function test_ParseTcbEvalNumbers() public {
        TcbEvalNumber[] memory parsedNumbers = tcbEvalHelper.parseTcbEvalNumbers(tcbEvalNumbersArrayStr);

        assertEq(parsedNumbers.length, 3, "Parsed numbers array length mismatch");

        // Element 0
        assertEq(parsedNumbers[0].tcbEvaluationDataNumber, 19, "Elem 0: tcbEvaluationDataNumber mismatch");
        assertEq(parsedNumbers[0].tcbRecoveryEventDate, 1747094400, "Elem 0: tcbRecoveryEventDate mismatch"); // "2025-05-13T00:00:00Z"
        assertEq(parsedNumbers[0].tcbDate, 1747180800, "Elem 0: tcbDate mismatch"); // "2025-05-14T00:00:00Z"

        // Element 1
        assertEq(parsedNumbers[1].tcbEvaluationDataNumber, 18, "Elem 1: tcbEvaluationDataNumber mismatch");
        assertEq(parsedNumbers[1].tcbRecoveryEventDate, 1731369600, "Elem 1: tcbRecoveryEventDate mismatch"); // "2024-11-12T00:00:00Z"
        assertEq(parsedNumbers[1].tcbDate, 1731456000, "Elem 1: tcbDate mismatch"); // "2024-11-13T00:00:00Z"

        // Element 2
        assertEq(parsedNumbers[2].tcbEvaluationDataNumber, 17, "Elem 2: tcbEvaluationDataNumber mismatch");
        assertEq(parsedNumbers[2].tcbRecoveryEventDate, 1710201600, "Elem 2: tcbRecoveryEventDate mismatch"); // "2024-03-12T00:00:00Z"
        assertEq(parsedNumbers[2].tcbDate, 1710288000, "Elem 2: tcbDate mismatch"); // "2024-03-13T00:00:00Z"
    }

    function test_EvalNumbersSerialization() public {
        TcbEvalNumber[] memory parsedNumbers = tcbEvalHelper.parseTcbEvalNumbers(tcbEvalNumbersArrayStr);

        bytes memory serializedData = tcbEvalHelper.tcbEvalNumbersToBytes(parsedNumbers);

        TcbEvalNumber[] memory deserializedNumbers = tcbEvalHelper.tcbEvalNumbersFromBytes(serializedData);

        assertEq(deserializedNumbers.length, parsedNumbers.length, "Deserialized numbers length mismatch");

        for (uint256 i = 0; i < parsedNumbers.length; i++) {
            assertEq(
                deserializedNumbers[i].tcbEvaluationDataNumber,
                parsedNumbers[i].tcbEvaluationDataNumber
            );
            assertEq(
                deserializedNumbers[i].tcbRecoveryEventDate,
                parsedNumbers[i].tcbRecoveryEventDate
            );
            assertEq(
                deserializedNumbers[i].tcbDate,
                parsedNumbers[i].tcbDate
            );
        }
    }
}
