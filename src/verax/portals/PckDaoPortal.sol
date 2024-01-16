// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AbstractPortal} from "@consensys/linea-attestation-registry-contracts/abstracts/AbstractPortal.sol";
import {AttestationPayload, Attestation} from "@consensys/linea-attestation-registry-contracts/types/Structs.sol";
import {PckDao, AttestationRequest, CA} from "../../dao/PckDao.sol";

contract PckDaoPortal is PckDao, AbstractPortal {
    /// @notice Error thrown when trying to improperly make attestations
    error No_External_Attestation();
    /// @notice Error thrown when trying to retrieve an attestation that has been revoked/replaced
    error Attestation_Revoked(bytes32 predecessor, bytes32 successor);

    bool private _unlock;

    constructor(address[] memory modules, address router, address pcs) AbstractPortal(modules, router) PckDao(pcs) {}

    modifier locked() {
        if (!_unlock) {
            revert No_External_Attestation();
        }
        _;
    }

    /// @inheritdoc AbstractPortal
    function withdraw(address payable to, uint256 amount) external override {}

    function pckSchemaID() public pure override returns (bytes32 PCK_SCHEMA_ID) {
        // keccak256(bytes("bytes pckCert, uint256 createdAt, uint256 updatedAt"))
        PCK_SCHEMA_ID = 0x2ca531ee0086eee1c85b98d4c6dda78d3fb22921669e2fced0ebf3914f48e32d;
    }

    function _attestPck(AttestationRequest memory req, CA ca) internal override returns (bytes32 attestationId) {
        _unlock = true;

        // Generate the Validation payload
        // The validation payload simply contains the corresponding Intermediate CA
        // used for verifying the signature in the PCK Certificate
        bytes[] memory validationPayload = new bytes[](1);
        (bytes memory intermediateCert,) = getPckCertChain(ca);
        validationPayload[0] = intermediateCert;

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
    {
        // TODO: Check serial number from CRL
    }

    function _onBulkAttest(
        AttestationPayload[] memory, /*attestationsPayloads*/
        bytes[][] memory /*validationPayloads*/
    ) internal override locked {
        /// @notice: external attestations not possible, therefore this code is unreachable
    }

    function _onReplace(
        bytes32, /*attestationId*/
        AttestationPayload memory, /*attestationPayload*/
        address, /*attester*/
        uint256 /*value*/
    ) internal override locked {
        // TODO: Check serial number from CRL
    }

    function _onBulkReplace(
        bytes32[] memory, /*attestationIds*/
        AttestationPayload[] memory, /*attestationsPayloads*/
        bytes[][] memory /*validationPayloads*/
    ) internal override locked {
        /// @notice: external attestations not possible, therefore this code is unreachable
    }

    function _onRevoke(bytes32 attestationId) internal override {
        // TODO: Check serial number from CRL
    }

    function _onBulkRevoke(bytes32[] memory attestationIds) internal override {
        // TODO: Check serial number from CRL
    }
}
