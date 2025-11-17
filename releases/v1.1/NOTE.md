# Automata Onchain PCCS

## Release Note

---

## Deployment

Click [here](https://github.com/automata-network/automata-dcap-attestation/blob/v1.1.0/rust-crates/libraries/network-registry/deployment/current/DEPLOYMENT.md) to get the contract deployment info.

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