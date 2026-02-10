// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PcsDao} from "./PcsDao.sol";
import {DaoBase} from "./DaoBase.sol";
import {SigVerifyBase} from "./SigVerifyBase.sol";

import {CA} from "../Common.sol";
import {TcbEvalHelper, TcbEvalJsonObj, TcbEvalDataBasic, TcbEvalNumber, TcbId} from "../helpers/TcbEvalHelper.sol";

/// @notice the on-chain schema of the attested data consists of the ABI-encoded tuple:
/// @notice (TcbEvalDataBasic, TcbEvalJsonObj)
/// - ABI-encoded TcbEvalHelper.TcbEvalDataBasic
/// - ABI-encoded of TcbEvalJsonObj - the JSON string representation of TCB Evaluation Data Numbers collateral
///
/// @notice See {{ TcbEvalHelper.sol }} to learn more about TCB Evaluation Data Numbers related struct definitions.

/**
 * @title TCB Evaluation Data Access Object
 * @notice This contract handles TCB Evaluation Data Numbers equivalent to Intel's /tcbevaluationdatanumbers API endpoint
 * @dev should extends this contract and use the provided read/write methods to interact with TCB Evaluation Data Numbers JSON
 * data published on-chain.
 */
abstract contract TcbEvalDao is DaoBase, SigVerifyBase {
    PcsDao public Pcs;
    TcbEvalHelper public TcbEvalLib;
    address public crlLibAddr;

    // first 4 bytes of keccak256("TCB_EVAL_MAGIC")
    bytes4 constant TCB_EVAL_MAGIC = 0xbebc7284;

    uint64 constant TWELFTH_MONTHS_SECONDS = 31557600; // 365.25 days in seconds

    // c9220efa
    error Missing_TCB_Eval_Cert();
    // 925ca6d8
    error TCB_Eval_Cert_Expired();
    // 49c53e1e
    error TCB_Eval_Cert_Revoked(uint256 serialNum);
    // eca8017e
    error Invalid_TCB_Eval_Cert_Signature();
    // c750d267
    error TCB_Eval_Expired();
    // 9ddee474
    error TCB_Eval_Out_Of_Date();
    // fe17888f
    error TCB_Eval_Missing(TcbId id);

    event UpsertedTcbEval(uint8 indexed tcbId);

    constructor(
        address _resolver,
        address _p256,
        address _pcs,
        address _tcbEvalHelper,
        address _x509Helper,
        address _crlLib
    ) SigVerifyBase(_p256, _x509Helper) DaoBase(_resolver) {
        Pcs = PcsDao(_pcs);
        TcbEvalLib = TcbEvalHelper(_tcbEvalHelper);
        crlLibAddr = _crlLib;
    }

    function getCollateralValidity(bytes32 key)
        external
        view
        override
        returns (uint64 issueDateTimestamp, uint64 nextUpdateTimestamp)
    {
        (issueDateTimestamp, nextUpdateTimestamp) = _loadTcbEvalIssueData(key);
    }

    /**
     * @notice computes the key that is mapped to the collateral attestation ID
     * @return key = keccak256(TCB_EVAL_MAGIC ++ id)
     */
    function TCB_EVAL_KEY(TcbId id) public view virtual returns (bytes32 key) {
        key = keccak256(abi.encodePacked(TCB_EVAL_MAGIC, id));
    }

    /**
     * @notice Queries the full TCB Evaluation Data JSON Object for the given TEE type
     * @param id TEE type - "SGX" or "TDX"
     * @return tcbEvalObj See {TcbEvalHelper.sol} to learn more about the structure definition
     */
    function getTcbEvaluationObject(TcbId id) external view returns (TcbEvalJsonObj memory tcbEvalObj) {
        (,, tcbEvalObj) = _getTcbEvaluationDataNumbers(id);
    }

    /**
     * @notice Queries the TCB Evaluation Data Numbers for the given TEE type
     * @param id TCB ID - "SGX" or "TDX"
     * @return tcbEvalDataNumbers An array of TCB Evaluation Data Numbers that are actively supported
     */
    function getTcbEvaluationDataNumbers(TcbId id) external view returns (uint256[] memory tcbEvalDataNumbers) {
        (, TcbEvalNumber[] memory tcbEvalNumbersArr, ) = _getTcbEvaluationDataNumbers(id);
        uint256 len = tcbEvalNumbersArr.length;
        tcbEvalDataNumbers = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            tcbEvalDataNumbers[i] = tcbEvalNumbersArr[i].tcbEvaluationDataNumber;
        }
    }

    function early(TcbId id) external view returns (uint32 tcbEvaluationNumber) {
        (, TcbEvalNumber[] memory tcbEvalNumbers,) = _getTcbEvaluationDataNumbers(id);
        tcbEvaluationNumber = tcbEvalNumbers[0].tcbEvaluationDataNumber;
    }

    function standard(TcbId id) external view returns (uint32 tcbEvaluationNumber) {
        (, TcbEvalNumber[] memory tcbEvalNumbers,) = _getTcbEvaluationDataNumbers(id);
        uint256 len = tcbEvalNumbers.length;
        for (uint256 i = 0; i < len; i++) {
            // the standard TCB Evaluation Data Number is the highest one that is at least 12 months old
            if (block.timestamp - tcbEvalNumbers[i].tcbRecoveryEventDate >= TWELFTH_MONTHS_SECONDS) {
                tcbEvaluationNumber = tcbEvalNumbers[i].tcbEvaluationDataNumber;
                break;
            }
        }
    }

    /**
     * @notice Upserts TCB Evaluation Data Numbers
     * @param tcbEvalObj See {TcbEvalHelper.sol} to learn more about the structure definition
     */
    function upsertTcbEvaluationData(TcbEvalJsonObj calldata tcbEvalObj) external returns (bytes32 attestationId) {
        bytes32 hash = sha256(bytes(tcbEvalObj.tcbEvaluationDataNumbers));

        // Parse TCB evaluation data to get basic info for key computation
        (TcbEvalDataBasic memory tcbEvalData, string memory tcbEvalNumbersString) =
            TcbEvalLib.parseTcbEvalString(tcbEvalObj.tcbEvaluationDataNumbers);

        bytes32 key = TCB_EVAL_KEY(tcbEvalData.id);

        _checkCollateralDuplicate(key, hash);
        _validateTcbEvalData(tcbEvalObj);

        bytes memory req = _buildTcbEvalAttestationRequest(key, tcbEvalObj, tcbEvalData, tcbEvalNumbersString);

        attestationId = _attestTcbEval(req, hash, key);

        _storeTcbEvalIssueData(key, tcbEvalData.issueDate, tcbEvalData.nextUpdate);
        emit UpsertedTcbEval(uint8(tcbEvalData.id));
    }

    /**
     * @notice Fetches the TCB Evaluation Data Issuer Chain
     * @return signingCert - DER encoded Intel TCB Signing Certificate
     * @return rootCert - DER encoded Intel SGX Root CA
     */
    function getTcbEvalIssuerChain() external view returns (bytes memory signingCert, bytes memory rootCert) {
        signingCert = _onFetchDataFromResolver(Pcs.PCS_KEY(CA.SIGNING, false), false);
        rootCert = _onFetchDataFromResolver(Pcs.PCS_KEY(CA.ROOT, false), false);
    }

    function _getTcbEvaluationDataNumbers(TcbId id)
        private
        view
        returns (
            TcbEvalDataBasic memory tcbEvalData,
            TcbEvalNumber[] memory tcbEvalNumbers,
            TcbEvalJsonObj memory tcbEvalObj
        )
    {
        bytes memory attestedTcbEvalData = _onFetchDataFromResolver(TCB_EVAL_KEY(id), false);
        if (attestedTcbEvalData.length == 0) {
            revert TCB_Eval_Missing(id);
        } else {
            bytes memory encodedTcbEvalNumbers;
            (tcbEvalData, encodedTcbEvalNumbers, tcbEvalObj) =
                abi.decode(attestedTcbEvalData, (TcbEvalDataBasic, bytes, TcbEvalJsonObj));
            tcbEvalNumbers = TcbEvalLib.tcbEvalNumbersFromBytes(encodedTcbEvalNumbers);
        }
    }

    /**
     * @notice attests collateral via the Resolver
     * @return attestationId
     */
    function _attestTcbEval(bytes memory reqData, bytes32 hash, bytes32 key)
        internal
        virtual
        returns (bytes32 attestationId)
    {
        (attestationId,) = resolver.attest(key, reqData, hash);
    }

    /**
     * @notice constructs the TCB Evaluation Data attestation data
     */
    function _buildTcbEvalAttestationRequest(
        bytes32 key,
        TcbEvalJsonObj calldata tcbEvalObj,
        TcbEvalDataBasic memory tcbEvalData,
        string memory tcbEvalNumbersString
    ) private view returns (bytes memory reqData) {
        // Check expiration before continuing
        if (block.timestamp < tcbEvalData.issueDate || block.timestamp > tcbEvalData.nextUpdate) {
            revert TCB_Eval_Expired();
        }

        // Make sure new collateral is "newer"
        (uint64 existingIssueDate,) = _loadTcbEvalIssueData(key);
        if (existingIssueDate > 0) {
            // New data must have a later issue date to be considered newer
            bool outOfDate = tcbEvalData.issueDate <= existingIssueDate;
            if (outOfDate) {
                revert TCB_Eval_Out_Of_Date();
            }
        }

        // Parse the TCB evaluation numbers array
        TcbEvalNumber[] memory tcbEvalNumbers = TcbEvalLib.parseTcbEvalNumbers(tcbEvalNumbersString);
        bytes memory encodedNumbers = TcbEvalLib.tcbEvalNumbersToBytes(tcbEvalNumbers);

        reqData = abi.encode(tcbEvalData, encodedNumbers, tcbEvalObj);
    }

    function _validateTcbEvalData(TcbEvalJsonObj calldata tcbEvalObj) private view {
        // Check issuer expiration - use Intel TCB Signing CA (CA.SIGNING)
        bytes32 issuerKey = Pcs.PCS_KEY(CA.SIGNING, false);
        (uint256 issuerNotValidBefore, uint256 issuerNotValidAfter) = Pcs.getCollateralValidity(issuerKey);
        if (block.timestamp < issuerNotValidBefore || block.timestamp > issuerNotValidAfter) {
            revert TCB_Eval_Cert_Expired();
        }

        bytes memory signingDer = _fetchDataFromResolver(issuerKey, false);
        if (signingDer.length > 0) {
            bytes memory rootCrl = _fetchDataFromResolver(Pcs.PCS_KEY(CA.ROOT, true), false);
            if (rootCrl.length > 0) {
                // Check revocation
                (, bytes memory serialNumberData) = x509.staticcall(
                    abi.encodeWithSelector(
                        0xb29b51cb, // X509Helper.getSerialNumber(bytes)
                        signingDer
                    )
                );
                uint256 serialNumber = abi.decode(serialNumberData, (uint256));
                (, bytes memory serialNumberRevokedData) = crlLibAddr.staticcall(
                    abi.encodeWithSelector(
                        0xcedb9781, // X509CRLHelper.serialNumberIsRevoked(uint256,bytes)
                        serialNumber,
                        rootCrl
                    )
                );
                bool revoked = abi.decode(serialNumberRevokedData, (bool));
                if (revoked) {
                    revert TCB_Eval_Cert_Revoked(serialNumber);
                }
            }

            // Validate signature
            bool sigVerified =
                verifySignature(sha256(bytes(tcbEvalObj.tcbEvaluationDataNumbers)), tcbEvalObj.signature, signingDer);
            if (!sigVerified) {
                revert Invalid_TCB_Eval_Cert_Signature();
            }
        } else {
            revert Missing_TCB_Eval_Cert();
        }
    }

    /// @dev for the time being, we will require a method to "cache" the TCB evaluation data issued timestamp
    /// @dev this reduces the amount of data to read, when performing rollback check
    /// @dev which also allows any caller to check expiration of TCB Evaluation Data before loading the entire data
    /// @dev the functions defined below can be overridden by the inheriting contract

    function _storeTcbEvalIssueData(bytes32 tcbEvalKey, uint64 issueDateTimestamp, uint64 nextUpdateTimestamp)
        internal
        virtual;

    function _loadTcbEvalIssueData(bytes32 tcbEvalKey)
        internal
        view
        virtual
        returns (uint64 issueDateTimestamp, uint64 nextUpdateTimestamp);
}
