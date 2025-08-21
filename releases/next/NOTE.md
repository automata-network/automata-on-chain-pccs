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
|  | Ethereum Hoodi | [0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC](https://hoodi.etherscan.io/address/0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC) |
|  | BNB Testnet | [0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC](https://testnet.bscscan.com/address/0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC) |
|  | Polygon Amoy | [0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC](https://amoy.polygonscan.com/address/0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC) |
|  | Avalanche C Fuji | [0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC](https://testnet.snowtrace.io/address/0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC) |
|  | Base Sepolia | [0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC](https://sepolia.basescan.org/address/0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC) |
|  | OP Sepolia | [0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC](https://sepolia-optimism.etherscan.io/address/0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC) |
|  | World Sepolia | [0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC](https://sepolia.worldscan.org/address/0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC) |
|  | Arbitrum Sepolia | [0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC](https://sepolia.arbiscan.io/address/0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC) |
|  | Unichain Sepolia | [0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC](https://unichain-sepolia.blockscout.com/address/0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC) |

#### Mainnet

|  | Network | Address |
| --- | --- | --- |
| `TcbEvalHelper.sol` | Automata Mainnet | [0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC](https://explorer.ata.network/address/0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC) |
|  | Base Mainnet | [0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC](https://basescan.org/address/0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC) |
|  | OP Mainnet | [0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC](https://optimistic.etherscan.io/address/0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC) |
|  | World Mainnet | [0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC](https://worldscan.org/address/0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC) |
|  | Arbitrum Mainnet | [0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC](https://arbiscan.io/address/0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC) |
|  | Polygon Mainnet | [0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC](https://polygonscan.com/address/0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC) |
|  | BNB Mainnet | [0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC](https://bscscan.com/address/0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC) |
|  | Avalanche C Mainnet | [0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC](https://snowtrace.io/address/0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC) |
|  | Unichain Mainnet | [0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC](https://unichain.blockscout.com/address/0xc02eCE21bD137410bc8edD30886bA6C7d255F3cC) |

---

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

##### Ethereum Hoodi

| Contract | TCB Evaluation Data Number | Address |
| --- | --- | --- |
| `AutomataTcbEvalDao` | N/A | [0x8e1EA521a6A4832A0c3763D75ED4b8017cfB5424](https://hoodi.etherscan.io/address/0x8e1EA521a6A4832A0c3763D75ED4b8017cfB5424) |
| `AutomataFmspcTcbDaoVersioned` | 17 | [0x3A1fDF33420026d145C59bC6b3129bA81E9bF68e](https://hoodi.etherscan.io/address/0x3A1fDF33420026d145C59bC6b3129bA81E9bF68e) |
| | 18 | [0xBF3268Dcee73EfDe149d206ebB856380C6EeD374](https://hoodi.etherscan.io/address/0xBF3268Dcee73EfDe149d206ebB856380C6EeD374) |
| | 19 | [0xb1D89Fd867A1D6a122ed88c092163281c2474111](https://hoodi.etherscan.io/address/0xb1D89Fd867A1D6a122ed88c092163281c2474111) |
| `AutomataEnclaveIdentityDaoVersioned` | 17 | [0xE6fE85B78cb82e3b9C8AE57d754C86fe6774aF64](https://hoodi.etherscan.io/address/0xE6fE85B78cb82e3b9C8AE57d754C86fe6774aF64) |
| | 18 | [0x5dF358463632A8eEA0bdeF87f011F032e984b7ef](https://hoodi.etherscan.io/address/0x5dF358463632A8eEA0bdeF87f011F032e984b7ef) |
| | 19 | [0xa0DE0E975599347A76FF9A3baC59d686fE89b73C](https://hoodi.etherscan.io/address/0xa0DE0E975599347A76FF9A3baC59d686fE89b73C) |

##### BNB Testnet

| Contract | TCB Evaluation Data Number | Address |
| --- | --- | --- |
| `AutomataTcbEvalDao` | N/A | [0xcF614258C68730D8cB9713AcAe425875D1FDb370](https://testnet.bscscan.com/address/0xcF614258C68730D8cB9713AcAe425875D1FDb370) |
| `AutomataFmspcTcbDaoVersioned` | 17 | [0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306](https://testnet.bscscan.com/address/0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306) |
| | 18 | [0x62E8Cd513B12F248804123f7ed12A0601B79FBAc](https://testnet.bscscan.com/address/0x62E8Cd513B12F248804123f7ed12A0601B79FBAc) |
| | 19 | [0x43cdd3490785059423A17a90C1d8f46382C518D2](https://testnet.bscscan.com/address/0x43cdd3490785059423A17a90C1d8f46382C518D2) |
| `AutomataEnclaveIdentityDaoVersioned` | 17 | [0x29aaB215aeE14D4D843C57521BbF2D3B17b45810](https://testnet.bscscan.com/address/0x29aaB215aeE14D4D843C57521BbF2D3B17b45810) |
| | 18 | [0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56](https://testnet.bscscan.com/address/0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56) |
| | 19 | [0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0](https://testnet.bscscan.com/address/0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0) |

##### Polygon Amoy

| Contract | TCB Evaluation Data Number | Address |
| --- | --- | --- |
| `AutomataTcbEvalDao` | N/A | [0xcF614258C68730D8cB9713AcAe425875D1FDb370](https://amoy.polygonscan.com/address/0xcF614258C68730D8cB9713AcAe425875D1FDb370) |
| `AutomataFmspcTcbDaoVersioned` | 17 | [0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306](https://amoy.polygonscan.com/address/0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306) |
| | 18 | [0x62E8Cd513B12F248804123f7ed12A0601B79FBAc](https://amoy.polygonscan.com/address/0x62E8Cd513B12F248804123f7ed12A0601B79FBAc) |
| | 19 | [0x43cdd3490785059423A17a90C1d8f46382C518D2](https://amoy.polygonscan.com/address/0x43cdd3490785059423A17a90C1d8f46382C518D2) |
| `AutomataEnclaveIdentityDaoVersioned` | 17 | [0x29aaB215aeE14D4D843C57521BbF2D3B17b45810](https://amoy.polygonscan.com/address/0x29aaB215aeE14D4D843C57521BbF2D3B17b45810) |
| | 18 | [0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56](https://amoy.polygonscan.com/address/0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56) |
| | 19 | [0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0](https://amoy.polygonscan.com/address/0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0) |

##### Avalanche C Fuji

| Contract | TCB Evaluation Data Number | Address |
| --- | --- | --- |
| `AutomataTcbEvalDao` | N/A | [0x8e1EA521a6A4832A0c3763D75ED4b8017cfB5424](https://testnet.snowtrace.io/address/0x8e1EA521a6A4832A0c3763D75ED4b8017cfB5424) |
| `AutomataFmspcTcbDaoVersioned` | 17 | [0x3A1fDF33420026d145C59bC6b3129bA81E9bF68e](https://testnet.snowtrace.io/address/0x3A1fDF33420026d145C59bC6b3129bA81E9bF68e) |
| | 18 | [0xBF3268Dcee73EfDe149d206ebB856380C6EeD374](https://testnet.snowtrace.io/address/0xBF3268Dcee73EfDe149d206ebB856380C6EeD374) |
| | 19 | [0xb1D89Fd867A1D6a122ed88c092163281c2474111](https://testnet.snowtrace.io/address/0xb1D89Fd867A1D6a122ed88c092163281c2474111) |
| `AutomataEnclaveIdentityDaoVersioned` | 17 | [0xE6fE85B78cb82e3b9C8AE57d754C86fe6774aF64](https://testnet.snowtrace.io/address/0xE6fE85B78cb82e3b9C8AE57d754C86fe6774aF64) |
| | 18 | [0x5dF358463632A8eEA0bdeF87f011F032e984b7ef](https://testnet.snowtrace.io/address/0x5dF358463632A8eEA0bdeF87f011F032e984b7ef) |
| | 19 | [0xa0DE0E975599347A76FF9A3baC59d686fE89b73C](https://testnet.snowtrace.io/address/0xa0DE0E975599347A76FF9A3baC59d686fE89b73C) |

##### Base Sepolia

| Contract | TCB Evaluation Data Number | Address |
| --- | --- | --- |
| `AutomataTcbEvalDao` | N/A | [0xcF614258C68730D8cB9713AcAe425875D1FDb370](https://sepolia.basescan.org/address/0xcF614258C68730D8cB9713AcAe425875D1FDb370) |
| `AutomataFmspcTcbDaoVersioned` | 17 | [0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306](https://sepolia.basescan.org/address/0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306) |
| | 18 | [0x62E8Cd513B12F248804123f7ed12A0601B79FBAc](https://sepolia.basescan.org/address/0x62E8Cd513B12F248804123f7ed12A0601B79FBAc) |
| | 19 | [0x43cdd3490785059423A17a90C1d8f46382C518D2](https://sepolia.basescan.org/address/0x43cdd3490785059423A17a90C1d8f46382C518D2) |
| `AutomataEnclaveIdentityDaoVersioned` | 17 | [0x29aaB215aeE14D4D843C57521BbF2D3B17b45810](https://sepolia.basescan.org/address/0x29aaB215aeE14D4D843C57521BbF2D3B17b45810) |
| | 18 | [0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56](https://sepolia.basescan.org/address/0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56) |
| | 19 | [0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0](https://sepolia.basescan.org/address/0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0) |

##### OP Sepolia

| Contract | TCB Evaluation Data Number | Address |
| --- | --- | --- |
| `AutomataTcbEvalDao` | N/A | [0xcF614258C68730D8cB9713AcAe425875D1FDb370](https://sepolia-optimism.etherscan.io/address/0xcF614258C68730D8cB9713AcAe425875D1FDb370) |
| `AutomataFmspcTcbDaoVersioned` | 17 | [0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306](https://sepolia-optimism.etherscan.io/address/0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306) |
| | 18 | [0x62E8Cd513B12F248804123f7ed12A0601B79FBAc](https://sepolia-optimism.etherscan.io/address/0x62E8Cd513B12F248804123f7ed12A0601B79FBAc) |
| | 19 | [0x43cdd3490785059423A17a90C1d8f46382C518D2](https://sepolia-optimism.etherscan.io/address/0x43cdd3490785059423A17a90C1d8f46382C518D2) |
| `AutomataEnclaveIdentityDaoVersioned` | 17 | [0x29aaB215aeE14D4D843C57521BbF2D3B17b45810](https://sepolia-optimism.etherscan.io/address/0x29aaB215aeE14D4D843C57521BbF2D3B17b45810) |
| | 18 | [0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56](https://sepolia-optimism.etherscan.io/address/0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56) |
| | 19 | [0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0](https://sepolia-optimism.etherscan.io/address/0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0) |

##### World Sepolia

| Contract | TCB Evaluation Data Number | Address |
| --- | --- | --- |
| `AutomataTcbEvalDao` | N/A | [0xcF614258C68730D8cB9713AcAe425875D1FDb370](https://sepolia.worldscan.org/address/0xcF614258C68730D8cB9713AcAe425875D1FDb370) |
| `AutomataFmspcTcbDaoVersioned` | 17 | [0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306](https://sepolia.worldscan.org/address/0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306) |
| | 18 | [0x62E8Cd513B12F248804123f7ed12A0601B79FBAc](https://sepolia.worldscan.org/address/0x62E8Cd513B12F248804123f7ed12A0601B79FBAc) |
| | 19 | [0x43cdd3490785059423A17a90C1d8f46382C518D2](https://sepolia.worldscan.org/address/0x43cdd3490785059423A17a90C1d8f46382C518D2) |
| `AutomataEnclaveIdentityDaoVersioned` | 17 | [0x29aaB215aeE14D4D843C57521BbF2D3B17b45810](https://sepolia.worldscan.org/address/0x29aaB215aeE14D4D843C57521BbF2D3B17b45810) |
| | 18 | [0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56](https://sepolia.worldscan.org/address/0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56) |
| | 19 | [0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0](https://sepolia.worldscan.org/address/0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0) |

##### Arbitrum Sepolia

| Contract | TCB Evaluation Data Number | Address |
| --- | --- | --- |
| `AutomataTcbEvalDao` | N/A | [0xcF614258C68730D8cB9713AcAe425875D1FDb370](https://sepolia.arbiscan.io/address/0xcF614258C68730D8cB9713AcAe425875D1FDb370) |
| `AutomataFmspcTcbDaoVersioned` | 17 | [0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306](https://sepolia.arbiscan.io/address/0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306) |
| | 18 | [0x62E8Cd513B12F248804123f7ed12A0601B79FBAc](https://sepolia.arbiscan.io/address/0x62E8Cd513B12F248804123f7ed12A0601B79FBAc) |
| | 19 | [0x43cdd3490785059423A17a90C1d8f46382C518D2](https://sepolia.arbiscan.io/address/0x43cdd3490785059423A17a90C1d8f46382C518D2) |
| `AutomataEnclaveIdentityDaoVersioned` | 17 | [0x29aaB215aeE14D4D843C57521BbF2D3B17b45810](https://sepolia.arbiscan.io/address/0x29aaB215aeE14D4D843C57521BbF2D3B17b45810) |
| | 18 | [0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56](https://sepolia.arbiscan.io/address/0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56) |
| | 19 | [0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0](https://sepolia.arbiscan.io/address/0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0) |

##### Unichain Sepolia

| Contract | TCB Evaluation Data Number | Address |
| --- | --- | --- |
| `AutomataTcbEvalDao` | N/A | [0xcF614258C68730D8cB9713AcAe425875D1FDb370](https://unichain-sepolia.blockscout.com/address/0xcF614258C68730D8cB9713AcAe425875D1FDb370) |
| `AutomataFmspcTcbDaoVersioned` | 17 | [0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306](https://unichain-sepolia.blockscout.com/address/0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306) |
| | 18 | [0x62E8Cd513B12F248804123f7ed12A0601B79FBAc](https://unichain-sepolia.blockscout.com/address/0x62E8Cd513B12F248804123f7ed12A0601B79FBAc) |
| | 19 | [0x43cdd3490785059423A17a90C1d8f46382C518D2](https://unichain-sepolia.blockscout.com/address/0x43cdd3490785059423A17a90C1d8f46382C518D2) |
| `AutomataEnclaveIdentityDaoVersioned` | 17 | [0x29aaB215aeE14D4D843C57521BbF2D3B17b45810](https://unichain-sepolia.blockscout.com/address/0x29aaB215aeE14D4D843C57521BbF2D3B17b45810) |
| | 18 | [0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56](https://unichain-sepolia.blockscout.com/address/0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56) |
| | 19 | [0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0](https://unichain-sepolia.blockscout.com/address/0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0) |

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

##### Base Mainnet

| Contract | TCB Evaluation Data Number | Address |
| --- | --- | --- |
| `AutomataTcbEvalDao` | N/A | [0xcF614258C68730D8cB9713AcAe425875D1FDb370](https://basescan.org/address/0xcF614258C68730D8cB9713AcAe425875D1FDb370) |
| `AutomataFmspcTcbDaoVersioned` | 17 | [0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306](https://basescan.org/address/0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306) |
| | 18 | [0x62E8Cd513B12F248804123f7ed12A0601B79FBAc](https://basescan.org/address/0x62E8Cd513B12F248804123f7ed12A0601B79FBAc) |
| | 19 | [0x43cdd3490785059423A17a90C1d8f46382C518D2](https://basescan.org/address/0x43cdd3490785059423A17a90C1d8f46382C518D2) |
| `AutomataEnclaveIdentityDaoVersioned` | 17 | [0x29aaB215aeE14D4D843C57521BbF2D3B17b45810](https://basescan.org/address/0x29aaB215aeE14D4D843C57521BbF2D3B17b45810) |
| | 18 | [0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56](https://basescan.org/address/0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56) |
| | 19 | [0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0](https://basescan.org/address/0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0) |

##### OP Mainnet

| Contract | TCB Evaluation Data Number | Address |
| --- | --- | --- |
| `AutomataTcbEvalDao` | N/A | [0xcF614258C68730D8cB9713AcAe425875D1FDb370](https://optimistic.etherscan.io/address/0xcF614258C68730D8cB9713AcAe425875D1FDb370) |
| `AutomataFmspcTcbDaoVersioned` | 17 | [0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306](https://optimistic.etherscan.io/address/0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306) |
| | 18 | [0x62E8Cd513B12F248804123f7ed12A0601B79FBAc](https://optimistic.etherscan.io/address/0x62E8Cd513B12F248804123f7ed12A0601B79FBAc) |
| | 19 | [0x43cdd3490785059423A17a90C1d8f46382C518D2](https://optimistic.etherscan.io/address/0x43cdd3490785059423A17a90C1d8f46382C518D2) |
| `AutomataEnclaveIdentityDaoVersioned` | 17 | [0x29aaB215aeE14D4D843C57521BbF2D3B17b45810](https://optimistic.etherscan.io/address/0x29aaB215aeE14D4D843C57521BbF2D3B17b45810) |
| | 18 | [0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56](https://optimistic.etherscan.io/address/0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56) |
| | 19 | [0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0](https://optimistic.etherscan.io/address/0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0) |

##### World Mainnet

| Contract | TCB Evaluation Data Number | Address |
| --- | --- | --- |
| `AutomataTcbEvalDao` | N/A | [0xcF614258C68730D8cB9713AcAe425875D1FDb370](https://worldscan.org/address/0xcF614258C68730D8cB9713AcAe425875D1FDb370) |
| `AutomataFmspcTcbDaoVersioned` | 17 | [0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306](https://worldscan.org/address/0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306) |
| | 18 | [0x62E8Cd513B12F248804123f7ed12A0601B79FBAc](https://worldscan.org/address/0x62E8Cd513B12F248804123f7ed12A0601B79FBAc) |
| | 19 | [0x43cdd3490785059423A17a90C1d8f46382C518D2](https://worldscan.org/address/0x43cdd3490785059423A17a90C1d8f46382C518D2) |
| `AutomataEnclaveIdentityDaoVersioned` | 17 | [0x29aaB215aeE14D4D843C57521BbF2D3B17b45810](https://worldscan.org/address/0x29aaB215aeE14D4D843C57521BbF2D3B17b45810) |
| | 18 | [0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56](https://worldscan.org/address/0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56) |
| | 19 | [0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0](https://worldscan.org/address/0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0) |

##### Arbitrum Mainnet

| Contract | TCB Evaluation Data Number | Address |
| --- | --- | --- |
| `AutomataTcbEvalDao` | N/A | [0xcF614258C68730D8cB9713AcAe425875D1FDb370](https://arbiscan.io/address/0xcF614258C68730D8cB9713AcAe425875D1FDb370) |
| `AutomataFmspcTcbDaoVersioned` | 17 | [0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306](https://arbiscan.io/address/0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306) |
| | 18 | [0x62E8Cd513B12F248804123f7ed12A0601B79FBAc](https://arbiscan.io/address/0x62E8Cd513B12F248804123f7ed12A0601B79FBAc) |
| | 19 | [0x43cdd3490785059423A17a90C1d8f46382C518D2](https://arbiscan.io/address/0x43cdd3490785059423A17a90C1d8f46382C518D2) |
| `AutomataEnclaveIdentityDaoVersioned` | 17 | [0x29aaB215aeE14D4D843C57521BbF2D3B17b45810](https://arbiscan.io/address/0x29aaB215aeE14D4D843C57521BbF2D3B17b45810) |
| | 18 | [0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56](https://arbiscan.io/address/0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56) |
| | 19 | [0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0](https://arbiscan.io/address/0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0) |

##### Polygon Mainnet

| Contract | TCB Evaluation Data Number | Address |
| --- | --- | --- |
| `AutomataTcbEvalDao` | N/A | [0xcF614258C68730D8cB9713AcAe425875D1FDb370](https://polygonscan.com/address/0xcF614258C68730D8cB9713AcAe425875D1FDb370) |
| `AutomataFmspcTcbDaoVersioned` | 17 | [0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306](https://polygonscan.com/address/0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306) |
| | 18 | [0x62E8Cd513B12F248804123f7ed12A0601B79FBAc](https://polygonscan.com/address/0x62E8Cd513B12F248804123f7ed12A0601B79FBAc) |
| | 19 | [0x43cdd3490785059423A17a90C1d8f46382C518D2](https://polygonscan.com/address/0x43cdd3490785059423A17a90C1d8f46382C518D2) |
| `AutomataEnclaveIdentityDaoVersioned` | 17 | [0x29aaB215aeE14D4D843C57521BbF2D3B17b45810](https://polygonscan.com/address/0x29aaB215aeE14D4D843C57521BbF2D3B17b45810) |
| | 18 | [0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56](https://polygonscan.com/address/0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56) |
| | 19 | [0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0](https://polygonscan.com/address/0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0) |

##### BNB Mainnet

| Contract | TCB Evaluation Data Number | Address |
| --- | --- | --- |
| `AutomataTcbEvalDao` | N/A | [0xcF614258C68730D8cB9713AcAe425875D1FDb370](https://bscscan.com/address/0xcF614258C68730D8cB9713AcAe425875D1FDb370) |
| `AutomataFmspcTcbDaoVersioned` | 17 | [0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306](https://bscscan.com/address/0x3d47b3E543dC4f7557E553e343F32DE0Eb15C306) |
| | 18 | [0x62E8Cd513B12F248804123f7ed12A0601B79FBAc](https://bscscan.com/address/0x62E8Cd513B12F248804123f7ed12A0601B79FBAc) |
| | 19 | [0x43cdd3490785059423A17a90C1d8f46382C518D2](https://bscscan.com/address/0x43cdd3490785059423A17a90C1d8f46382C518D2) |
| `AutomataEnclaveIdentityDaoVersioned` | 17 | [0x29aaB215aeE14D4D843C57521BbF2D3B17b45810](https://bscscan.com/address/0x29aaB215aeE14D4D843C57521BbF2D3B17b45810) |
| | 18 | [0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56](https://bscscan.com/address/0x6eE9602b90E8C451FfBCc8d5Dc9C8A3BF0A4fA56) |
| | 19 | [0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0](https://bscscan.com/address/0x5A4636EA4Bd9DDD5bA78E9405e2FA420317329D0) |

##### Avalanche C Mainnet

| Contract | TCB Evaluation Data Number | Address |
| --- | --- | --- |
| `AutomataTcbEvalDao` | N/A | [0x8e1EA521a6A4832A0c3763D75ED4b8017cfB5424](https://snowtrace.io/address/0x8e1EA521a6A4832A0c3763D75ED4b8017cfB5424) |
| `AutomataFmspcTcbDaoVersioned` | 17 | [0x3A1fDF33420026d145C59bC6b3129bA81E9bF68e](https://snowtrace.io/address/0x3A1fDF33420026d145C59bC6b3129bA81E9bF68e) |
| | 18 | [0xBF3268Dcee73EfDe149d206ebB856380C6EeD374](https://snowtrace.io/address/0xBF3268Dcee73EfDe149d206ebB856380C6EeD374) |
| | 19 | [0xb1D89Fd867A1D6a122ed88c092163281c2474111](https://snowtrace.io/address/0xb1D89Fd867A1D6a122ed88c092163281c2474111) |
| `AutomataEnclaveIdentityDaoVersioned` | 17 | [0xE6fE85B78cb82e3b9C8AE57d754C86fe6774aF64](https://snowtrace.io/address/0xE6fE85B78cb82e3b9C8AE57d754C86fe6774aF64) |
| | 18 | [0x5dF358463632A8eEA0bdeF87f011F032e984b7ef](https://snowtrace.io/address/0x5dF358463632A8eEA0bdeF87f011F032e984b7ef) |
| | 19 | [0xa0DE0E975599347A76FF9A3baC59d686fE89b73C](https://snowtrace.io/address/0xa0DE0E975599347A76FF9A3baC59d686fE89b73C) |

##### Unichain Mainnet

| Contract | TCB Evaluation Data Number | Address |
| --- | --- | --- |
| `AutomataTcbEvalDao` | N/A | [0x989255E6Bf4d2AE19e503eeF0E7DeD04d38D5a62](https://unichain.blockscout.com/address/0x989255E6Bf4d2AE19e503eeF0E7DeD04d38D5a62) |
| `AutomataFmspcTcbDaoVersioned` | 17 | [0x171eC97D750490b8916456Da908215bD618472BF](https://unichain.blockscout.com/address/0x171eC97D750490b8916456Da908215bD618472BF) |
| | 18 | [0xcB1f19e9F477E1Fe98c349F57023C317033976D9](https://unichain.blockscout.com/address/0xcB1f19e9F477E1Fe98c349F57023C317033976D9) |
| | 19 | [0x0353eFD9c0e0b208442c62Bd7Dd704d456C4FF3d](https://unichain.blockscout.com/address/0x0353eFD9c0e0b208442c62Bd7Dd704d456C4FF3d) |
| `AutomataEnclaveIdentityDaoVersioned` | 17 | [0xE6B1ba6861Fb3F4f4cc5CAE3C3Fb93C8b4Dc9617](https://unichain.blockscout.com/address/0xE6B1ba6861Fb3F4f4cc5CAE3C3Fb93C8b4Dc9617) |
| | 18 | [0x0f3c5B8b9da297EFFea8745bedAA37f9671166bD](https://unichain.blockscout.com/address/0x0f3c5B8b9da297EFFea8745bedAA37f9671166bD) |
| | 19 | [0xeA9A65A523D6e173b825841A8278d2448dEecFb1](https://unichain.blockscout.com/address/0xeA9A65A523D6e173b825841A8278d2448dEecFb1) |