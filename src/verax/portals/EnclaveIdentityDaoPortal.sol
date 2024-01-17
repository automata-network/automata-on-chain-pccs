// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AbstractPortal} from "@consensys/linea-attestation-registry-contracts/abstracts/AbstractPortal.sol";
import {AttestationPayload, Attestation} from "@consensys/linea-attestation-registry-contracts/types/Structs.sol";
import {EnclaveIdentityDao, AttestationRequest} from "../../dao/EnclaveIdentityDao.sol";
import {SigVerifyModuleBase} from "../base/SigVerifyModuleBase.sol";

contract EnclaveIdentityDaoPortal is EnclaveIdentityDao, AbstractPortal, SigVerifyModuleBase {
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

    constructor(address[] memory modules, address router, address pcs, address enclaveIdentityHelper, address x509)
        AbstractPortal(modules, router)
        EnclaveIdentityDao(pcs, enclaveIdentityHelper)
        SigVerifyModuleBase(x509)
    {
        // validation is done here. No need for a module.
        require(modules.length == 0);
    }

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

        bytes[] memory empty = new bytes[](0);
        (bytes memory signingCert,) = getEnclaveIdentityIssuerChain();

        AttestationPayload memory attestationPayload =
            AttestationPayload(req.schema, req.data.expirationTime, abi.encodePacked(req.data.recipient), req.data.data);

        _validate(attestationPayload, signingCert);

        uint32 attestationIdCounter = attestationRegistry.getAttestationIdCounter() + 1;
        uint256 chainPrefix = attestationRegistry.getChainPrefix();
        attestationId = bytes32(abi.encode(chainPrefix + attestationIdCounter));

        bytes32 predecessor = req.data.refUID;
        if (predecessor == bytes32(0)) {
            super.attest(attestationPayload, empty);
        } else {
            super.replace(predecessor, attestationPayload, empty);
        }

        _unlock = false;
    }

    function _getAttestedData(bytes32 attestationId) internal view override returns (bytes memory attestationData) {
        if (attestationRegistry.isRegistered(attestationId)) {
            Attestation memory attestation = attestationRegistry.getAttestation(attestationId);
            if (attestation.revoked) {
                revert Attestation_Revoked(attestationId, attestation.replacedBy);
            }
            attestationData = attestation.attestationData;
        }
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

    function _validate(AttestationPayload memory attestationPayload, bytes memory issuer) private view {
        (,, string memory enclaveIdentity, bytes memory signature) =
            abi.decode(attestationPayload.attestationData, (uint256, uint256, string, bytes));
        bytes32 digest = sha256(abi.encodePacked(enclaveIdentity));
        bool sigVerified = verifySignature(digest, signature, issuer);
        if (!sigVerified) {
            revert Invalid_Signature();
        }
    }
}
