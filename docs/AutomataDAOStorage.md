# Automata PCCS DAO and Collateral Storage Management

## Overview

`AutomataDaoStorage` serves as the central location for collateral storage. This contract is designed to be immutable and only writable by individual DAOs. 

There is an access control mechanism in place allowing an admin to determine whether an address can read and/or write to the storage.

This design approach allows the ability to migrate DAOs from one address to another while retaining collateral data.

Currently, the following contracts are granted with read and write permissions:

- `AutomataEnclaveIdentityDAO`
- `AutomataFmspcTcbDAO`
- `AutomataPckDao`
- `AutomataPcsDao`

The following contract is ONLY granted with read permission:

- [`PCCSRouter`](https://github.com/automata-network/automata-dcap-attestation/blob/main/evm/contracts/PCCSRouter.sol)

The `PCCSRouter` is the "middle man" between Automata PCCS Storage and external dApps. Smart contracts must call the appropriate methods implemented in the `PCCSRouter` to read collaterals from the storage.

---

Each DAO uses a 32-byte value as "key" to label collaterals, which is simply a hash of parametric values associated with a collateral, such as the TEE type, version number etc. `AutomataDaoStorage` creates a direct mapping, using the key to locate the collateral data.

`AutomataDaoStorage` can also utilize the collateral keys to store the metadata of a particular collateral. Metadata such as the issuance timestamp, the collateral hash and the "content-specific" hash can be useful for performing certain checks about the collateral without reading the entire data to memory, which can significantly reduce gas cost. 

The metadata is stored exactly the same way as collaterals do. The metadata key used for the mapping is derived from taking the hash of the collateral key, concatenated with a string identifier that describes the metadata.

The remainder of this section describes the key-value pair defined in `AutomataDaoStorage` by individual DAOs to store collaterals and their metadata.

## Global Constants

The following constants are defined and hashed together with collateral parameters to reduce the risk of hash collisions when deriving collateral keys.

```
bytes4 DATA_ATTESTATION_MAGIC = 0x54a09e9a
bytes4 HASH_ATTESTATION_MAGIC = 0x628ab4d2
```

## `AutomataEnclaveIdentityDAO`

```
bytes4 ENCLAVE_ID_MAGIC = 0xff818fce
ENCLAVE_ID_KEY = keccak256(ENCLAVE_ID_MAGIC, u256 id, u256 version)
```

Mappings defined:

- keccak256(DATA_ATTESTATION_MAGIC, ENCLAVE_ID_KEY) => serialized blob consisting of `IdentityObj`, JSON string body of `EnclaveIdentityJsonObj` and the signature.

- keccak256(HASH_ATTESTATION_MAGIC, ENCLAVE_ID_KEY) => sha256 hash of JSON string body of `EnclaveIdentityJsonObj`

- keccak256(ENCLAVE_ID_KEY, "identityIssueEvaluation") => uint256 slot consisting the values (`issueDateTimestamp`, `nextUpdateTimestamp` and `tcbEvaluationDataNumber`)

- keccak256(ENCLAVE_ID_KEY, "identityContentHash") => "content-specific" hash

---

## `AutomataFmspcTcbDAO`

```
bytes4 FMSPC_TCB_MAGIC = 0xbb69b29c
FMSPC_TCB_KEY = keccak256(FMSPC_TCB_MAGIC, u8 tcbType, u8[6] fmspc, u32 version)
```

Mappings defined:

- keccak256(DATA_ATTESTATION_MAGIC, FMSPC_TCB_KEY) => serialized blob (may vary depending on the collateral version)

- keccak256(HASH_ATTESTATION_MAGIC, FMSPC_TCB_KEY) => sha256 hash of JSON string body of `TcbInfoJsonObj`

- keccak256(FMSPC_TCB_KEY, "tcbIssueEvaluation") => uint256 slot consisting the values (`issueDateTimestamp`, `nextUpdateTimestamp` and `tcbEvaluationDataNumber`)

- keccak256(FMSPC_TCB_KEY, "fmspcTcbContentHash") => "content-specific" hash

---

## `AutomataPckDAO`

```
bytes4 PCK_MAGIC = 0xf0e2a246
PCK_KEY = keccak256(PCK_MAGIC, u8[16] qeid, u8[2] pceid, u8[18] tcbm)

bytes4 TCB_MAPPING_MAGIC = 0x5b8e7b4e
TCB_MAPPING_KEY = keccak256(TCB_MAPPING_MAGIC, u8[16] qeid, u8[2] pceid, u8[16] platform_cpusvn, u8[2] platform_pcesvn)
```

Mappings defined:

- keccak256(DATA_ATTESTATION_MAGIC, PCK_KEY) => DER-encoded blob of a PCK Certificate

- keccak256(HASH_ATTESTATION_MAGIC, PCK_KEY) => keccak256 hash of the blob

- keccak256(PCS_KEY, "pckValidity") => uint256 slot consisting the values (`notValidBefore` and `notValidAfter`)

The key used to keep track of TCB Mapping does not conform with the standard definition. Instead:

- keccak256(qeid, pceid) => tcbm set

- keccak256(qeid, pceid, rawCpuSvn, rawPceSvn) => tcbm

---

## `AutomataPcsDAO`

```
bytes4 PCS_MAGIC = 0xe90e3dc7
PCS_KEY = keccak256(PCS_MAGIC, u8 CA, bool isCrl)

CA = 0 => ROOT
CA = 1 => PROCESSOR
CA = 2 => PLATFORM
CA = 3 => SIGNING
```

Mappings defined:

- keccak256(DATA_ATTESTATION_MAGIC, PCS_KEY) => DER-encoded blob of a CA Certificate or CRL

- keccak256(HASH_ATTESTATION_MAGIC, PCS_KEY) => keccak256 hash of the blob

- keccak256(PCS_KEY, "pcsValidity") => uint256 slot consisting the values (`notValidBefore` and `notValidAfter`)