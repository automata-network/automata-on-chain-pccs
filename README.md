# Automata On Chain PCCS

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
| `EnclaveIdentityHelper.sol` | testnet | [0xfd4a34b578B352FE1896CDafaEb0f45f993352Bf]() |
| `FmspcTcbHelper.sol` | testnet | [0xC2A662e08A35513596E22D0aC236Ce72e59125EE]() |
| `PCKHelper.sol` | testnet | [0x5213c0e3Ab478dbc83E8afFF8909717332E4f8E1]() |
| `X509CRLHelper.sol` | testnet | [0x12C1E13Aa2a238EAb15c2e2b6AC670266bc3C814]() |

### Base Contracts

The Base contracts are libraries that provide the Data Access Object (DAO) APIs with similar designs inspired from the [Design Guide for Intel SGX PCCS](https://download.01.org/intel-sgx/sgx-dcap/1.21/linux/docs/SGX_DCAP_Caching_Service_Design_Guide.pdf).

Base contracts are dependent on Helper contracts to parse collaterals, and contains implementation of basic collateral authenticity check functions for upserts. Smart contract developers are encouraged to extend the base contracts to build their own custom implementation of on-chain PCCS.

<!-- Click [here](./src/bases/) to learn more about each DAOs. -->

Our DAO implementation can be found in the [`automata_pccs`](./src/automata_pccs/) directory, and are deployed to testnet.

|  | Network | Address |
| --- | --- | --- |
| `AutomataEnclaveIdentity.sol` | testnet | [0x413272890ab9F155a47A5F90a404Fb51aa259087]() |
| `AutomataFmspcTcbDao.sol` | testnet | [0x7c04B466DebA13D48116b1339C62b35B9805E5A0]() |
| `AutomataPckDao.sol` | testnet | [0x6D4cA6AE5315EBBcb4331c82531db0ad8853Eb31]() |
| `AutomataPcsDao.sol` | testnet | [0xD0335cbC73CA2f8EDd98a2BE3909f55642F414D7]() |

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