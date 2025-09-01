// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CA} from "../Common.sol";
import {
    EnclaveIdentityHelper, EnclaveIdentityJsonObj, EnclaveId, IdentityObj
} from "../helpers/EnclaveIdentityHelper.sol";

import {DaoBase} from "./DaoBase.sol";
import {SigVerifyBase} from "./SigVerifyBase.sol";
import {PcsDao} from "./PcsDao.sol";

/// @notice The on-chain schema for Identity.json is to store as ABI-encoded tuple of (EnclaveIdentityHelper.IdentityObj, EnclaveIdentityHelper.EnclaveIdentityJsonObj)
/// @notice In other words, the tuple simply consists of the collateral in both parsed and string forms.
/// @notice see {{ EnclaveIdentityHelper.IdentityObj }} for struct definition

/**
 * @title Enclave Identity Data Access Object
 * @notice This contract is heavily inspired by Section 4.2.9 in the Intel SGX PCCS Design Guideline
 * https://download.01.org/intel-sgx/sgx-dcap/1.19/linux/docs/SGX_DCAP_Caching_Service_Design_Guide.pdf
 * @dev should extends this contract and use the provided read/write methods to interact with
 * Identity.json data published on-chain.
 */
abstract contract EnclaveIdentityDao is DaoBase, SigVerifyBase {
    PcsDao public Pcs;
    EnclaveIdentityHelper public EnclaveIdentityLib;
    address public crlLibAddr;

    // first 4 bytes of keccak256("ENCLAVE_ID_MAGIC")
    bytes4 constant ENCLAVE_ID_MAGIC = 0xff818fce;

    // 289fa0cb
    error Enclave_Id_Mismatch();
    // 4e0f5696
    error Incorrect_Enclave_Id_Version();
    // 841a0280
    error Missing_TCB_Cert();
    // ea8cd522
    error TCB_Cert_Expired();
    // 7fb57a7a
    error TCB_Cert_Revoked(uint256 serialNum);
    // 8de7233f
    error Invalid_TCB_Cert_Signature();
    // 9ac04499
    error Enclave_Id_Expired();
    // 7a204327
    error Enclave_Id_Out_Of_Date();

    event UpsertedEnclaveIdentity(uint256 indexed id, uint256 indexed version);

    constructor(
        address _resolver,
        address _p256,
        address _pcs,
        address _enclaveIdentityHelper,
        address _x509Helper,
        address _crlLib
    ) DaoBase(_resolver) SigVerifyBase(_p256, _x509Helper) {
        Pcs = PcsDao(_pcs);
        EnclaveIdentityLib = EnclaveIdentityHelper(_enclaveIdentityHelper);
        crlLibAddr = _crlLib;
    }

    function getCollateralValidity(bytes32 key)
        external
        view
        override
        returns (uint64 issueDateTimestamp, uint64 nextUpdateTimestamp)
    {
        (issueDateTimestamp, nextUpdateTimestamp,) = _loadEnclaveIdentityIssueEvaluation(key);
    }

    function getIdentityContentHash(bytes32 key) external view returns (bytes32) {
        return _loadIdentityContentHash(key);
    }

    /**
     * @notice computes the key that is mapped to the collateral attestation ID
     * NOTE: the "version" indicated here is taken from the input parameter (e.g. v3 vs v4);
     * NOT the "version" value found in the Enclave Identity JSON
     * @return key = keccak256(ENCLAVE_ID_MAGIC ++ id ++ version)
     */
    function ENCLAVE_ID_KEY(uint256 id, uint256 version) public pure returns (bytes32 key) {
        key = keccak256(abi.encodePacked(ENCLAVE_ID_MAGIC, id, version));
    }

    /**
     * @notice Section 4.2.9 (getEnclaveIdentity)
     * @notice Gets the enclave identity.
     * @param id 0: QE; 1: QVE; 2: TD_QE
     * https://github.com/intel/SGXDataCenterAttestationPrimitives/blob/39989a42bbbb0c968153a47254b6de79a27eb603/QuoteVerification/QVL/Src/AttestationLibrary/src/Verifiers/EnclaveIdentityV2.h#L49-L52
     * @param version the input version parameter (v3 or v4)
     * @return enclaveIdObj - consisting of the Identity JSON string and the signature.
     *  See {EnclaveIdentityHelper.sol} to learn more about the structure definition
     */
    function getEnclaveIdentity(uint256 id, uint256 version)
        external
        view
        returns (EnclaveIdentityJsonObj memory enclaveIdObj)
    {
        bytes memory attestedIdentityData = _onFetchDataFromResolver(ENCLAVE_ID_KEY(id, version), false);
        if (attestedIdentityData.length > 0) {
            (, enclaveIdObj) = abi.decode(attestedIdentityData, (IdentityObj, EnclaveIdentityJsonObj));
        }
    }

    /**
     * @notice Section 4.2.9 (upsertEnclaveIdentity)
     * @param id 0: QE; 1: QVE; 2: TD_QE
     * https://github.com/intel/SGXDataCenterAttestationPrimitives/blob/39989a42bbbb0c968153a47254b6de79a27eb603/QuoteVerification/QVL/Src/AttestationLibrary/src/Verifiers/EnclaveIdentityV2.h#L49-L52
     * @param version the input version parameter (v3 or v4)
     * @param enclaveIdentityObj enclaveIdObj - consisting of the Identity JSON string and the signature.
     * See {EnclaveIdentityHelper.sol} to learn more about the structure definition
     */
    function upsertEnclaveIdentity(uint256 id, uint256 version, EnclaveIdentityJsonObj calldata enclaveIdentityObj)
        external
        returns (bytes32 attestationId)
    {
        bytes32 key = ENCLAVE_ID_KEY(id, version);
        bytes32 hash = sha256(bytes(enclaveIdentityObj.identityStr));

        _checkCollateralDuplicate(key, hash);

        _validateQeIdentity(enclaveIdentityObj, hash);
        (bytes memory req, bytes32 identityContentHash) =
            _buildEnclaveIdentityAttestationRequest(id, version, key, enclaveIdentityObj);
        attestationId = _attestEnclaveIdentity(req, hash, key);

        _storeIdentityContentHash(key, identityContentHash);

        emit UpsertedEnclaveIdentity(id, version);
    }

    /**
     * @notice Fetches the Enclave Identity issuer chain
     * @return signingCert - DER encoded Intel TCB Signing Certificate
     * @return rootCert - DER encoded Intel SGX Root CA
     */
    function getEnclaveIdentityIssuerChain() external view returns (bytes memory signingCert, bytes memory rootCert) {
        signingCert = _onFetchDataFromResolver(Pcs.PCS_KEY(CA.SIGNING, false), false);
        rootCert = _onFetchDataFromResolver(Pcs.PCS_KEY(CA.ROOT, false), false);
    }

    /**
     * @notice attests collateral via the Resolver
     * @return attestationId
     */
    function _attestEnclaveIdentity(bytes memory reqData, bytes32 hash, bytes32 key)
        internal
        virtual
        returns (bytes32 attestationId)
    {
        (attestationId,) = resolver.attest(key, reqData, hash);
    }

    /**
     * @notice constructs the EnclaveIdentityHelper.IdentityObj attestation data
     */
    function _buildEnclaveIdentityAttestationRequest(
        uint256 id,
        uint256 version,
        bytes32 key,
        EnclaveIdentityJsonObj calldata enclaveIdentityObj
    ) private returns (bytes memory reqData, bytes32 identityContentHash) {
        (IdentityObj memory identity, string memory identityTcbString) =
            EnclaveIdentityLib.parseIdentityString(enclaveIdentityObj.identityStr);
        if (id != uint256(identity.id)) {
            revert Enclave_Id_Mismatch();
        }

        if (id == uint256(EnclaveId.TD_QE) && version != 4 && version != 5) {
            revert Incorrect_Enclave_Id_Version();
        }

        if (block.timestamp < identity.issueDateTimestamp || block.timestamp > identity.nextUpdateTimestamp) {
            revert Enclave_Id_Expired();
        }

        // make sure new collateral is "newer"
        (uint64 existingIssueDateTimestamp,, uint64 existingEvaluationDataNumber) =
            _loadEnclaveIdentityIssueEvaluation(key);
        bool outOfDate = existingEvaluationDataNumber > identity.tcbEvaluationDataNumber
            || existingIssueDateTimestamp >= identity.issueDateTimestamp;
        if (outOfDate) {
            revert Enclave_Id_Out_Of_Date();
        }

        // attest timestamp
        _storeEnclaveIdentityIssueEvaluation(
            key, identity.issueDateTimestamp, identity.nextUpdateTimestamp, identity.tcbEvaluationDataNumber
        );

        reqData = abi.encode(identity, enclaveIdentityObj);
        identityContentHash = EnclaveIdentityLib.getIdentityContentHash(identity, identityTcbString);
    }

    /**
     * @notice validates IdentityString is signed by Intel TCB Signing Cert
     */
    function _validateQeIdentity(EnclaveIdentityJsonObj calldata enclaveIdentityObj, bytes32 hash) private view {
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
            bool sigVerified = verifySignature(hash, enclaveIdentityObj.signature, signingDer);
            if (!sigVerified) {
                revert Invalid_TCB_Cert_Signature();
            }
        } else {
            revert Missing_TCB_Cert();
        }
    }

    /// @dev for the time being, we will require a method to "cache" the issuance timestamp
    /// @dev and the evaluation data number
    /// @dev this reduces the amount of data to read, when performing rollback check
    /// @dev which also allows any caller to check expiration of the Enclave Identity before loading the entire data
    /// @dev the functions defined below can be overridden by the inheriting contract

    function _storeEnclaveIdentityIssueEvaluation(
        bytes32 tcbKey,
        uint64 issueDateTimestamp,
        uint64 nextUpdateTimestamp,
        uint32 evaluationDataNumber
    ) internal virtual;

    function _loadEnclaveIdentityIssueEvaluation(bytes32 tcbKey)
        internal
        view
        virtual
        returns (uint64 issueDateTimestamp, uint64 nextUpdateTimestamp, uint32 evaluationDataNumber);

    /// @dev store time-insensitive content hash

    function _storeIdentityContentHash(bytes32 identityKey, bytes32 contentHash) internal virtual;

    function _loadIdentityContentHash(bytes32 identityKey) internal view virtual returns (bytes32 contentHash);
}
