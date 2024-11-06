// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FmspcTcbDao, PcsDao, DaoBase} from "../bases/FmspcTcbDao.sol";
import {Ownable} from "solady/auth/Ownable.sol";

import {AutomataDaoBase} from "./shared/AutomataDaoBase.sol";

contract AutomataFmspcTcbDao is AutomataDaoBase, FmspcTcbDao, Ownable {
    constructor(address _storage, address _p256, address _pcs, address _fmspcHelper, address _x509Helper)
        FmspcTcbDao(_storage, _p256, _pcs, _fmspcHelper, _x509Helper)
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
