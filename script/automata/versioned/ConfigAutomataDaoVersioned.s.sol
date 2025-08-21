// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../utils/DeploymentConfig.sol";
import "../../utils/Multichain.sol";
import {AutomataTcbEvalDao} from "../../../src/automata_pccs/AutomataTcbEvalDao.sol";
import {AutomataFmspcTcbDaoVersioned} from "../../../src/automata_pccs/versioned/AutomataFmspcTcbDaoVersioned.sol";
import {AutomataEnclaveIdentityDaoVersioned} from
    "../../../src/automata_pccs/versioned/AutomataEnclaveIdentityDaoVersioned.sol";

interface IOwnableRoles {
    function grantRoles(address user, uint256 roles) external;

    function revokeRoles(address user, uint256 roles) external;

    function hasAnyRoles(address user, uint256 roles) external view returns (bool);

    function renounceRoles(uint256 roles) external;
}

contract ConfigureAutomataDaoVersioned is DeploymentConfig, Multichain {
    address owner = vm.envAddress("OWNER");

    modifier broadcastOwner() {
        vm.startBroadcast(owner);
        _;
        vm.stopBroadcast();
    }

    function configureTcbEvalDaoRoles(address user, uint256 roles, bool authorize)
        external
        multichain
    {
        address tcbEvalDao = readContractAddress("AutomataTcbEvalDao", false);
        if (tcbEvalDao != address(0)) {
            _configureRoles(tcbEvalDao, user, roles, authorize);
        }
    }

    function configureFmspcTcbDaoVersionedRoles(address user, uint32 version, uint256 roles, bool authorize)
        external
        multichain
    {
        address fmspcTcbDao = readVersionedContractAddress("AutomataFmspcTcbDaoVersioned", version, false);
        if (fmspcTcbDao != address(0)) {
            _configureRoles(fmspcTcbDao, user, roles, authorize);
        }
    }

    function configureEnclaveIdentityDaoVersionedRoles(address user, uint32 version, uint256 roles, bool authorize)
        external
        multichain
    {
        address enclaveIdentityDao = readVersionedContractAddress("AutomataEnclaveIdentityDaoVersioned", version, false);
        if (enclaveIdentityDao != address(0)) {
            _configureRoles(enclaveIdentityDao, user, roles, authorize);
        }
    }

    function _configureRoles(address dao, address user, uint256 roles, bool authorize) private broadcastOwner {
        IOwnableRoles daoRoles = IOwnableRoles(dao);
        bool hasAnyRoles = daoRoles.hasAnyRoles(user, roles);
        if (authorize && !hasAnyRoles ) {
            daoRoles.grantRoles(user, roles);
        } else if (!authorize && hasAnyRoles) {
            daoRoles.revokeRoles(user, roles);
        } else {
            console.log("Skip _configureRoles()");
        }
    }
}
