# Automata Onchain PCCS

## Release Note

---

## What’s Changed

- Introduced TCB Evaluation Dsta Number Helper and Data Access Object.
    - The DAO contains a list of TCB Evaluation Data Number that is actively supported by Intel.
    - Implementation of `early()` or `standard()` methods in the DAO.
        - `early()` returns the latest TCB Evaluation Data Number.
        - `standard()` returns the highest TCB Evaluation Data Number that was issued at least one year after the corresponding TCB Recovery Event.
    - Click [here](https://www.intel.com/content/www/us/en/developer/articles/technical/software-security-guidance/best-practices/trusted-computing-base-recovery.html?wapkw=intel%20software%20guard%20extension%20trusted%20computing%20base%20recovery) to learn more TCB Recovery Events.
- Each instance of FMSPC TCB Info and QE Identity DAO contracts are now tied to a specific TCB Evaluation Data Number.
    - In other words, a new TCB Recovery Event would warrant a new deployment for both FMSPC TCB Info and QE Identity DAO contracts.
- This release does not affect the remaining DAOs, i.e. PcsDAO and PckDAO, and existing Helpers, i.e. EnclaveIdentityHelper, FmspcTcbHelper, PCKHelper and X509CRLHelper. Therefore, no changes to their contract addresses.

---

## Deployment

### Helper Contracts

#### Testnet

|  | Network | Address |
| --- | --- | --- |
| `TcbEvalHelper.sol` | Automata Testnet | [0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC](https://explorer-testnet.ata.network/address/0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC) |
|  | Ethereum Sepolia | [0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC](https://sepolia.etherscan.io/address/0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC) |
|  | Ethereum Holesky | [0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC](https://holesky.etherscan.io/address/0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC) |

#### Mainnet

|  | Network | Address |
| --- | --- | --- |
| `TcbEvalHelper.sol` | Automata Mainnet | [0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC](https://explorer.ata.network/address/0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC) |

### Automata DAO Contracts

#### Testnet

##### Automata Testnet

| Contract | TCB Evaluation Data Number | Address |
| --- | --- | --- |
| `AutomataTcbEvalDao` | N/A | [0xcF614258C68730D8cB9713AcAe425875D1FDb370](https://explorer-testnet.ata.network/address/0xcF614258C68730D8cB9713AcAe425875D1FDb370) |
| `AutomataFmspcTcbDaoVersioned` | 17 | [0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306](https://explorer-testnet.ata.network/address/0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306) |
| | 18 | [0x62E8Cd513B12F248804123f7ed12A0601B79FBAc](https://explorer-testnet.ata.network/address/0x62E8Cd513B12F248804123f7ed12A0601B79FBAc) |
| | 19 | [0x43cdd3490785059423A17a90C1d8f46382C518D2](https://explorer-testnet.ata.network/address/0x43cdd3490785059423A17a90C1d8f46382C518D2) |
| `AutomataEnclaveIdentityDaoVersioned` | 17 | [0x29aaB215aeE14D4D843C57521BbF2D3B17b45810](https://explorer-testnet.ata.network/address/0x29aaB215aeE14D4D843C57521BbF2D3B17b45810) |
| | 18 | [0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56](https://explorer-testnet.ata.network/address/0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56) |
| | 19 | [0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0](https://explorer-testnet.ata.network/address/0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0) |

##### Ethereum Sepolia

| Contract | TCB Evaluation Data Number | Address |
| --- | --- | --- |
| `AutomataTcbEvalDao` | N/A | [0x8e1EA521a6A4832A0c3763D75ED4b8017cfB5424](https://sepolia.etherscan.io/address/0x8e1EA521a6A4832A0c3763D75ED4b8017cfB5424) |
| `AutomataFmspcTcbDaoVersioned` | 17 | [0x3A1fDF33420026d145C59bC6b3129bA81E9bF68e](https://sepolia.etherscan.io/address/0x3A1fDF33420026d145C59bC6b3129bA81E9bF68e) |
| | 18 | [0xBF3268Dcee73EfDe149d206ebB856380C6EeD374](https://sepolia.etherscan.io/address/0xBF3268Dcee73EfDe149d206ebB856380C6EeD374) |
| | 19 | [0xb1D89Fd867A1D6a122ed88c092163281c2474111](https://sepolia.etherscan.io/address/0xb1D89Fd867A1D6a122ed88c092163281c2474111) |
| `AutomataEnclaveIdentityDaoVersioned` | 17 | [0xE6fE85B78cb82e3b9C8AE57d754C86fe6774aF64](https://sepolia.etherscan.io/address/0xE6fE85B78cb82e3b9C8AE57d754C86fe6774aF64) |
| | 18 | [0x5dF358463632A8eEA0bdeF87f011F032e984b7ef](https://sepolia.etherscan.io/address/0x5dF358463632A8eEA0bdeF87f011F032e984b7ef) |
| | 19 | [0xa0DE0E975599347A76FF9A3baC59d686fE89b73C](https://sepolia.etherscan.io/address/0xa0DE0E975599347A76FF9A3baC59d686fE89b73C) |

##### Ethereum Holesky

| Contract | TCB Evaluation Data Number | Address |
| --- | --- | --- |
| `AutomataTcbEvalDao` | N/A | [0x8e1EA521a6A4832A0c3763D75ED4b8017cfB5424](https://holesky.etherscan.io/address/0x8e1EA521a6A4832A0c3763D75ED4b8017cfB5424) |
| `AutomataFmspcTcbDaoVersioned` | 17 | [0x3A1fDF33420026d145C59bC6b3129bA81E9bF68e](https://holesky.etherscan.io/address/0x3A1fDF33420026d145C59bC6b3129bA81E9bF68e) |
| | 18 | [0xBF3268Dcee73EfDe149d206ebB856380C6EeD374](https://holesky.etherscan.io/address/0xBF3268Dcee73EfDe149d206ebB856380C6EeD374) |
| | 19 | [0xb1D89Fd867A1D6a122ed88c092163281c2474111](https://holesky.etherscan.io/address/0xb1D89Fd867A1D6a122ed88c092163281c2474111) |
| `AutomataEnclaveIdentityDaoVersioned` | 17 | [0xE6fE85B78cb82e3b9C8AE57d754C86fe6774aF64](https://holesky.etherscan.io/address/0xE6fE85B78cb82e3b9C8AE57d754C86fe6774aF64) |
| | 18 | [0x5dF358463632A8eEA0bdeF87f011F032e984b7ef](https://holesky.etherscan.io/address/0x5dF358463632A8eEA0bdeF87f011F032e984b7ef) |
| | 19 | [0xa0DE0E975599347A76FF9A3baC59d686fE89b73C](https://holesky.etherscan.io/address/0xa0DE0E975599347A76FF9A3baC59d686fE89b73C) |

#### Mainnet

##### Automata Mainnet

| Contract | TCB Evaluation Data Number | Address |
| --- | --- | --- |
| `AutomataTcbEvalDao` | N/A | [0xcF614258C68730D8cB9713AcAe425875D1FDb370](https://explorer.ata.network/address/0xcF614258C68730D8cB9713AcAe425875D1FDb370) |
| `AutomataFmspcTcbDaoVersioned` | 17 | [0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306](https://explorer.ata.network/address/0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306) |
| | 18 | [0x62E8Cd513B12F248804123f7ed12A0601B79FBAc](https://explorer.ata.network/address/0x62E8Cd513B12F248804123f7ed12A0601B79FBAc) |
| | 19 | [0x43cdd3490785059423A17a90C1d8f46382C518D2](https://explorer.ata.network/address/0x43cdd3490785059423A17a90C1d8f46382C518D2) |
| `AutomataEnclaveIdentityDaoVersioned` | 17 | [0x29aaB215aeE14D4D843C57521BbF2D3B17b45810](https://explorer.ata.network/address/0x29aaB215aeE14D4D843C57521BbF2D3B17b45810) |
| | 18 | [0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56](https://explorer.ata.network/address/0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56) |
| | 19 | [0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0](https://explorer.ata.network/address/0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0) |