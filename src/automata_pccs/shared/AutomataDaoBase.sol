// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AutomataDaoStorage} from "./AutomataDaoStorage.sol";
import {DaoBase} from "../../bases/DaoBase.sol";

abstract contract AutomataDaoBase is DaoBase {
    function _fetchDataFromResolver(bytes32 key, bool hash)
        internal
        view
        virtual
        override
        returns (bytes memory data)
    {
        if (_callerIsAuthorized()) {
            data = super._fetchDataFromResolver(key, hash);
        }
    }

    function _callerIsAuthorized() private view returns (bool authorized) {
        AutomataDaoStorage automataStorage = AutomataDaoStorage(address(resolver));
        authorized = automataStorage.paused() || automataStorage.isAuthorizedCaller(msg.sender);
    }
}
