// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IDaoAttestationResolver {
    function collateralPointer(bytes32 key) external view returns (bytes32 collateralAttId);

    function collateralHashPointer(bytes32 key) external view returns (bytes32 collateralHashAttId);

    function attest(bytes32 key, bytes calldata attData, bytes32 attDataHash)
        external
        returns (bytes32 attestationId, bytes32 hashAttestationid);

    function readAttestation(bytes32 attestationId) external view returns (bytes memory attData);
}
