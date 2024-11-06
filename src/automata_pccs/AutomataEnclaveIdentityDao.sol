// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {EnclaveIdentityDao, PcsDao, DaoBase} from "../bases/EnclaveIdentityDao.sol";
import {Ownable} from "solady/auth/Ownable.sol";

import {AutomataDaoBase} from "./shared/AutomataDaoBase.sol";

contract AutomataEnclaveIdentityDao is AutomataDaoBase, EnclaveIdentityDao, Ownable {
    constructor(address _storage, address _p256, address _pcs, address _enclaveIdentityHelper, address _x509Helper)
        EnclaveIdentityDao(_storage, _p256, _pcs, _enclaveIdentityHelper, _x509Helper)
    {
        _initializeOwner(msg.sender);
    }

    function getAttestedData(bytes32 key) public view override(AutomataDaoBase, DaoBase) returns (bytes memory) {
        return super.getAttestedData(key);
    }

    function getCollateralHash(bytes32 key)
        public
        view
        override(AutomataDaoBase, DaoBase)
        returns (bytes32 collateralHash)
    {
        return super.getCollateralHash(key);
    }
}
