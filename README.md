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

<!-- Click [here](./src/helpers/) to learn more about the implementation details for Helper contracts. -->

The Helper contracts have been deployed to testnet, and can be used by both on-chain and off-chain programs.

|  | Network | Address |
| --- | --- | --- |
| `EnclaveIdentityHelper.sol` | testnet | [0xfd4a34b578B352FE1896CDafaEb0f45f993352Bf](https://explorer-testnet.ata.network/address/0xfd4a34b578B352FE1896CDafaEb0f45f993352Bf) |
|  | mainnet (preview) | [0x13BECaa512713Ac7C2d7a04ba221aD5E02D43DFE](https://explorer.ata.network/address/0x13BECaa512713Ac7C2d7a04ba221aD5E02D43DFE) |
| `FmspcTcbHelper.sol` | testnet | [0xC2A662e08A35513596E22D0aC236Ce72e59125EE](https://explorer-testnet.ata.network/address/0xC2A662e08A35513596E22D0aC236Ce72e59125EE) |
|  | mainnet (preview) | [0xc99bf04c31bf3d026b5b47b2574fc19c1459b732](https://explorer.ata.network/address/0xc99bf04c31bf3d026b5b47b2574fc19c1459b732) |
| `PCKHelper.sol` | testnet | [0x5213c0e3Ab478dbc83E8afFF8909717332E4f8E1](https://explorer-testnet.ata.network/address/0x5213c0e3Ab478dbc83E8afFF8909717332E4f8E1) |
|  | mainnet (preview) | [0x3e2fe733E444313A93Fa3f9AEd3bB203048dDE70](https://explorer.ata.network/address/0x3e2fe733E444313A93Fa3f9AEd3bB203048dDE70) |
| `X509CRLHelper.sol` | testnet | [0x12C1E13Aa2a238EAb15c2e2b6AC670266bc3C814](https://explorer-testnet.ata.network/address/0x12C1E13Aa2a238EAb15c2e2b6AC670266bc3C814) |
|  | mainnet (preview) | [0x2567245dE6E349C8B7AA82fD6FF854b844A0aEF9](https://explorer.ata.network/address/0x2567245dE6E349C8B7AA82fD6FF854b844A0aEF9) |

### Base Contracts

The Base contracts are libraries that provide the Data Access Object (DAO) APIs with similar designs inspired from the [Design Guide for Intel SGX PCCS](https://download.01.org/intel-sgx/sgx-dcap/1.21/linux/docs/SGX_DCAP_Caching_Service_Design_Guide.pdf).

Base contracts are dependent on Helper contracts to parse collaterals, and contains implementation of basic collateral authenticity check functions for upserts. Smart contract developers are encouraged to extend the base contracts to build their own custom implementation of on-chain PCCS.

<!-- Click [here](./src/bases/) to learn more about each DAOs. -->

Our DAO implementation can be found in the [`automata_pccs`](./src/automata_pccs/) directory, and are deployed to testnet.

|  | Network | Address |
| --- | --- | --- |
| `AutomataEnclaveIdentityDao.sol` | testnet | [0x413272890ab9F155a47A5F90a404Fb51aa259087](https://explorer-testnet.ata.network/address/0x413272890ab9F155a47A5F90a404Fb51aa259087) |
|  | mainnet (preview) | [0x28111536292b34f37120861A46B39BF39187d73a](https://explorer.ata.network/address/0x28111536292b34f37120861A46B39BF39187d73a) |
| `AutomataFmspcTcbDao.sol` | testnet | [0x7c04B466DebA13D48116b1339C62b35B9805E5A0](https://explorer-testnet.ata.network/address/0x7c04B466DebA13D48116b1339C62b35B9805E5A0) |
|  | mainnet (preview) | [0x868c18869f68E0E0b0b7B2B4439f7fDDd0421e6b](https://explorer.ata.network/address/0x868c18869f68E0E0b0b7B2B4439f7fDDd0421e6b) |
| `AutomataPckDao.sol` | testnet | [0x6D4cA6AE5315EBBcb4331c82531db0ad8853Eb31](https://explorer-testnet.ata.network/address/0x6D4cA6AE5315EBBcb4331c82531db0ad8853Eb31) |
|  | mainnet (preview) | [0xeCc198936FcA3Ca1fDc97B8612B32185908917B0](https://explorer.ata.network/address/0xeCc198936FcA3Ca1fDc97B8612B32185908917B0) |
| `AutomataPcsDao.sol` | testnet | [0xD0335cbC73CA2f8EDd98a2BE3909f55642F414D7](https://explorer-testnet.ata.network/address/0xD0335cbC73CA2f8EDd98a2BE3909f55642F414D7) |
|  | mainnet (preview) | [0x86f8865bce8be62cb8096b5b94fa3fb3a6ed330c](https://explorer.ata.network/address/0x86f8865bce8be62cb8096b5b94fa3fb3a6ed330c) |

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
