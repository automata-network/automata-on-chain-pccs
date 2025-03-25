// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AutomataDaoStorage} from "./AutomataDaoStorage.sol";
import {DaoBase} from "../../bases/DaoBase.sol";

abstract contract AutomataDaoBase is DaoBase {
    // 953769d0
    error Unauthorized_Caller(address caller);

    /**
     * @notice overrides the default _fetchDataFromResolver() method to allow
     * custom logic implementation BEFORE fetching data from the resolver
     * @notice this is added to allow read operations to be called from
     * the PCCSRouter contract (Learn more about PCCSRouter at
     * https://github.com/automata-network/automata-dcap-attestation/blob/DEV-3373/audit/contracts/PCCSRouter.sol)
     *
     */
    function _onFetchDataFromResolver(bytes32 key, bool hash)
        internal
        view
        virtual
        override
        returns (bytes memory data)
    {
        if (_callerIsAuthorized()) {
            data = super._onFetchDataFromResolver(key, hash);
        } else {
            revert Unauthorized_Caller(msg.sender);
        }
    }

    function _callerIsAuthorized() private view returns (bool authorized) {
        AutomataDaoStorage automataStorage = AutomataDaoStorage(address(resolver));
        authorized = automataStorage.paused() || automataStorage.isAuthorizedCaller(msg.sender);
    }
}
