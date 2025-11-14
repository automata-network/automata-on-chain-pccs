// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct EnclaveIdentityJsonObj {
    string identityStr;
    bytes signature;
}

interface IEnclaveIdentityDao {
    function getEnclaveIdentity(uint256 id, uint256 version)
        external
        view
        returns (EnclaveIdentityJsonObj memory enclaveIdObj);

    function getEnclaveIdentityIssuerChain() external view returns (bytes memory signingCert, bytes memory rootCert);

    function upsertEnclaveIdentity(uint256 id, uint256 version, EnclaveIdentityJsonObj calldata enclaveIdentityObj)
        external
        returns (bytes32 attestationId);
}
