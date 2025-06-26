// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../utils/DeploymentConfig.sol";
import {AutomataTcbEvalDao} from "../../../src/automata_pccs/AutomataTcbEvalDao.sol";
import {AutomataFmspcTcbDaoVersioned} from "../../../src/automata_pccs/versioned/AutomataFmspcTcbDaoVersioned.sol";
import {AutomataEnclaveIdentityDaoVersioned} from "../../../src/automata_pccs/versioned/AutomataEnclaveIdentityDaoVersioned.sol";

interface IOwnableRoles {
    function grantRoles(address user, uint256 roles) external;

    function revokeRoles(address user, uint256 roles) external;

    function renounceRoles(uint256 roles) external;
}

contract ConfigureAutomataDaoVersioned is DeploymentConfig {
    address owner = vm.envAddress("OWNER");

    modifier broadcastOwner() {
        vm.startBroadcast(owner);
        _;
        vm.stopBroadcast();
    }

    function configureTcbEvalDaoRoles(address user, uint256 roles, bool authorize) external broadcastOwner {
        address tcbEvalDao = readContractAddress("AutomataTcbEvalDao");
        _configureRoles(tcbEvalDao, user, roles, authorize);
    }

    function configureFmspcTcbDaoVersionedRoles(
        address user,
        uint32 version,
        uint256 roles,
        bool authorize
    ) external broadcastOwner {
        address fmspcTcbDao = readVersionedContractAddress("AutomataFmspcTcbDaoVersioned", version);
        _configureRoles(fmspcTcbDao, user, roles, authorize);
    }
    function configureEnclaveIdentityDaoVersionedRoles(
        address user,
        uint32 version,
        uint256 roles,
        bool authorize
    ) external broadcastOwner {
        address enclaveIdentityDao = readVersionedContractAddress("AutomataEnclaveIdentityDaoVersioned", version);
        _configureRoles(enclaveIdentityDao, user, roles, authorize);
    }

    function _configureRoles(address dao, address user, uint256 roles, bool authorize) private {
        IOwnableRoles daoRoles = IOwnableRoles(dao);
        if (authorize) {
            daoRoles.grantRoles(user, roles);
        } else {
            daoRoles.revokeRoles(user, roles);
        }
    }
}