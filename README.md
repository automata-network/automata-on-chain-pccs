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
| `EnclaveIdentityHelper.sol` | Automata Testnet | [0xae27D762EED6958bc34b358bd7C78c7211fe77F8](https://explorer-testnet.ata.network/address/0xae27D762EED6958bc34b358bd7C78c7211fe77F8) |
| `FmspcTcbHelper.sol` | Automata Testnet | [0x71056B540b4E60D0E8eFb55FAd487C486B09FFF5](https://explorer-testnet.ata.network/address/0x71056B540b4E60D0E8eFb55FAd487C486B09FFF5) |
| `PCKHelper.sol` | Automata Testnet | [0x4Aca9C0EB063401C9F5c2Fc4487DBC5ccF1C9E2B](https://explorer-testnet.ata.network/address/0x4Aca9C0EB063401C9F5c2Fc4487DBC5ccF1C9E2B) |
| `X509CRLHelper.sol` | Automata Testnet | [0x6e204fEAe40F668a06E78a83b66185FFC8892DDA](https://explorer-testnet.ata.network/address/0x6e204fEAe40F668a06E78a83b66185FFC8892DDA) |

### Base libraries and Automata DAO contracts

The base contracts are libraries that provide the Data Access Object (DAO) APIs with similar designs inspired from the [Design Guide for Intel SGX PCCS](https://download.01.org/intel-sgx/sgx-dcap/1.21/linux/docs/SGX_DCAP_Caching_Service_Design_Guide.pdf).

Base contracts are dependent on Helper contracts to parse collaterals, and contains implementation of basic collateral authenticity check functions for upserts. Smart contract developers are encouraged to extend the base contracts to build their own custom implementation of on-chain PCCS.

Our DAO implementation can be found in the [`automata_pccs`](./src/automata_pccs/) directory.

#### Testnet

|  | Network | Address |
| --- | --- | --- |
| `AutomataEnclaveIdentityDao.sol` | Automata Testnet | [0x413272890ab9F155a47A5F90a404Fb51aa259087](https://explorer-testnet.ata.network/address/0x413272890ab9F155a47A5F90a404Fb51aa259087) |
| `AutomataFmspcTcbDao.sol` | Automata Testnet | [0x9c54C72867b07caF2e6255CE32983c28aFE40F26](https://explorer-testnet.ata.network/address/0x9c54C72867b07caF2e6255CE32983c28aFE40F26) |
| `AutomataPckDao.sol` | Automata Testnet | [0x722525B96b62e182F8A095af0a79d4EA2037795C](https://explorer-testnet.ata.network/address/0x722525B96b62e182F8A095af0a79d4EA2037795C) |
| `AutomataPcsDao.sol` | Automata Testnet | [0xcf171ACd6c0a776f9d3E1F6Cac8067c982Ac6Ce1](https://explorer-testnet.ata.network/address/0xcf171ACd6c0a776f9d3E1F6Cac8067c982Ac6Ce1) |

---

### #BUIDL 🛠️

- Install [Foundry](https://book.getfoundry.sh/getting-started/installation)

- Create `.env` file with the provided example.

```bash
cp env/.{network}.env.example .env
```

- Compile the contracts

```bash
forge build
```

- Run tests

```bash
forge test
```

To view gas report, pass the `--gas-report` flag.

#### Deployment

- Deploy the Helper contracts

```bash
./script/helper/deploy.sh
```

If you are having issues running the script, try changing the permission settings.

```bash
chmod +x ./script/helper/deploy.sh
```

Make sure to update `.env` file with the appropriate addresses, then run `source .env`.

- Deploy `automata-pccs`

```bash
forge script DeployAutomataDao --rpc-url $RPC_URL -vvvv --broadcast --sig "deployAll(bool)" true
```

Make sure to update `.env` file with the appropriate addresses, then run `source .env`.

Once you have deployed all Automata DAOs, you must grant them write access to [`AutomataDaoStorage`](./src/automata_pccs//shared/AutomataDaoStorage.sol) by running:

```bash
forge script ConfigureAutomataDao -rpc-url $RPC_URL -vvvv --broadcast --sig "updateStorageDao()"
```
