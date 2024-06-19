// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DaoBase} from "../../bases/DaoBase.sol";
import {CA} from "../../Common.sol";

interface IAutomataDaoStorage {
    function writeToPccs(bytes32 attId, bytes memory attData) external;

    function readPccs(bytes32 attId) external view returns (bytes memory attData);

    function deleteData(bytes32 attId) external;
}

abstract contract AutomataDaoBase is DaoBase {
    IAutomataDaoStorage pccsStorage;

    constructor(address _storage) {
        pccsStorage = IAutomataDaoStorage(_storage);
    }

    function getAttestedData(bytes32 attestationId) public view override returns (bytes memory attestationData) {
        attestationData = pccsStorage.readPccs(attestationId);
    }

    /// @dev we simply map the collateral hash to the data itself in our use case
    /// @dev however, this may not be the case when the dao integrates an attestation service, such as EAS
    /// @dev it is recommended to store the hash of the collateral as a separate attestation from the collateral
    /// to reduce the size of data read
    function getCollateralHash(bytes32 attestationId) public pure override returns (bytes32) {
        return attestationId;
    }

    function _attestCollateral(bytes32 collateralHash, bytes memory data) internal {
        pccsStorage.writeToPccs(collateralHash, data);
    }

    function _deletePredecessor(bytes32 predecessor) internal {
        if (getAttestedData(predecessor).length > 0) {
            pccsStorage.deleteData(predecessor);
        }
    }
}
