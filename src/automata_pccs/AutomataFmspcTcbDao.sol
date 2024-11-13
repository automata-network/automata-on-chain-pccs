// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FmspcTcbDao, PcsDao, DaoBase} from "../bases/FmspcTcbDao.sol";
import {AutomataDaoBase} from "./shared/AutomataDaoBase.sol";

contract AutomataFmspcTcbDao is AutomataDaoBase, FmspcTcbDao {
    constructor(address _storage, address _p256, address _pcs, address _fmspcHelper, address _x509Helper)
        FmspcTcbDao(_storage, _p256, _pcs, _fmspcHelper, _x509Helper)
    {}

    function _onFetchDataFromResolver(bytes32 key, bool hash)
        internal
        view
        override(AutomataDaoBase, DaoBase)
        returns (bytes memory data)
    {
        data = super._onFetchDataFromResolver(key, hash);
    }
}
