// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AbstractPortal} from "@consensys/linea-attestation-registry-contracts/abstracts/AbstractPortal.sol";
import {AttestationPayload, Attestation} from "@consensys/linea-attestation-registry-contracts/types/Structs.sol";
import {FmspcTcbDao, AttestationRequest} from "../../lib/dao/FmspcTcbDao.sol";

contract FmspcTcbDaoPortal is FmspcTcbDao, AbstractPortal {
    /// @notice Error thrown when trying to revoke an attestation
    error No_Revocation();
    /// @notice Error thrown when trying to bulk revoke attestations
    error No_BulkRevocation();
    /// @notice Error thrown when trying to improperly make attestations
    error No_External_Attestation();

    bool private _unlock;

    constructor(address[] memory modules, address router, address pcs)
        AbstractPortal(modules, router)
        FmspcTcbDao(pcs)
    {}

    modifier locked() {
        if (!_unlock) {
            revert No_External_Attestation();
        }
        _;
    }

    /// @inheritdoc AbstractPortal
    function withdraw(address payable to, uint256 amount) external override {}

    function fmspcTcbSchemaID() public pure override returns (bytes32 FMSPC_TCB_SCHEMA_ID) {
        // keccak256(bytes("bytes tcbInfo, uint256 createdAt, uint256 updatedAt"))
        FMSPC_TCB_SCHEMA_ID = 0xd16d0301ef1e0da2909ee969b5b4f21704a6e38a7dad4575242cbc84eeeb8903;
    }

    function _attestTcb(AttestationRequest memory req) internal override returns (bytes32 attestationId) {
        _unlock = true;

        // Generate the Validation payload
        // The validation payload simply contains the Signing CA Certificate chain
        // used for verifying the Identity Signature
        bytes[] memory validationPayload = new bytes[](1);
        (bytes memory signingCert, bytes memory rootCert) = getTcbIssuerChain();
        validationPayload[0] = abi.encode(signingCert, rootCert);

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
    ) internal override locked {}

    function _onReplace(
        bytes32, /*attestationId*/
        AttestationPayload memory, /*attestationPayload*/
        address, /*attester*/
        uint256 /*value*/
    ) internal override locked {}

    function _onBulkReplace(
        bytes32[] memory, /*attestationIds*/
        AttestationPayload[] memory, /*attestationsPayloads*/
        bytes[][] memory /*validationPayloads*/
    ) internal override locked {}

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
