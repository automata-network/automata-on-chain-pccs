// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {EnclaveIdentityDao, AttestationRequest, PcsDao} from "../bases/EnclaveIdentityDao.sol";

import {Ownable} from "solady/auth/Ownable.sol";

contract AutomataEnclaveIdentityDao is Ownable, EnclaveIdentityDao {
    constructor(address _storage, address _p256, address _pcs, address _enclaveIdentityHelper, address _x509Helper)
        EnclaveIdentityDao(_storage, _p256, _pcs, _enclaveIdentityHelper, _x509Helper)
    {
        _initializeOwner(msg.sender);
    }

    function setPcs(address _pcs) external onlyOwner {
        Pcs = PcsDao(_pcs);
    }

    function enclaveIdentitySchemaID() public pure override returns (bytes32) {
        // NOT-APPLICABLE FOR OUR USE CASE
        // but this is required by most attestation services, such as EAS, Verax etc
        return bytes32(0);
    }
}
