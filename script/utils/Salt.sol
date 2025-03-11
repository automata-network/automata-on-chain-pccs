// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

bytes32 constant ENCLAVE_IDENTITY_HELPER_SALT = keccak256(bytes("ENCLAVE_IDENTITY_HELPER_SALT"));
bytes32 constant FMSPC_TCB_HELPER_SALT = keccak256(bytes("FMSPC_TCB_HELPER_SALT"));
bytes32 constant X509_HELPER_SALT = keccak256(bytes("X509_HELPER_SALT"));
bytes32 constant X509_CRL_HELPER_SALT = keccak256(bytes("X509_CRL_HELPER_SALT"));

bytes32 constant PCCS_STORAGE_SALT = keccak256(bytes("PCCS_STORAGE_SALT"));
bytes32 constant ENCLAVE_ID_DAO_SALT = keccak256(bytes("ENCLAVE_ID_DAO_SALT"));
bytes32 constant FMSPC_TCB_DAO_SALT = keccak256(bytes("FMSPC_TCB_DAO_SALT"));
bytes32 constant PCK_DAO_SALT = keccak256(bytes("PCK_DAO_SALT"));
bytes32 constant PCS_DAO_SALT = keccak256(bytes("PCS_DAO_SALT"));
