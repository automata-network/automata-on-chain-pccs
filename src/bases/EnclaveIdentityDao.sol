// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CA, AttestationRequestData, AttestationRequest} from "../Common.sol";
import {
    EnclaveIdentityHelper, EnclaveIdentityJsonObj, EnclaveId, IdentityObj
} from "../helpers/EnclaveIdentityHelper.sol";

import {DaoBase} from "./DaoBase.sol";
import {SigVerifyBase} from "./SigVerifyBase.sol";
import {PcsDao} from "./PcsDao.sol";

/**
 * @title Enclave Identity Data Access Object
 * @notice This contract is heavily inspired by Section 4.2.9 in the Intel SGX PCCS Design Guideline
 * https://download.01.org/intel-sgx/sgx-dcap/1.19/linux/docs/SGX_DCAP_Caching_Service_Design_Guide.pdf
 * @dev should extends this contract and use the provided read/write methods to interact with Enclave
 * Identity JSON data published on-chain.
 */
abstract contract EnclaveIdentityDao is DaoBase, SigVerifyBase {
    PcsDao public Pcs;
    EnclaveIdentityHelper public EnclaveIdentityLib;

    /// @notice retrieves the attestationId of the attested EnclaveIdentity from the registry
    /// key: keccak256(id ++ version)
    /// NOTE: the "version" indicated here is taken from the input parameter (e.g. v3 vs v4);
    /// NOT the "version" value found in the Enclave Identity JSON
    ///
    /// @notice the schema of the attested data is the following:
    /// An ABI-encoded tuple of (EnclaveIdentityHelper.IdentityObj, string, bytes)
    /// see {{ EnclaveIdentityHelper.IdentityObj }} for struct definition
    /// - string qeidentityObj
    /// - bytes signature
    mapping(bytes32 => bytes32) public enclaveIdentityAttestations;

    error Enclave_Id_Mismatch();
    error Invalid_TCB_Cert_Signature();
    error Enclave_Id_Expired();

    constructor(address _pcs, address _enclaveIdentityHelper, address _x509Helper) SigVerifyBase(_x509Helper) {
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
        view
        returns (EnclaveIdentityJsonObj memory enclaveIdObj)
    {
        bytes32 attestationId = _getAttestationId(id, version);
        if (attestationId != bytes32(0)) {
            bytes memory attestedIdentityData = getAttestedData(attestationId);
            (, enclaveIdObj.identityStr, enclaveIdObj.signature) =
                abi.decode(attestedIdentityData, (IdentityObj, string, bytes));
        }
    }

    /// @question is there a way we can validate the version input?
    /// TEMP: Currently, there is no way to quickly distinguish between QuoteV3 vs QuoteV4 Enclave Identity

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
        _validateQeIdentity(enclaveIdentityObj);
        AttestationRequest memory req = _buildEnclaveIdentityAttestationRequest(id, version, enclaveIdentityObj);
        bytes32 hash = sha256(bytes(enclaveIdentityObj.identityStr));
        attestationId = _attestEnclaveIdentity(req, hash);
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
        signingCert = getAttestedData(signingCertAttestationId);
        rootCert = getAttestedData(rootCertAttestationId);
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
    function _attestEnclaveIdentity(AttestationRequest memory req, bytes32 hash)
        internal
        virtual
        returns (bytes32 attestationId);

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
        IdentityObj memory identity = EnclaveIdentityLib.parseIdentityString(enclaveIdentityObj.identityStr);
        if (id != uint256(identity.id)) {
            revert Enclave_Id_Mismatch();
        }

        if (block.timestamp < identity.issueDateTimestamp || block.timestamp > identity.nextUpdateTimestamp) {
            revert Enclave_Id_Expired();
        }

        bytes memory attestationData =
            abi.encode(identity, enclaveIdentityObj.identityStr, enclaveIdentityObj.signature);
        AttestationRequestData memory reqData = AttestationRequestData({
            recipient: msg.sender,
            expirationTime: uint64(identity.nextUpdateTimestamp),
            revocable: true,
            refUID: predecessorAttestationId,
            data: attestationData,
            value: 0
        });
        req = AttestationRequest({schema: enclaveIdentitySchemaID(), data: reqData});
    }

    /**
     * @notice validates QEIdentity is signed by Intel TCB Signing Cert
     */
    function _validateQeIdentity(EnclaveIdentityJsonObj calldata enclaveIdentityObj) private view {
        // Get TCB Signing Cert
        bytes32 tcbSigningAttestationId = Pcs.pcsCertAttestations(CA.SIGNING);
        bytes memory signingDer = getAttestedData(tcbSigningAttestationId);

        // Validate signature
        bool sigVerified =
            verifySignature(sha256(bytes(enclaveIdentityObj.identityStr)), enclaveIdentityObj.signature, signingDer);

        if (!sigVerified) {
            revert Invalid_TCB_Cert_Signature();
        }
    }
}
