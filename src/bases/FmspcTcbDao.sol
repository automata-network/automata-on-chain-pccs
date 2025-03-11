// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PcsDao} from "./PcsDao.sol";
import {DaoBase} from "./DaoBase.sol";
import {SigVerifyBase} from "./SigVerifyBase.sol";

import {CA} from "../Common.sol";
import {
    FmspcTcbHelper,
    TcbInfoJsonObj,
    TcbId,
    TcbInfoBasic,
    TCBLevelsObj,
    TDXModule,
    TDXModuleIdentity
} from "../helpers/FmspcTcbHelper.sol";

/// @notice the on-chain schema of the attested data is dependent on the version of TCBInfo:
/// @notice For TCBInfoV2, it consists of the ABI-encoded tuple of the following values:
///
/// @notice (TcbInfoBasic, TCBLevelsObj[], TcbInfoJsonObj
/// - ABI-encoded TcbHelper.TcbInfoBasic
/// - serialized TCBLevelsObj bytes as implemented in TcbHelper.tcbLevelsObjToBytes()
/// - ABI-encoded of TcbInfoJsonObj - the JSON string representation of TCBInfo collateral
///
/// @notice For TCBInfoV3, it consists of the abi-encoded tuple of:
/// @notice (TcbInfoBasic, TDXModule, TDXModuleIdentity[], TCBLevelsObj, TcbInfoJsonObj)
/// - ABI-encoded TcbHelper.TcbInfoBasic
/// - ABI-encoded TcbHelper.TDXModule
/// - serialized TDXModuleIdentity bytes as implemented in TcbHelper.tdxModuleIdentityToBytes()
/// - serialized TCBLevelsObj bytes as implemented in TcbHelper.tcbLevelsObjToBytes()
/// - ABI-encoded of TcbInfoJsonObj - the JSON string representation of TCBInfo collateral
///
/// @notice the serializers for TCBLevelsObj and TDXModuleIdentity[] are opted over ABI-encoding to significantly
/// reduce gas costs.
///
/// @notice See {{ FmspcTcbHelper.sol }} to learn more about FMSPC TCB related struct definitions.

/**
 * @title FMSPC TCB Data Access Object
 * @notice This contract is heavily inspired by Section 4.2.3 in the Intel SGX PCCS Design Guidelines
 * https://download.01.org/intel-sgx/sgx-dcap/1.19/linux/docs/SGX_DCAP_Caching_Service_Design_Guide.pdf
 * @dev should extends this contract and use the provided read/write methods to interact with TCBInfo JSON
 * data published on-chain.
 */
