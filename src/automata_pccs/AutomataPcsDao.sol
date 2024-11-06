// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PcsDao, X509CRLHelper} from "../bases/PcsDao.sol";
import {Ownable} from "solady/auth/Ownable.sol";

contract AutomataPcsDao is PcsDao, Ownable {
    constructor(address _storage, address _p256, address _x509, address _crl) PcsDao(_storage, _p256, _x509, _crl) {
        _initializeOwner(msg.sender);
    }

    function updateDeps(address _x509, address _crl) external onlyOwner {
        x509 = _x509;
        crlLib = X509CRLHelper(_crl);
    }
}
