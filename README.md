<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/automata-network/automata-brand-kit/main/PNG/ATA_White%20Text%20with%20Color%20Logo.png">
    <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/automata-network/automata-brand-kit/main/PNG/ATA_Black%20Text%20with%20Color%20Logo.png">
    <img src="https://raw.githubusercontent.com/automata-network/automata-brand-kit/main/PNG/ATA_White%20Text%20with%20Color%20Logo.png" width="50%">
  </picture>
</div>

# Automata On Chain PCCS
[![Automata On Chain PCCS](https://img.shields.io/badge/Power%20By-Automata-orange.svg)](https://github.com/automata-network)

## Summary

This repo consists of Solidity implementation for an on-chain PCCS (Provisioning Certificate Caching Service) used in Intel DCAP (Data Center Attestation Primitives).

On-chain PCCS provides an open and permissionless service where users can freely contribute and be given easy access to collaterals for quote verification.

---

## Contracts

There are two sets of contracts, i.e. the **Helper** and **Base**.

### Helper Contracts

The Helper contracts provide APIs for parsing collaterals and converting into Solidity structs, i.e. QEIdentity.json, TCBInfo.json, basic DER-decoder for PCK X509 leaf certificate and extensions and X509 CRLs.

### Base libraries and Automata DAO contracts

The base contracts are libraries that provide the Data Access Object (DAO) APIs with similar designs inspired from the [Design Guide for Intel SGX PCCS](https://download.01.org/intel-sgx/sgx-dcap/1.21/linux/docs/SGX_DCAP_Caching_Service_Design_Guide.pdf).

Base contracts are dependent on Helper contracts to parse collaterals, and contains implementation of basic collateral authenticity check functions for upserts. Smart contract developers are encouraged to extend the base contracts to build their own custom implementation of on-chain PCCS.

Our DAO implementation can be found in the [`automata_pccs`](./src/automata_pccs/) directory.

### Deployment Info

This list contains the deployment info for the versions that we are currently supporting.

- [Current](./releases/next/NOTE.md)
- [v1.0.0](./releases/v1.0.0/NOTE.md)

---

### #BUIDL 🛠️

1. Install [Foundry](https://getfoundry.sh/introduction/installation/)

2. Install the dependencies

```bash
forge install
```

3. Compile the contracts

```bash
forge build
```

4. Run tests

```bash
forge test
```

To view gas report, pass the `--gas-report` flag.

### Deployment

Before you begin, it is HIGHLY recommended that you store and encrypt wallet keys using [Cast](https://book.getfoundry.sh/reference/cast/cast-wallet-import).

```bash
cast wallet import --keystore-dir ./keystore dcap_prod --interactive
```

If you had [**decided against taking the .env pledge**](https://github.com/smartcontractkit/full-blockchain-solidity-course-js/discussions/5), you can (but shouldn't) pass your wallet key to the `PRIVATE_KEY` environmental variable.

Once you have set up your wallet, you may run the following script to deploy the PCCS Contracts.

```bash
make deploy-all RPC_URL=<rpc-url>
```

You may also pass `SIMULATE=true` at the end of the command to run the script without broadcasting the transactions.

After deploying the contracts, run the commands below to verify contracts on the explorer.

Etherscan:
```bash
make verify-all RPC_URL=<rpc-url> ETHERSCAN_API_KEY=<etherscan-api-key>
```

Blockscout:
```bash
make verify-all RPC_URL=<rpc-url> VERIFIER=blockscout VERIFIER_URL=<explorer-api-url>
```

To see all available commands, run:

```bash
make help
```
