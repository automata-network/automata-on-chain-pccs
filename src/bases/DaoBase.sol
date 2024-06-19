// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

abstract contract DaoBase {
    /**
     * @dev implement getter logic to retrieve attested data
     * @param attestationId maps to the data
     */
    function getAttestedData(bytes32 attestationId) public view virtual returns (bytes memory attestationData);

    /**
     * @dev must store the hash of a collateral (e.g. X509 Cert, TCBInfo JSON etc) in the attestation registry
     * @dev it is recommended to store hash as a separate attestation from the actual collateral
     * @dev this getter can be useful for checking the correctness of the queried attested collateral
     *
     * @dev may link the hash attestation with the attestation of the collateral
     * For example, the content of a hash attestation can be a tuple of bytes32 values consisting of:
     * (bytes32 collateralHash, bytes32 collateralAttestationId)
     * @param attestationId - the attestationId pointing to the hash attestation, or the collateral attestation
     * itself, if the hash is included as part of the attestation data, this varies by how you define the schema.
     */
    function getCollateralHash(bytes32 attestationId) public view virtual returns (bytes32 collateralHash);
}
