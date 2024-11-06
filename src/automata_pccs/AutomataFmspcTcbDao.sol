// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FmspcTcbDao, PcsDao} from "../bases/FmspcTcbDao.sol";
import {Ownable} from "solady/auth/Ownable.sol";

contract AutomataFmspcTcbDao is Ownable, FmspcTcbDao {
    constructor(address _storage, address _p256, address _pcs, address _fmspcHelper, address _x509Helper)
        FmspcTcbDao(_storage, _p256, _pcs, _fmspcHelper, _x509Helper)
    {
        _initializeOwner(msg.sender);
    }

    function setPcs(address _pcs) external onlyOwner {
        Pcs = PcsDao(_pcs);
    }
}
