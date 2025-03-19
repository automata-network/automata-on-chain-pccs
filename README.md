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

> ℹ️ **Note**: 
>
> The deployment addresses shown here are currently based on the latest [changes](https://github.com/automata-network/automata-on-chain-pccs/pull/9) made.
>
> To view deployments on the previous version (will be deprecated soon), you may refer to this [branch](https://github.com/automata-network/automata-on-chain-pccs/tree/v0).

There are two sets of contracts, i.e. the **Helper** and **Base**.

### Helper Contracts

The Helper contracts provide APIs for parsing collaterals and converting into Solidity structs, i.e. QEIdentity.json, TCBInfo.json, basic DER-decoder for PCK X509 leaf certificate and extensions and X509 CRLs.

#### Testnet

|  | Network | Address |
| --- | --- | --- |
| `EnclaveIdentityHelper.sol` | Automata Testnet | [0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0](https://explorer-testnet.ata.network/address/0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0) |
|  | Ethereum Sepolia | [0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0](https://sepolia.etherscan.io/address/0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0) |
|  | Ethereum Holesky | [0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0](https://holesky.etherscan.io/address/0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0) |
|  | Base Sepolia | [0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0](https://sepolia.basescan.org/address/0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0) |
|  | OP Sepolia | [0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0](https://sepolia-optimism.etherscan.io/address/0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0) |
|  | Arbitrum Sepolia | [0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0](https://sepolia.arbiscan.io/address/0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0) |
| `FmspcTcbHelper.sol` | Automata Testnet | [0x181dc716922c84554aeA8bafa07c906F4e4C15B2](https://explorer-testnet.ata.network/address/0x181dc716922c84554aeA8bafa07c906F4e4C15B2) |
|  | Ethereum Sepolia | [0x181dc716922c84554aeA8bafa07c906F4e4C15B2](https://sepolia.etherscan.io/address/0x181dc716922c84554aeA8bafa07c906F4e4C15B2) |
|  | Ethereum Holesky | [0x181dc716922c84554aeA8bafa07c906F4e4C15B2](https://holesky.etherscan.io/address/0x181dc716922c84554aeA8bafa07c906F4e4C15B2) |
|  | Base Sepolia | [0x181dc716922c84554aeA8bafa07c906F4e4C15B2](https://sepolia.basescan.org/address/0x181dc716922c84554aeA8bafa07c906F4e4C15B2) |
|  | OP Sepolia | [0x181dc716922c84554aeA8bafa07c906F4e4C15B2](https://sepolia-optimism.etherscan.io/address/0x181dc716922c84554aeA8bafa07c906F4e4C15B2) |
|  | Arbitrum Sepolia | [0x181dc716922c84554aeA8bafa07c906F4e4C15B2](https://sepolia.arbiscan.io/address/0x181dc716922c84554aeA8bafa07c906F4e4C15B2) |
| `PCKHelper.sol` | Automata Testnet | [0xeD75bb6543c53d49f4445055Ba18380068025370](https://explorer-testnet.ata.network/address/0xeD75bb6543c53d49f4445055Ba18380068025370) |
|  | Ethereum Sepolia | [0xeD75bb6543c53d49f4445055Ba18380068025370](https://sepolia.etherscan.io/address/0xeD75bb6543c53d49f4445055Ba18380068025370) |
|  | Ethereum Holesky | [0xeD75bb6543c53d49f4445055Ba18380068025370](https://holesky.etherscan.io/address/0xeD75bb6543c53d49f4445055Ba18380068025370) |
|  | Base Sepolia | [0xeD75bb6543c53d49f4445055Ba18380068025370](https://sepolia.basescan.org/address/0xeD75bb6543c53d49f4445055Ba18380068025370) |
|  | OP Sepolia | [0xeD75bb6543c53d49f4445055Ba18380068025370](https://sepolia-optimism.etherscan.io/address/0xeD75bb6543c53d49f4445055Ba18380068025370) |
|  | Arbitrum Sepolia | [0xeD75bb6543c53d49f4445055Ba18380068025370](https://sepolia.arbiscan.io/address/0xeD75bb6543c53d49f4445055Ba18380068025370) |
| `X509CRLHelper.sol` | Automata Testnet | [0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C](https://explorer-testnet.ata.network/address/0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C) |
|  | Ethereum Sepolia | [0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C](https://sepolia.etherscan.io/address/0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C) |
|  | Ethereum Holesky | [0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C](https://holesky.etherscan.io/address/0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C) |
|  | Base Sepolia | [0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C](https://sepolia.basescan.org/address/0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C) |
|  | OP Sepolia | [0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C](https://sepolia-optimism.etherscan.io/address/0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C) |
|  | Arbitrum Sepolia | [0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C](https://sepolia.arbiscan.io/address/0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C) |

<!-- #### Mainnet

|  | Network | Address |
| --- | --- | --- |
| `EnclaveIdentityHelper.sol` | Automata Mainnet | [0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0](https://explorer.ata.network/address/0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0) |
|  | Ethereum Mainnet | [0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0](https://etherscan.io/address/0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0) |
|  | Base Mainnet | [0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0](https://basescan.org/address/0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0) |
|  | OP Mainnet | [0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0](https://optimistic.etherscan.io/address/0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0) |
|  | World Mainnet | [0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0](https://worldchain-mainnet.explorer.alchemy.com/address/0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0) |
|  | Arbitrum Mainnet | [0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0](https://arbiscan.io/address/0x635A8A01e84cDcE1475FCeB7D57FEcadD3d1a0A0) |
| `FmspcTcbHelper.sol` | Automata Mainnet | [0x181dc716922c84554aeA8bafa07c906F4e4C15B2](https://explorer.ata.network/address/0x181dc716922c84554aeA8bafa07c906F4e4C15B2) |
|  | Ethereum Mainnet | [0xc99bF04C31bF3d026B5B47b2574FC19C1459B732](https://etherscan.io/address/0xc99bF04C31bF3d026B5B47b2574FC19C1459B732) |
|  | Base Mainnet | [0x181dc716922c84554aeA8bafa07c906F4e4C15B2](https://basescan.org/address/0x181dc716922c84554aeA8bafa07c906F4e4C15B2) |
|  | OP Mainnet | [0x181dc716922c84554aeA8bafa07c906F4e4C15B2](https://optimistic.etherscan.io/address/0x181dc716922c84554aeA8bafa07c906F4e4C15B2) |
|  | World Mainnet | [0xc99bF04C31bF3d026B5B47b2574FC19C1459B732](https://worldchain-mainnet.explorer.alchemy.com/address/0xc99bF04C31bF3d026B5B47b2574FC19C1459B732) |
|  | Arbitrum Mainnet | [0x181dc716922c84554aeA8bafa07c906F4e4C15B2](https://arbiscan.io/address/0x181dc716922c84554aeA8bafa07c906F4e4C15B2) |
| `PCKHelper.sol` | Automata Mainnet | [0xeD75bb6543c53d49f4445055Ba18380068025370](https://explorer.ata.network/address/0xeD75bb6543c53d49f4445055Ba18380068025370) |
|  | Ethereum Mainnet | [0xeD75bb6543c53d49f4445055Ba18380068025370](https://etherscan.io/address/0xeD75bb6543c53d49f4445055Ba18380068025370) |
|  | Base Mainnet | [0xeD75bb6543c53d49f4445055Ba18380068025370](https://basescan.org/address/0xeD75bb6543c53d49f4445055Ba18380068025370) |
|  | OP Mainnet | [0xeD75bb6543c53d49f4445055Ba18380068025370](https://optimistic.etherscan.io/address/0xeD75bb6543c53d49f4445055Ba18380068025370) |
|  | World Mainnet | [0xeD75bb6543c53d49f4445055Ba18380068025370](https://worldchain-mainnet.explorer.alchemy.com/address/0xeD75bb6543c53d49f4445055Ba18380068025370) |
|  | Arbitrum Mainnet | [0xeD75bb6543c53d49f4445055Ba18380068025370](https://arbiscan.io/address/0xeD75bb6543c53d49f4445055Ba18380068025370) |
| `X509CRLHelper.sol` | Automata Mainnet | [0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C](https://explorer.ata.network/address/0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C) |
|  | Ethereum Mainnet | [0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C](https://etherscan.io/address/0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C) |
|  | Base Mainnet | [0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C](https://basescan.org/address/0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C) |
|  | OP Mainnet | [0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C](https://optimistic.etherscan.io/address/0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C) |
|  | World Mainnet | [0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C](https://worldchain-mainnet.explorer.alchemy.com/address/0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C) |
|  | Arbitrum Mainnet | [0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C](https://arbiscan.io/address/0xA454FB9522631D586f3A790c6CDc6f1B70Ca903C) | -->

### Base libraries and Automata DAO contracts

The base contracts are libraries that provide the Data Access Object (DAO) APIs with similar designs inspired from the [Design Guide for Intel SGX PCCS](https://download.01.org/intel-sgx/sgx-dcap/1.21/linux/docs/SGX_DCAP_Caching_Service_Design_Guide.pdf).

Base contracts are dependent on Helper contracts to parse collaterals, and contains implementation of basic collateral authenticity check functions for upserts. Smart contract developers are encouraged to extend the base contracts to build their own custom implementation of on-chain PCCS.

Our DAO implementation can be found in the [`automata_pccs`](./src/automata_pccs/) directory.

#### Testnet

|  | Network | Address |
| --- | --- | --- |
| `AutomataEnclaveIdentityDao.sol` | Automata Testnet | [0xd74e880029cd3B6b434f16beA5F53A06989458Ee](https://explorer-testnet.ata.network/address/0xd74e880029cd3B6b434f16beA5F53A06989458Ee) |
|  | Ethereum Sepolia | [0xc3ea5Ff40263E16cD2f4413152A77e7A6b10B0C9](https://sepolia.etherscan.io/address/0xc3ea5Ff40263E16cD2f4413152A77e7A6b10B0C9) |
|  | Ethereum Holesky | [0xc3ea5Ff40263E16cD2f4413152A77e7A6b10B0C9](https://holesky.etherscan.io/address/0xc3ea5Ff40263E16cD2f4413152A77e7A6b10B0C9) |
|  | Base Sepolia | [0xd74e880029cd3B6b434f16beA5F53A06989458Ee](https://sepolia.basescan.org/address/0xd74e880029cd3B6b434f16beA5F53A06989458Ee) |
|  | OP Sepolia | [0xd74e880029cd3B6b434f16beA5F53A06989458Ee](https://sepolia-optimism.etherscan.io/address/0xd74e880029cd3B6b434f16beA5F53A06989458Ee) |
|  | Arbitrum Sepolia | [0xd74e880029cd3B6b434f16beA5F53A06989458Ee](https://sepolia.arbiscan.io/address/0xd74e880029cd3B6b434f16beA5F53A06989458Ee) |
| `AutomataFmspcTcbDao.sol` | Automata Testnet | [0xd3A3f34E8615065704cCb5c304C0cEd41bB81483](https://explorer-testnet.ata.network/address/0xd3A3f34E8615065704cCb5c304C0cEd41bB81483) |
|  | Ethereum Sepolia | [0x63eF330eAaadA189861144FCbc9176dae41A5BAf](https://sepolia.etherscan.io/address/0x63eF330eAaadA189861144FCbc9176dae41A5BAf) |
|  | Ethereum Holesky | [0x63eF330eAaadA189861144FCbc9176dae41A5BAf](https://holesky.etherscan.io/address/0x63eF330eAaadA189861144FCbc9176dae41A5BAf6) |
|  | Base Sepolia | [0xd3A3f34E8615065704cCb5c304C0cEd41bB81483](https://sepolia.basescan.org/address/0xd3A3f34E8615065704cCb5c304C0cEd41bB81483) |
|  | OP Sepolia | [0xd3A3f34E8615065704cCb5c304C0cEd41bB81483](https://sepolia-optimism.etherscan.io/address/0xd3A3f34E8615065704cCb5c304C0cEd41bB81483) |
|  | Arbitrum Sepolia | [0xd3A3f34E8615065704cCb5c304C0cEd41bB81483](https://sepolia.arbiscan.io/address/0xd3A3f34E8615065704cCb5c304C0cEd41bB81483) |
| `AutomataPckDao.sol` | Automata Testnet | [0xa4615C2a260413878241ff7605AD9577feB356A5](https://explorer-testnet.ata.network/address/0xa4615C2a260413878241ff7605AD9577feB356A5) |
|  | Ethereum Sepolia | [0x75A2BafFfb2096990246F1a2dA65801Ea2A00b36](https://sepolia.etherscan.io/address/0x75A2BafFfb2096990246F1a2dA65801Ea2A00b36) |
|  | Ethereum Holesky | [0x75A2BafFfb2096990246F1a2dA65801Ea2A00b36](https://holesky.etherscan.io/address/0x75A2BafFfb2096990246F1a2dA65801Ea2A00b36) |
|  | Base Sepolia | [0xa4615C2a260413878241ff7605AD9577feB356A5](https://sepolia.basescan.org/address/0xa4615C2a260413878241ff7605AD9577feB356A5) |
|  | OP Sepolia | [0xa4615C2a260413878241ff7605AD9577feB356A5](https://sepolia-optimism.etherscan.io/address/0xa4615C2a260413878241ff7605AD9577feB356A5) |
|  | Arbitrum Sepolia | [0xa4615C2a260413878241ff7605AD9577feB356A5](https://sepolia.arbiscan.io/address/0xa4615C2a260413878241ff7605AD9577feB356A5) |
| `AutomataPcsDao.sol` | Automata Testnet | [0xB270cD8550DA117E3accec36A90c4b0b48daD342](https://explorer-testnet.ata.network/address/0xB270cD8550DA117E3accec36A90c4b0b48daD342) |
|  | Ethereum Sepolia | [0x45CF7485A0D394130153a3630EA0729999511C2e](https://sepolia.etherscan.io/address/0x45CF7485A0D394130153a3630EA0729999511C2e) |
|  | Ethereum Holesky | [0x45CF7485A0D394130153a3630EA0729999511C2e](https://holesky.etherscan.io/address/0x45CF7485A0D394130153a3630EA0729999511C2e) |
|  | Base Sepolia | [0xB270cD8550DA117E3accec36A90c4b0b48daD342](https://sepolia.basescan.org/address/0xB270cD8550DA117E3accec36A90c4b0b48daD342) |
|  | OP Sepolia | [0xB270cD8550DA117E3accec36A90c4b0b48daD342](https://sepolia-optimism.etherscan.io/address/0xB270cD8550DA117E3accec36A90c4b0b48daD342) |
|  | Arbitrum Sepolia | [0xB270cD8550DA117E3accec36A90c4b0b48daD342](https://sepolia.arbiscan.io/address/0xB270cD8550DA117E3accec36A90c4b0b48daD342) |

<!-- #### Mainnet

|  | Network | Address |
| --- | --- | --- |
| `AutomataEnclaveIdentityDao.sol` | Automata Mainnet | [0xd74e880029cd3B6b434f16beA5F53A06989458Ee](https://explorer.ata.network/address/0xd74e880029cd3B6b434f16beA5F53A06989458Ee) |
|  | Ethereum Mainnet | [0xc3ea5Ff40263E16cD2f4413152A77e7A6b10B0C9](https://etherscan.io/address/0xc3ea5Ff40263E16cD2f4413152A77e7A6b10B0C9) |
|  | Base Mainnet | [0xd74e880029cd3B6b434f16beA5F53A06989458Ee](https://basescan.org/address/0xd74e880029cd3B6b434f16beA5F53A06989458Ee) |
|  | OP Mainnet | [0xd74e880029cd3B6b434f16beA5F53A06989458Ee](https://optimistic.etherscan.io/address/0xd74e880029cd3B6b434f16beA5F53A06989458Ee) |
|  | World Mainnet | [0x28111536292b34f37120861A46B39BF39187d73a](https://worldchain-mainnet.explorer.alchemy.com/address/0x28111536292b34f37120861A46B39BF39187d73a) |
|  | Arbitrum Mainnet | [0xd74e880029cd3B6b434f16beA5F53A06989458Ee](https://arbiscan.io/address/0xd74e880029cd3B6b434f16beA5F53A06989458Ee) |
| `AutomataFmspcTcbDao.sol` | Automata Mainnet | [0xd3A3f34E8615065704cCb5c304C0cEd41bB81483](https://explorer.ata.network/address/0xd3A3f34E8615065704cCb5c304C0cEd41bB81483) |
|  | Ethereum Mainnet | [0x63eF330eAaadA189861144FCbc9176dae41A5BAf](https://etherscan.io/address/0x63eF330eAaadA189861144FCbc9176dae41A5BAf) |
|  | Base Mainnet | [0xd3A3f34E8615065704cCb5c304C0cEd41bB81483](https://basescan.org/address/0xd3A3f34E8615065704cCb5c304C0cEd41bB81483) |
|  | OP Mainnet | [0xd3A3f34E8615065704cCb5c304C0cEd41bB81483](https://optimistic.etherscan.io/address/0xd3A3f34E8615065704cCb5c304C0cEd41bB81483) |
|  | World Mainnet | [0x868c18869f68E0E0b0b7B2B4439f7fDDd0421e6b](https://worldchain-mainnet.explorer.alchemy.com/address/0x868c18869f68E0E0b0b7B2B4439f7fDDd0421e6b) |
|  | Arbitrum Mainnet | [0xd3A3f34E8615065704cCb5c304C0cEd41bB81483](https://arbiscan.io/address/0xd3A3f34E8615065704cCb5c304C0cEd41bB81483) |
| `AutomataPckDao.sol` | Automata Mainnet | [0xa4615C2a260413878241ff7605AD9577feB356A5](https://explorer.ata.network/address/0xa4615C2a260413878241ff7605AD9577feB356A5) |
|  | Ethereum Mainnet | [0x75A2BafFfb2096990246F1a2dA65801Ea2A00b36](https://etherscan.io/address/0x75A2BafFfb2096990246F1a2dA65801Ea2A00b36) |
|  | Base Mainnet | [0xa4615C2a260413878241ff7605AD9577feB356A5](https://basescan.org/address/0xa4615C2a260413878241ff7605AD9577feB356A5) |
|  | OP Mainnet | [0xa4615C2a260413878241ff7605AD9577feB356A5](https://optimistic.etherscan.io/address/0xa4615C2a260413878241ff7605AD9577feB356A5) |
|  | World Mainnet | [0xeCc198936FcA3Ca1fDc97B8612B32185908917B0](https://worldchain-mainnet.explorer.alchemy.com/address/0xeCc198936FcA3Ca1fDc97B8612B32185908917B0) |
|  | Arbitrum Mainnet | [0xa4615C2a260413878241ff7605AD9577feB356A5](https://arbiscan.io/address/0xa4615C2a260413878241ff7605AD9577feB356A5) |
| `AutomataPcsDao.sol` | Automata Mainnet | [0xB270cD8550DA117E3accec36A90c4b0b48daD342](https://explorer.ata.network/address/0xB270cD8550DA117E3accec36A90c4b0b48daD342) |
|  | Ethereum Mainnet | [0x45CF7485A0D394130153a3630EA0729999511C2e](https://etherscan.io/address/0x45CF7485A0D394130153a3630EA0729999511C2e) |
|  | Base Mainnet | [0xB270cD8550DA117E3accec36A90c4b0b48daD342](https://basescan.org/address/0xB270cD8550DA117E3accec36A90c4b0b48daD342) |
|  | OP Mainnet | [0xB270cD8550DA117E3accec36A90c4b0b48daD342](https://optimistic.etherscan.io/address/0xB270cD8550DA117E3accec36A90c4b0b48daD342) |
|  | World Mainnet | [0x86f8865BCe8BE62CB8096b5B94fA3fB3a6ED330c](https://worldchain-mainnet.explorer.alchemy.com/address/0x86f8865BCe8BE62CB8096b5B94fA3fB3a6ED330c) |
|  | Arbitrum Mainnet | [0xB270cD8550DA117E3accec36A90c4b0b48daD342](https://arbiscan.io/address/0xB270cD8550DA117E3accec36A90c4b0b48daD342) | -->

---

### #BUIDL 🛠️

1. Install [Foundry](https://book.getfoundry.sh/getting-started/installation)

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