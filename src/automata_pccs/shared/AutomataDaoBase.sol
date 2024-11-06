// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AutomataDaoStorage} from "./AutomataDaoStorage.sol";
import {DaoBase} from "../../bases/DaoBase.sol";

abstract contract AutomataDaoBase is DaoBase {
    function getAttestedData(bytes32 key) public view virtual override returns (bytes memory data) {
        if (_callerIsAuthorized()) {
            data = super.getAttestedData(key);
        }
    }

    function getCollateralHash(bytes32 key) public view virtual override returns (bytes32 collateralHash) {
        if (_callerIsAuthorized()) {
            collateralHash = super.getCollateralHash(key);
        }
    }

    function _callerIsAuthorized() private view returns (bool authorized) {
        AutomataDaoStorage automataStorage = AutomataDaoStorage(address(resolver));
        authorized = automataStorage.paused() || automataStorage.isAuthorizedCaller(msg.sender);
    }
}
