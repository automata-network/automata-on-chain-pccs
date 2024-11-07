// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CA} from "../Common.sol";
import {
    EnclaveIdentityHelper, EnclaveIdentityJsonObj, EnclaveId, IdentityObj
} from "../helpers/EnclaveIdentityHelper.sol";

import {DaoBase} from "./DaoBase.sol";
import {SigVerifyBase} from "./SigVerifyBase.sol";
import {PcsDao} from "./PcsDao.sol";

/// @notice EnclaveId is stored as ABI-encoded tuple of (EnclaveIdentityHelper.IdentityObj, string, bytes)
/// @notice see {{ EnclaveIdentityHelper.IdentityObj }} for struct definition
/// @notice - string qeidentityObj
/// @notice - bytes signature

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

    error Enclave_Id_Mismatch();
    error Invalid_TCB_Cert_Signature();
    error Enclave_Id_Expired();

    constructor(address _resolver, address _p256, address _pcs, address _enclaveIdentityHelper, address _x509Helper)
        DaoBase(_resolver)
        SigVerifyBase(_p256, _x509Helper)
    {
        Pcs = PcsDao(_pcs);
        EnclaveIdentityLib = EnclaveIdentityHelper(_enclaveIdentityHelper);
    }

    /**
     * @notice computes the key that is mapped to the collateral attestation ID
     * NOTE: the "version" indicated here is taken from the input parameter (e.g. v3 vs v4);
     * NOT the "version" value found in the Enclave Identity JSON
     * @return key = keccak256(id ++ version)
     */
    function ENCLAVE_ID_KEY(uint256 id, uint256 version) public pure returns (bytes32 key) {
        key = keccak256(abi.encodePacked(id, version));
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
        bytes memory attestedIdentityData = _fetchDataFromResolver(ENCLAVE_ID_KEY(id, version), false);
        if (attestedIdentityData.length > 0) {
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
        bytes32 key = ENCLAVE_ID_KEY(id, version);
        bytes memory req = _buildEnclaveIdentityAttestationRequest(id, key, enclaveIdentityObj);
        bytes32 hash = sha256(bytes(enclaveIdentityObj.identityStr));
        attestationId = _attestEnclaveIdentity(req, hash, key);
    }

    /**
     * @notice Fetches the Enclave Identity issuer chain
     * @return signingCert - DER encoded Intel TCB Signing Certificate
     * @return rootCert - DER encoded Intel SGX Root CA
     */
    function getEnclaveIdentityIssuerChain() external view returns (bytes memory signingCert, bytes memory rootCert) {
        signingCert = _fetchDataFromResolver(Pcs.PCS_KEY(CA.SIGNING, false), false);
        rootCert = _fetchDataFromResolver(Pcs.PCS_KEY(CA.ROOT, false), false);
    }

    /**
     * @dev implement logic to validate and attest the enclave identity
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
     * @notice builds an EAS compliant attestation request
     */
    function _buildEnclaveIdentityAttestationRequest(
        uint256 id,
        bytes32 key,
        EnclaveIdentityJsonObj calldata enclaveIdentityObj
    ) private view returns (bytes memory reqData) {
        IdentityObj memory identity = EnclaveIdentityLib.parseIdentityString(enclaveIdentityObj.identityStr);
        if (id != uint256(identity.id)) {
            revert Enclave_Id_Mismatch();
        }

        if (block.timestamp < identity.issueDateTimestamp || block.timestamp > identity.nextUpdateTimestamp) {
            revert Enclave_Id_Expired();
        }

        reqData = abi.encode(identity, enclaveIdentityObj.identityStr, enclaveIdentityObj.signature);
    }

    /**
     * @notice validates QEIdentity is signed by Intel TCB Signing Cert
     */
    function _validateQeIdentity(EnclaveIdentityJsonObj calldata enclaveIdentityObj) private view {
        // Get TCB Signing Cert
        // bytes memory signingDer = _fetchDataFromResolver(Pcs.PCS_KEY(CA.SIGNING, false), false);
        // TEMP: calling _fetchDataFromResolver() would make more sense semantically
        // TEMP: but I am calling the resolver directly here so that
        // TEMP: _fetchDataFromResolver() can be overwritten without breaking here...
        bytes memory signingDer = resolver.readAttestation(resolver.collateralPointer(Pcs.PCS_KEY(CA.SIGNING, false)));

        // Validate signature
        bool sigVerified =
            verifySignature(sha256(bytes(enclaveIdentityObj.identityStr)), enclaveIdentityObj.signature, signingDer);

        if (!sigVerified) {
            revert Invalid_TCB_Cert_Signature();
        }
    }
}
