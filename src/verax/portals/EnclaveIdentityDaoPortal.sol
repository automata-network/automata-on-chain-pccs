// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AbstractPortal} from "@consensys/linea-attestation-registry-contracts/abstracts/AbstractPortal.sol";
import {AttestationPayload, Attestation} from "@consensys/linea-attestation-registry-contracts/types/Structs.sol";
import {EnclaveIdentityDao, AttestationRequest} from "../../dao/EnclaveIdentityDao.sol";

contract EnclaveIdentityDaoPortal is EnclaveIdentityDao, AbstractPortal {
    /// @notice Error thrown when trying to revoke an attestation
    error No_Revocation();
    /// @notice Error thrown when trying to bulk revoke attestations
    error No_BulkRevocation();
    /// @notice Error thrown when trying to improperly make attestations
    error No_External_Attestation();
    /// @notice Error thrown when trying to retrieve an attestation that has been revoked/replaced
    error Attestation_Revoked(bytes32 predecessor, bytes32 successor);
    /// @notice Error thrown when the replacement of Enclave Identity is invalid
    error Invalid_Identity_Replacement();

    bool private _unlock;

    constructor(address[] memory modules, address router, address pcs, address enclaveIdentityHelper)
        AbstractPortal(modules, router)
        EnclaveIdentityDao(pcs, enclaveIdentityHelper)
    {}

    modifier locked() {
        if (!_unlock) {
            revert No_External_Attestation();
        }
        _;
    }

    /// @inheritdoc AbstractPortal
    function withdraw(address payable to, uint256 amount) external override {}

    function enclaveIdentitySchemaID() public pure override returns (bytes32 ENCLAVE_IDENTITY_SCHEMA_ID) {
        // keccak256(bytes("uint256 issueDateTimestamp, uint256 nextUpdateTimestamp, string identity, bytes signature"))
        ENCLAVE_IDENTITY_SCHEMA_ID = 0x97b41ea5b7cea14d9f50d4b8f09b6fff7744522db6e340e18fbc324810ab9152;
    }

    function _attestEnclaveIdentity(AttestationRequest memory req) internal override returns (bytes32 attestationId) {
        _unlock = true;

        // Generate the Validation payload
        // The validation payload simply contains the Signing CA Certificate
        // used for verifying the Identity Signature
        bytes[] memory validationPayload = new bytes[](1);
        (bytes memory signingCert,) = getEnclaveIdentityIssuerChain();
        validationPayload[0] = signingCert;

        AttestationPayload memory attestationPayload =
            AttestationPayload(req.schema, req.data.expirationTime, abi.encodePacked(req.data.recipient), req.data.data);

        uint32 attestationIdCounter = attestationRegistry.getAttestationIdCounter();
        attestationId = bytes32(abi.encode(attestationIdCounter));

        bytes32 predecessor = req.data.refUID;
        if (predecessor == bytes32(0)) {
            super.attest(attestationPayload, validationPayload);
        } else {
            super.replace(predecessor, attestationPayload, validationPayload);
        }

        _unlock = false;
    }

    function _getAttestedData(bytes32 attestationId) internal view override returns (bytes memory attestationData) {
        Attestation memory attestation = attestationRegistry.getAttestation(attestationId);
        if (attestation.revoked) {
            revert Attestation_Revoked(attestationId, attestation.replacedBy);
        }
        attestationData = attestation.attestationData;
    }

    function _onAttest(AttestationPayload memory, /*attestationPayload*/ address, /*attester*/ uint256 /*value*/ )
        internal
        override
        locked
    {}

    function _onBulkAttest(
        AttestationPayload[] memory, /*attestationsPayloads*/
        bytes[][] memory /*validationPayloads*/
    ) internal override locked {
        /// @notice: external attestations not possible, therefore this code is unreachable
    }

    function _onReplace(
        bytes32 attestationId,
        AttestationPayload memory attestationPayload,
        address, /*attester*/
        uint256 /*value*/
    ) internal view override locked {
        bytes memory prevData = _getAttestedData(attestationId);
        bytes memory currentData = attestationPayload.attestationData;
        (uint256 prevIssueDate,,,) = abi.decode(prevData, (uint256, uint256, string, bytes));
        (uint256 currentIssueDate,,,) = abi.decode(currentData, (uint256, uint256, string, bytes));

        if (currentIssueDate < prevIssueDate) {
            revert Invalid_Identity_Replacement();
        }
    }

    function _onBulkReplace(
        bytes32[] memory, /*attestationIds*/
        AttestationPayload[] memory, /*attestationsPayloads*/
        bytes[][] memory /*validationPayloads*/
    ) internal override locked {
        /// @notice: external attestations not possible, therefore this code is unreachable
    }

    /**
     * @inheritdoc AbstractPortal
     * @notice This portal doesn't allow for an attestation to be revoked
     */
    function _onRevoke(bytes32 /*attestationId*/ ) internal pure override {
        revert No_Revocation();
    }

    /**
     * @inheritdoc AbstractPortal
     * @notice This portal doesn't allow for attestations to be revoked
     */
    function _onBulkRevoke(bytes32[] memory /*attestationIds*/ ) internal pure override {
        revert No_BulkRevocation();
    }
}
