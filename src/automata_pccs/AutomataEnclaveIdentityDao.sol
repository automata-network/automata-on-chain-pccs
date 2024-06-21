// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AutomataDaoBase} from "./shared/AutomataDaoBase.sol";
import {EnclaveIdentityDao, AttestationRequest} from "../bases/EnclaveIdentityDao.sol";

contract AutomataEnclaveIdentityDao is AutomataDaoBase, EnclaveIdentityDao {
    constructor(address _storage, address _pcs, address _enclaveIdentityHelper, address _x509Helper)
        EnclaveIdentityDao(_pcs, _enclaveIdentityHelper, _x509Helper)
        AutomataDaoBase(_storage)
    {}

    function enclaveIdentitySchemaID() public pure override returns (bytes32) {
        // NOT-APPLICABLE FOR OUR USE CASE
        // but this is required by most attestation services, such as EAS, Verax etc
        return bytes32(0);
    }

    function _attestEnclaveIdentity(AttestationRequest memory req, bytes32 hash)
        internal
        override
        returns (bytes32 attestationId)
    {
        // delete the predecessor if replacing
        _deletePredecessor(req.data.refUID);
        _attestCollateral(hash, req.data.data);
        attestationId = hash;
    }
}