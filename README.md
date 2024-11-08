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
> The current deployment are based on the un-audited [v0](https://github.com/automata-network/automata-on-chain-pccs/tree/v0) branch. We are currently getting our contracts audited, and will be re-deploying production-ready contracts then.

There are two sets of contracts, i.e. the **Helper** and **Base**.

### Helper Contracts

The Helper contracts provide APIs for parsing collaterals and converting into Solidity structs, i.e. QEIdentity.json, TCBInfo.json, basic DER-decoder for PCK X509 leaf certificate and extensions and X509 CRLs.

#### Testnet

|  | Network | Address |
| --- | --- | --- |
| `EnclaveIdentityHelper.sol` | Automata Testnet | [0xfd4a34b578B352FE1896CDafaEb0f45f993352Bf](https://explorer-testnet.ata.network/address/0xfd4a34b578B352FE1896CDafaEb0f45f993352Bf) |
|  | Ethereum Holesky Testnet | [0xEea41Ae0cB09A478b80425Ae61c85e445E83c415](https://holesky.etherscan.io/address/0xEea41Ae0cB09A478b80425Ae61c85e445E83c415) |
|  | Ethereum Sepolia Testnet | [0xA5D1EC1CcCdF2f60Df05cf1e110352F696bA4C64](https://Sepolia.etherscan.io/address/0xA5D1EC1CcCdF2f60Df05cf1e110352F696bA4C64) |
| `FmspcTcbHelper.sol` | Automata Testnet | [0xC2A662e08A35513596E22D0aC236Ce72e59125EE](https://explorer-testnet.ata.network/address/0xC2A662e08A35513596E22D0aC236Ce72e59125EE) |
|  | Ethereum Holesky Testnet | [0xc728DD0FcD76CD9166F66e1CD8002dE86d6525B8](https://holesky.etherscan.io/address/0xc728DD0FcD76CD9166F66e1CD8002dE86d6525B8) |
|  | Ethereum Sepolia Testnet | [0x2404DAc28D18847937CcAdC1b29d3403AED3BB6C](https://Sepolia.etherscan.io/address/0x2404DAc28D18847937CcAdC1b29d3403AED3BB6C) |
| `PCKHelper.sol` | Automata Testnet | [0x5213c0e3Ab478dbc83E8afFF8909717332E4f8E1](https://explorer-testnet.ata.network/address/0x5213c0e3Ab478dbc83E8afFF8909717332E4f8E1) |
|  | Ethereum Holesky Testnet | [0xDe20629a87C371668bB371ef1d77D9D167E52021](https://holesky.etherscan.io/address/0xDe20629a87C371668bB371ef1d77D9D167E52021) |
|  | Ethereum Sepolia Testnet | [0xBf1ec53BA4768D1470F037898C6a3ff9Ed3Fe394](https://Sepolia.etherscan.io/address/0xBf1ec53BA4768D1470F037898C6a3ff9Ed3Fe394) |
| `X509CRLHelper.sol` | Automata Testnet | [0x12C1E13Aa2a238EAb15c2e2b6AC670266bc3C814](https://explorer-testnet.ata.network/address/0x12C1E13Aa2a238EAb15c2e2b6AC670266bc3C814) |
|  | Ethereum Holesky Testnet | [0x3ACBfad7460e2fae32A31f863e1A38F7a002cEA8](https://holesky.etherscan.io/address/0x3ACBfad7460e2fae32A31f863e1A38F7a002cEA8) |
|  | Ethereum Sepolia Testnet | [0x2a81585F6d8ACB52DED417De5946486394b54B63](https://Sepolia.etherscan.io/address/0x2a81585F6d8ACB52DED417De5946486394b54B63) |

#### Mainnet
|  | Network | Address |
| --- | --- | --- |
| `EnclaveIdentityHelper.sol` | Automata Mainnet | [0x13BECaa512713Ac7C2d7a04ba221aD5E02D43DFE](https://explorer.ata.network/address/0x13BECaa512713Ac7C2d7a04ba221aD5E02D43DFE) |
| `FmspcTcbHelper.sol` | Automata Mainnet | [0xc99bf04c31bf3d026b5b47b2574fc19c1459b732](https://explorer.ata.network/address/0xc99bf04c31bf3d026b5b47b2574fc19c1459b732) |
| `PCKHelper.sol` | Automata Mainnet | [0x3e2fe733E444313A93Fa3f9AEd3bB203048dDE70](https://explorer.ata.network/address/0x3e2fe733E444313A93Fa3f9AEd3bB203048dDE70) |
| `X509CRLHelper.sol` | Automata Mainnet | [0x2567245dE6E349C8B7AA82fD6FF854b844A0aEF9](https://explorer.ata.network/address/0x2567245dE6E349C8B7AA82fD6FF854b844A0aEF9) |

### Base libraries and Automata DAO contracts

The base contracts are libraries that provide the Data Access Object (DAO) APIs with similar designs inspired from the [Design Guide for Intel SGX PCCS](https://download.01.org/intel-sgx/sgx-dcap/1.21/linux/docs/SGX_DCAP_Caching_Service_Design_Guide.pdf).

Base contracts are dependent on Helper contracts to parse collaterals, and contains implementation of basic collateral authenticity check functions for upserts. Smart contract developers are encouraged to extend the base contracts to build their own custom implementation of on-chain PCCS.

Our DAO implementation can be found in the [`automata_pccs`](./src/automata_pccs/) directory, and have been deployed to various testnets and Automata mainnet.

#### Testnet

|  | Network | Address |
| --- | --- | --- |
| `AutomataEnclaveIdentityDao.sol` | Automata Testnet | [0x413272890ab9F155a47A5F90a404Fb51aa259087](https://explorer-testnet.ata.network/address/0x413272890ab9F155a47A5F90a404Fb51aa259087) |
|  | Ethereum Holesky Testnet | [0x9f4b0fB3A95072bD133082e9683A3536669EFE07](https://holesky.etherscan.io/address/0x9f4b0fB3A95072bD133082e9683A3536669EFE07) |
|  | Ethereum Sepolia Testnet | [0x4bb680A5e6Ad6228E7d334903B0Ce10EF60c961C](https://Sepolia.etherscan.io/address/0x4bb680A5e6Ad6228E7d334903B0Ce10EF60c961C) |
| `AutomataFmspcTcbDao.sol` | Automata Testnet | [0x7c04B466DebA13D48116b1339C62b35B9805E5A0](https://explorer-testnet.ata.network/address/0x7c04B466DebA13D48116b1339C62b35B9805E5A0) |
|  | Ethereum Holesky Testnet | [0xaB5074445E5ae3C650553d5a7560B3A7121635B9](https://holesky.etherscan.io/address/0xaB5074445E5ae3C650553d5a7560B3A7121635B9) |
|  | Ethereum Sepolia Testnet | [0xF790b1C23e6508A6135Ce88450eC0A59Af0B9896](https://Sepolia.etherscan.io/address/0xF790b1C23e6508A6135Ce88450eC0A59Af0B9896) |
| `AutomataPckDao.sol` | Automata Testnet | [0x6D4cA6AE5315EBBcb4331c82531db0ad8853Eb31](https://explorer-testnet.ata.network/address/0x6D4cA6AE5315EBBcb4331c82531db0ad8853Eb31) |
|  | Ethereum Holesky Testnet | [0x5B2d7781E3c44966769484daBCdc435EFD281c34](https://holesky.etherscan.io/address/0x5B2d7781E3c44966769484daBCdc435EFD281c34) |
|  | Ethereum Sepolia Testnet | [0x3eA9D905Cb79586C2184f329e6a651D97F2ebee3](https://Sepolia.etherscan.io/address/0x3eA9D905Cb79586C2184f329e6a651D97F2ebee3) |
| `AutomataPcsDao.sol` | Automata Testnet | [0xD0335cbC73CA2f8EDd98a2BE3909f55642F414D7](https://explorer-testnet.ata.network/address/0xD0335cbC73CA2f8EDd98a2BE3909f55642F414D7) |
|  | Ethereum Holesky Testnet | [0x66FdB4E72d2F4a7e2081bf83F1FfACC9bbCb384b](https://holesky.etherscan.io/address/0x66FdB4E72d2F4a7e2081bf83F1FfACC9bbCb384b) |
|  | Ethereum Sepolia Testnet | [0x348DA46aA11188f641f01dbe247b25FFA5FFB9c4](https://Sepolia.etherscan.io/address/0x348DA46aA11188f641f01dbe247b25FFA5FFB9c4) |

### Mainnet

|  | Network | Address |
| --- | --- | --- |
| `AutomataEnclaveIdentityDao.sol` | Automata Mainnet | [0x28111536292b34f37120861A46B39BF39187d73a](https://explorer.ata.network/address/0x28111536292b34f37120861A46B39BF39187d73a) |
| `AutomataFmspcTcbDao.sol` | Automata Mainnet | [0x868c18869f68E0E0b0b7B2B4439f7fDDd0421e6b](https://explorer.ata.network/address/0x868c18869f68E0E0b0b7B2B4439f7fDDd0421e6b) |
| `AutomataPckDao.sol` | Automata Mainnet | [0xeCc198936FcA3Ca1fDc97B8612B32185908917B0](https://explorer.ata.network/address/0xeCc198936FcA3Ca1fDc97B8612B32185908917B0) |
| `AutomataPcsDao.sol` | Automata Mainnet | [0x86f8865bce8be62cb8096b5b94fa3fb3a6ed330c](https://explorer.ata.network/address/0x86f8865bce8be62cb8096b5b94fa3fb3a6ed330c) |

---

### #BUIDL 🛠️

- Install [Foundry](https://book.getfoundry.sh/getting-started/installation)

- Create `.env` file with the provided example.

```bash
cp .env.example .env
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
