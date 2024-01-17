// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AbstractPortal} from "@consensys/linea-attestation-registry-contracts/abstracts/AbstractPortal.sol";
import {AttestationPayload, Attestation} from "@consensys/linea-attestation-registry-contracts/types/Structs.sol";
import {FmspcTcbDao, AttestationRequest} from "../../dao/FmspcTcbDao.sol";
import {SigVerifyModuleBase} from "../base/SigVerifyModuleBase.sol";

contract FmspcTcbDaoPortal is FmspcTcbDao, AbstractPortal, SigVerifyModuleBase {
    /// @notice Error thrown when trying to revoke an attestation
    error No_Revocation();
    /// @notice Error thrown when trying to bulk revoke attestations
    error No_BulkRevocation();
    /// @notice Error thrown when trying to improperly make attestations
    error No_External_Attestation();
    /// @notice Error thrown when trying to retrieve an attestation that has been revoked/replaced
    error Attestation_Revoked(bytes32 predecessor, bytes32 successor);
    /// @notice Error thrown when the replacement of TCBInfo is invalid
    error Invalid_TCBInfo_Replacement();

    bool private _unlock;

    constructor(address[] memory modules, address router, address pcs, address fmspcTcbHelper, address x509)
        AbstractPortal(modules, router)
        FmspcTcbDao(pcs, fmspcTcbHelper)
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

    function fmspcTcbSchemaID() public pure override returns (bytes32 FMSPC_TCB_SCHEMA_ID) {
        // keccak256(bytes("uint256 tcbType, uint256 version, uint256 issueDateTimestamp, uint256 nextUpdateTimestamp, string tcbInfo, bytes signature"))
        FMSPC_TCB_SCHEMA_ID = 0x46bd450c3c87d1c7842b1efb25c629c61fa188159f1e48326da497f28aef6757;
    }

    function _attestTcb(AttestationRequest memory req) internal override returns (bytes32 attestationId) {
        _unlock = true;

        bytes[] memory empty = new bytes[](0);
        (bytes memory signingCert,) = getTcbIssuerChain();

        AttestationPayload memory attestationPayload =
            AttestationPayload(req.schema, req.data.expirationTime, abi.encodePacked(req.data.recipient), req.data.data);

        _validate(attestationPayload, signingCert);

        uint32 attestationIdCounter = attestationRegistry.getAttestationIdCounter();
        attestationId = bytes32(abi.encode(attestationIdCounter));

        bytes32 predecessor = req.data.refUID;
        if (predecessor == bytes32(0)) {
            super.attest(attestationPayload, empty);
        } else {
            super.replace(predecessor, attestationPayload, empty);
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
        (,, uint256 prevIssueDate,,,) = abi.decode(prevData, (uint256, uint256, uint256, uint256, string, bytes));
        (,, uint256 currentIssueDate,,,) = abi.decode(currentData, (uint256, uint256, uint256, uint256, string, bytes));

        if (currentIssueDate < prevIssueDate) {
            revert Invalid_TCBInfo_Replacement();
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
        (,,,, string memory tcbInfo, bytes memory signature) =
            abi.decode(attestationPayload.attestationData, (uint256, uint256, uint256, uint256, string, bytes));
        bytes32 digest = sha256(abi.encodePacked(tcbInfo));
        bool sigVerified = verifySignature(digest, signature, issuer);
        if (!sigVerified) {
            revert Invalid_Signature();
        }
    }
}