abstract contract FmspcTcbDao is DaoBase, SigVerifyBase {
    PcsDao public Pcs;
    FmspcTcbHelper public FmspcTcbLib;
    address public crlLibAddr;

    // first 4 bytes of FMSPC_TCB_MAGIC
    bytes4 constant FMSPC_TCB_MAGIC = 0xbb69b29c;

    // 841a0280
    error Missing_TCB_Cert();
    // ea8cd522
    error TCB_Cert_Expired();
    // 7fb57a7a
    error TCB_Cert_Revoked(uint256 serialNum);
    // 8de7233f
    error Invalid_TCB_Cert_Signature();
    // bae57649
    error TCB_Expired();
    // 3d78f9f9
    error TCB_Out_Of_Date();

    event UpsertedFmpscTcb(uint8 indexed tcbType, bytes6 indexed fmspcTcbBytes, uint32 indexed version);

    constructor(
        address _resolver,
        address _p256,
        address _pcs,
        address _fmspcHelper,
        address _x509Helper,
        address _crlLib
    ) SigVerifyBase(_p256, _x509Helper) DaoBase(_resolver) {
        Pcs = PcsDao(_pcs);
        FmspcTcbLib = FmspcTcbHelper(_fmspcHelper);
        crlLibAddr = _crlLib;
    }

    function getCollateralValidity(bytes32 key)
        external
        view
        override
        returns (uint64 issueDateTimestamp, uint64 nextUpdateTimestamp)
    {
        (issueDateTimestamp, nextUpdateTimestamp,) = _loadTcbInfoIssueEvaluation(key);
    }

    function getTcbInfoContentHash(bytes32 key) external view returns (bytes32) {
        return _loadFmspcTcbContentHash(key);
    }

    /**
     * @notice computes the key that is mapped to the collateral attestation ID
     * @return key = keccak256(type ++ FMSPC ++ version)
     */
    function FMSPC_TCB_KEY(uint8 tcbType, bytes6 fmspc, uint32 version) public pure returns (bytes32 key) {
        key = keccak256(abi.encodePacked(FMSPC_TCB_MAGIC, tcbType, fmspc, version));
    }

    /**
     * @notice Section 4.2.3 (getTcbInfo)
     * @notice Queries TCB Info for the given FMSPC
     * @param tcbType 0: SGX, 1: TDX
     * https://github.com/intel/SGXDataCenterAttestationPrimitives/blob/39989a42bbbb0c968153a47254b6de79a27eb603/QuoteVerification/QVL/Src/AttestationParsers/src/Json/TcbInfo.cpp#L46-L47
     * @param fmspc FMSPC
     * @param version v2 or v3
     * https://github.com/intel/SGXDataCenterAttestationPrimitives/blob/39989a42bbbb0c968153a47254b6de79a27eb603/QuoteVerification/QVL/Src/AttestationParsers/include/SgxEcdsaAttestation/AttestationParsers.h#L241-L248
     * @return tcbObj See {FmspcTcbHelper.sol} to learn more about the structure definition
     */
    function getTcbInfo(uint256 tcbType, string calldata fmspc, uint256 version)
        external
        view
        returns (TcbInfoJsonObj memory tcbObj)
    {
        bytes6 fmspcBytes = bytes6(uint48(_parseUintFromHex(fmspc)));
        bytes memory attestedTcbData =
            _onFetchDataFromResolver(FMSPC_TCB_KEY(uint8(tcbType), fmspcBytes, uint32(version)), false);
        if (attestedTcbData.length > 0) {
            if (version < 3) {
                (,, tcbObj) = abi.decode(attestedTcbData, (TcbInfoBasic, bytes, TcbInfoJsonObj));
            } else {
                (,,,, tcbObj) = abi.decode(attestedTcbData, (TcbInfoBasic, TDXModule, bytes, bytes, TcbInfoJsonObj));
            }
        }
    }

    /**
     * @notice Section 4.2.9 (upsertEnclaveIdentity)
     * @param tcbInfoObj See {FmspcTcbHelper.sol} to learn more about the structure definition
     */
    function upsertFmspcTcb(TcbInfoJsonObj calldata tcbInfoObj) external returns (bytes32 attestationId) {
        bytes32 hash = sha256(bytes(tcbInfoObj.tcbInfoStr));

        // parse tcb info basic here so we can compute the key
        (
            TcbInfoBasic memory tcbInfo,
            string memory tcbLevelsString,
            string memory tdxModuleString,
            string memory tdxModuleIdentitiesString
        ) = FmspcTcbLib.parseTcbString(tcbInfoObj.tcbInfoStr);

        bytes32 key = FMSPC_TCB_KEY(uint8(tcbInfo.id), tcbInfo.fmspc, tcbInfo.version);

        _checkCollateralDuplicate(key, hash);
        _validateTcbInfo(tcbInfoObj);

        (bytes memory req, bytes32 contentHash) = _buildTcbAttestationRequest(
            key, tcbInfoObj, tcbInfo, tcbLevelsString, tdxModuleString, tdxModuleIdentitiesString
        );

        attestationId = _attestTcb(req, hash, key);

        _storeTcbInfoIssueEvaluation(key, tcbInfo.issueDate, tcbInfo.nextUpdate, tcbInfo.evaluationDataNumber);
        _storeFmspcTcbContentHash(key, contentHash);
        emit UpsertedFmpscTcb(uint8(tcbInfo.id), tcbInfo.fmspc, tcbInfo.version);
    }

    /**
     * @notice Fetches the TCBInfo Issuer Chain
     * @return signingCert - DER encoded Intel TCB Signing Certificate
     * @return rootCert - DER encoded Intel SGX Root CA
     */
    function getTcbIssuerChain() external view returns (bytes memory signingCert, bytes memory rootCert) {
        signingCert = _onFetchDataFromResolver(Pcs.PCS_KEY(CA.SIGNING, false), false);
        rootCert = _onFetchDataFromResolver(Pcs.PCS_KEY(CA.ROOT, false), false);
    }

    /**
     * @notice attests collateral via the Resolver
     * @return attestationId
     */
    function _attestTcb(bytes memory reqData, bytes32 hash, bytes32 key)
        internal
        virtual
        returns (bytes32 attestationId)
    {
        (attestationId,) = resolver.attest(key, reqData, hash);
    }

    /**
     * @notice constructs the TcbInfo.json attestation data
     */
    function _buildTcbAttestationRequest(
        bytes32 key,
        TcbInfoJsonObj calldata tcbInfoObj,
        TcbInfoBasic memory tcbInfo,
        string memory tcbLevelsString,
        string memory tdxModuleString,
        string memory tdxModuleIdentitiesString
    ) private view returns (bytes memory reqData, bytes32 contentHash) {
        // check expiration before continuing...
        if (block.timestamp < tcbInfo.issueDate || block.timestamp > tcbInfo.nextUpdate) {
            revert TCB_Expired();
        }

        // Make sure new collateral is "newer"
        (uint64 existingIssueDate,, uint32 existingEvaluationDataNumber) = _loadTcbInfoIssueEvaluation(key);
        if (existingIssueDate > 0) {
            /// I don't think there can be a scenario where an existing tcbinfo with a higher evaluation data number
            /// to be issued BEFORE a new tcbinfo with a lower evaluation data number
            bool outOfDate =
                tcbInfo.evaluationDataNumber < existingEvaluationDataNumber || tcbInfo.issueDate <= existingIssueDate;
            if (outOfDate) {
                revert TCB_Out_Of_Date();
            }
        }

        TCBLevelsObj[] memory tcbLevels = FmspcTcbLib.parseTcbLevels(tcbInfo.version, tcbLevelsString);
        bytes memory encodedTcbLevels = _encodeTcbLevels(tcbLevels);
        if (tcbInfo.version < 3) {
            reqData = abi.encode(tcbInfo, encodedTcbLevels, tcbInfoObj);
        } else {
            TDXModule memory module;
            TDXModuleIdentity[] memory moduleIdentities;
            bytes memory encodedModuleIdentities;
            if (tcbInfo.id == TcbId.TDX) {
                (module, moduleIdentities) = FmspcTcbLib.parseTcbTdxModules(tdxModuleString, tdxModuleIdentitiesString);
                encodedModuleIdentities = _encodeTdxModuleIdentities(moduleIdentities);
            }
            reqData = abi.encode(tcbInfo, module, encodedModuleIdentities, encodedTcbLevels, tcbInfoObj);
        }

        contentHash = FmspcTcbLib.generateFmspcTcbContentHash(
            tcbInfo, tcbLevelsString, tdxModuleString, tdxModuleIdentitiesString
        );
    }

    function _validateTcbInfo(TcbInfoJsonObj calldata tcbInfoObj) private view {
        // check issuer expiration
        bytes32 issuerKey = Pcs.PCS_KEY(CA.SIGNING, false);
        (uint256 issuerNotValidBefore, uint256 issuerNotValidAfter) = Pcs.getCollateralValidity(issuerKey);
        if (block.timestamp < issuerNotValidBefore || block.timestamp > issuerNotValidAfter) {
            revert TCB_Cert_Expired();
        }

        bytes memory signingDer = _fetchDataFromResolver(issuerKey, false);
        if (signingDer.length > 0) {
            bytes memory rootCrl = _fetchDataFromResolver(Pcs.PCS_KEY(CA.ROOT, true), false);
            if (rootCrl.length > 0) {
                // check revocation
                (, bytes memory serialNumberData) = x509.staticcall(
                    abi.encodeWithSelector(
                        0xb29b51cb, // X509Helper.getSerialNumber(bytes)
                        signingDer
                    )
                );
                uint256 serialNumber = abi.decode(serialNumberData, (uint256));
                (, bytes memory serialNumberRevokedData) = crlLibAddr.staticcall(
                    abi.encodeWithSelector(
                        0xcedb9781, // X508CRLHelper.serialNumberIsRevoked(uint256,bytes)
                        serialNumber,
                        rootCrl
                    )
                );
                bool revoked = abi.decode(serialNumberRevokedData, (bool));
                if (revoked) {
                    revert TCB_Cert_Revoked(serialNumber);
                }
            }

            // Validate signature
            bool sigVerified = verifySignature(sha256(bytes(tcbInfoObj.tcbInfoStr)), tcbInfoObj.signature, signingDer);
            if (!sigVerified) {
                revert Invalid_TCB_Cert_Signature();
            }
        } else {
            revert Missing_TCB_Cert();
        }
    }

    function _encodeTcbLevels(TCBLevelsObj[] memory tcbLevels) private view returns (bytes memory encoded) {
        uint256 n = tcbLevels.length;
        bytes[] memory arr = new bytes[](n);

        for (uint256 i = 0; i < n;) {
            arr[i] = FmspcTcbLib.tcbLevelsObjToBytes(tcbLevels[i]);

            unchecked {
                i++;
            }
        }

        encoded = abi.encode(arr);
    }

    function _encodeTdxModuleIdentities(TDXModuleIdentity[] memory tdxModuleIdentities)
        private
        view
        returns (bytes memory encoded)
    {
        uint256 n = tdxModuleIdentities.length;
        bytes[] memory arr = new bytes[](n);

        for (uint256 i = 0; i < n;) {
            arr[i] = FmspcTcbLib.tdxModuleIdentityToBytes(tdxModuleIdentities[i]);

            unchecked {
                i++;
            }
        }

        encoded = abi.encode(arr);
    }

    /// @dev for the time being, we will require a method to "cache" the tcbinfo issued timestamp
    /// @dev and the evaluation data number
    /// @dev this reduces the amount of data to read, when performing rollback check
    /// @dev which also allows any caller to check expiration of TCBInfo before loading the entire data
    /// @dev the functions defined below can be overridden by the inheriting contract

    function _storeTcbInfoIssueEvaluation(
        bytes32 tcbKey,
        uint64 issueDateTimestamp,
        uint64 nextUpdateTimestamp,
        uint32 evaluationDataNumber
    ) internal virtual;

    function _loadTcbInfoIssueEvaluation(bytes32 tcbKey)
        internal
        view
        virtual
        returns (uint64 issueDateTimestamp, uint64 nextUpdateTimestamp, uint32 evaluationDataNumber);

    /// @dev store time-insensitive content hash

    function _storeFmspcTcbContentHash(bytes32 tcbKey, bytes32 contentHash) internal virtual;

    function _loadFmspcTcbContentHash(bytes32 tcbKey) internal view virtual returns (bytes32 contentHash);
}
