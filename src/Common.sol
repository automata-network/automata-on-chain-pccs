// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

enum CA {
    ROOT,
    PROCESSOR,
    PLATFORM,
    SIGNING
}

/// @notice Attestation Definition is taken from https://github.com/ethereum-attestation-service/eas-contracts/blob/52af661748bde9b40ae782907702f885852bc149/contracts/IEAS.sol#L9C1-L23C2
/// @notice We opted for EAS Attestation Request Definition to ensure interoperability between Verax and EAS

struct AttestationRequestData {
    address recipient; // The recipient of the attestation.
    uint64 expirationTime; // The time when the attestation expires (Unix timestamp).
    bool revocable; // Whether the attestation is revocable.
    bytes32 refUID; // The UID of the related attestation.
    bytes data; // Custom attestation data.
    uint256 value; // An explicit ETH amount to send to the resolver. This is important to prevent accidental user errors.
}

struct AttestationRequest {
    bytes32 schema; // The unique identifier of the schema.
    AttestationRequestData data; // The arguments of the attestation request.
}

/// @notice A struct representing a single attestation.
/// https://github.com/ethereum-attestation-service/eas-contracts/blob/52af661748bde9b40ae782907702f885852bc149/contracts/Common.sol#L25C1-L37C2
struct Attestation {
    bytes32 uid; // A unique identifier of the attestation.
    bytes32 schema; // The unique identifier of the schema.
    uint64 time; // The time when the attestation was created (Unix timestamp).
    uint64 expirationTime; // The time when the attestation expires (Unix timestamp).
    uint64 revocationTime; // The time when the attestation was revoked (Unix timestamp).
    bytes32 refUID; // The UID of the related attestation.
    address recipient; // The recipient of the attestation.
    address attester; // The attester/sender of the attestation.
    bool revocable; // Whether the attestation is revocable.
    bytes data; // Custom attestation data.
}
