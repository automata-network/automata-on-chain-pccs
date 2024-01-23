// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CA, AttestationRequestData, AttestationRequest} from "../Common.sol";
import {PcsDao} from "./PcsDao.sol";

import {EnclaveIdentityHelper, EnclaveIdentityJsonObj, EnclaveId} from "../helper/EnclaveIdentityHelper.sol";

/**
 * @title Enclave Identity Data Access Object
 * @notice This contract is heavily inspired by Section 4.2.9 in the Intel SGX PCCS Design Guideline
 * https://download.01.org/intel-sgx/sgx-dcap/1.19/linux/docs/SGX_DCAP_Caching_Service_Design_Guide.pdf
 * @dev should extends this contract and use the provided read/write methods to interact with Enclave
 * Identity JSON data published on-chain.
 */

abstract contract EnclaveIdentityDao {
    PcsDao public Pcs;
    EnclaveIdentityHelper public EnclaveIdentityLib;

    /// @notice retrieves the attested EnclaveIdentity from the registry
    /// key: keccak256(id ++ version)
    /// NOTE: the "version" indicated here is taken from the input parameter (e.g. v3 vs v4);
    /// NOT the "version" value found in the Enclave Identity JSON
    ///
    /// @notice the schema of the attested data is the following:
    /// A tuple of (uint256, uint256, string, bytes)
    /// - uint256 issueDateTimestamp
    /// - uint256 nextUpdateTimestamp
    /// - string identity json blob
    /// - bytes signature
    mapping(bytes32 => bytes32) public enclaveIdentityAttestations;

    event EnclaveIdentityMissing(uint256 id, uint256 version);

    error Enclave_Id_Mismatch();

    constructor(address _pcs, address _enclaveIdentityHelper) {
        Pcs = PcsDao(_pcs);
        EnclaveIdentityLib = EnclaveIdentityHelper(_enclaveIdentityHelper);
    }

    /**
     * @notice Section 4.2.9 (getEnclaveIdentity)
     * @notice Gets the enclave identity.
     * @param id 0: QE; 1: QVE; 2: TD_QE
     * https://github.com/intel/SGXDataCenterAttestationPrimitives/blob/39989a42bbbb0c968153a47254b6de79a27eb603/QuoteVerification/QVL/Src/AttestationLibrary/src/Verifiers/EnclaveIdentityV2.h#L49-L52
     * @param version the input version parameter
     * @return enclaveIdObj See {EnclaveIdentityHelper.sol} to learn more about the structure definition
     */
    function getEnclaveIdentity(uint256 id, uint256 version)
        external
        returns (EnclaveIdentityJsonObj memory enclaveIdObj)
    {
        bytes32 attestationId = _getAttestationId(id, version);
        if (attestationId == bytes32(0)) {
            emit EnclaveIdentityMissing(id, version);
        } else {
            bytes memory attestedIdentityData = _getAttestedData(attestationId);
            (,, enclaveIdObj.identityStr, enclaveIdObj.signature) =
                abi.decode(attestedIdentityData, (uint256, uint256, string, bytes));
        }
    }

    /// @question is there a way we can validate the version input?
    /// TEMP: Currently, there is no way to quickly distinguish between QuoteV3 vs QuoteV4 Enclave Identity
    /// TODO: The JSON schema for the tcbLevel object is different between V3 and V4, so we might need
    /// to implement methods to "detect" the JSON schema, as a way of determining whether to assign for V3 or V4 quotes.

    /**
     * @notice Section 4.2.9 (upsertEnclaveIdentity)
     * @dev Attestation Registry Entrypoint Contracts, such as Portals on Verax are responsible
     * @dev for performing ECDSA verification on the provided Enclave Identity
     * against the Signing CA key prior to attestations
     * @param id 0: QE; 1: QVE; 2: TD_QE
     * https://github.com/intel/SGXDataCenterAttestationPrimitives/blob/39989a42bbbb0c968153a47254b6de79a27eb603/QuoteVerification/QVL/Src/AttestationLibrary/src/Verifiers/EnclaveIdentityV2.h#L49-L52
     * @param version the input version parameter
     * @param enclaveIdentityObj See {EnclaveIdentityHelper.sol} to learn more about the structure definition
     */
    function upsertEnclaveIdentity(uint256 id, uint256 version, EnclaveIdentityJsonObj calldata enclaveIdentityObj)
        external
        returns (bytes32 attestationId)
    {
        AttestationRequest memory req = _buildEnclaveIdentityAttestationRequest(id, version, enclaveIdentityObj);
        attestationId = _attestEnclaveIdentity(req);
        enclaveIdentityAttestations[keccak256(abi.encodePacked(id, version))] = attestationId;
    }

    /**
     * @notice Fetches the Enclave Identity issuer chain
     * @return signingCert - DER encoded Intel TCB Signing Certificate
     * @return rootCert - DER encoded Intel SGX Root CA
     */
    function getEnclaveIdentityIssuerChain() public view returns (bytes memory signingCert, bytes memory rootCert) {
        bytes32 signingCertAttestationId = Pcs.pcsCertAttestations(CA.SIGNING);
        bytes32 rootCertAttestationId = Pcs.pcsCertAttestations(CA.ROOT);
        signingCert = _getAttestedData(signingCertAttestationId);
        rootCert = _getAttestedData(rootCertAttestationId);
    }

    /**
     * @dev overwrite this method to define the schemaID for the attestation of Enclave Identities
     */
    function enclaveIdentitySchemaID() public view virtual returns (bytes32 ENCLAVE_IDENTITY_SCHEMA_ID);

    /**
     * @dev implement logic to validate and attest the enclave identity
     * @param req structure as defined by EAS
     * https://github.com/ethereum-attestation-service/eas-contracts/blob/52af661748bde9b40ae782907702f885852bc149/contracts/IEAS.sol#L9C1-L23C2
     * @return attestationId
     */
    function _attestEnclaveIdentity(AttestationRequest memory req) internal virtual returns (bytes32 attestationId);

    /**
     * @dev implement getter logic to retrieve attestation data
     * @param attestationId maps to the data
     */
    function _getAttestedData(bytes32 attestationId) internal view virtual returns (bytes memory attestationData);

    /**
     * @notice computes the key that maps to the corresponding attestation ID
     */
    function _getAttestationId(uint256 id, uint256 version) private view returns (bytes32 attestationId) {
        attestationId = enclaveIdentityAttestations[keccak256(abi.encodePacked(id, version))];
    }

    /**
     * @notice builds an EAS compliant attestation request
     */
    function _buildEnclaveIdentityAttestationRequest(
        uint256 id,
        uint256 version,
        EnclaveIdentityJsonObj calldata enclaveIdentityObj
    ) private view returns (AttestationRequest memory req) {
        bytes32 predecessorAttestationId = _getAttestationId(id, version);
        (uint256 issueDate, uint256 nextUpdate, EnclaveId retId) =
            EnclaveIdentityLib.getIdentitySummary(enclaveIdentityObj.identityStr);
        if (id != uint256(retId)) {
            revert Enclave_Id_Mismatch();
        }
        bytes memory attestationData =
            abi.encode(issueDate, nextUpdate, enclaveIdentityObj.identityStr, enclaveIdentityObj.signature);
        AttestationRequestData memory reqData = AttestationRequestData({
            recipient: msg.sender,
            expirationTime: 0,
            revocable: true,
            refUID: predecessorAttestationId,
            data: attestationData,
            value: 0
        });
        req = AttestationRequest({schema: enclaveIdentitySchemaID(), data: reqData});
    }
}
