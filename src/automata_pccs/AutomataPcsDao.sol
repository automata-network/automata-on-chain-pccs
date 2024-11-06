// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PcsDao, X509CRLHelper, DaoBase} from "../bases/PcsDao.sol";
import {Ownable} from "solady/auth/Ownable.sol";

import {AutomataDaoBase} from "./shared/AutomataDaoBase.sol";

contract AutomataPcsDao is AutomataDaoBase, PcsDao, Ownable {
    constructor(address _storage, address _p256, address _x509, address _crl) PcsDao(_storage, _p256, _x509, _crl) {
        _initializeOwner(msg.sender);
    }

    function getAttestedData(bytes32 key) public view override(AutomataDaoBase, DaoBase) returns (bytes memory) {
        return super.getAttestedData(key);
    }

    function getCollateralHash(bytes32 key) public view override(AutomataDaoBase, DaoBase) returns (bytes32 collateralHash) {
        return super.getCollateralHash(key);
    }
}
