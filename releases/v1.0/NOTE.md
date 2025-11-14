# Automata Onchain PCCS
 
## Release Note
 
A production-ready release of the Automata Onchain PCCS smart contract, following a comprehensive security audit and key optimizations for efficiency and reliability.

---

## Deployment

> [!NOTE]
>
> **UPDATE (March 2025)**： The EVM contracts for both Automata On Chain PCCS and [Automata DCAP Attestation](https://github.com/automata-network/automata-dcap-attestation) have been fully audited by Trail of Bits. 
>
> Click [here](https://github.com/trailofbits/publications/blob/master/reviews/2025-02-automata-dcap-attestation-onchain-pccs-securityreview.pdf) to view the audit report.

Click [here](https://github.com/automata-network/automata-dcap-attestation/blob/v1.1.0/rust-crates/libraries/network-registry/deployment/v1.0/DEPLOYMENT.md) to get the contract deployment info.

---

## What’s Changed
 
- The contract has been fully audited by Trail of Bits.  
  [🔗 View the full audit report](https://github.com/trailofbits/publications/blob/master/reviews/2025-02-automata-dcap-attestation-onchain-pccs-securityreview.pdf)
 
- Integrated [RIP-7212](https://github.com/ethereum/RIPs/blob/master/RIPS/rip-7212.md) for cheaper secp256r1 ECDSA verification on supported networks.
 
- Improved data structure encoding:
  - `TCBLevelsObj`
  - `TDXModuleIdentity`
  - `TDXModuleTcbLevelsObj`
 
- Optimized FMSPC TCB parser by reducing unnecessary looping.
 
- Introduced an interface standard for collateral storage known as the **Resolver**. The Resolver is a centralized location for individual DAOs to write and for authorized callers to read collaterals.
 
- Implemented collateral rollback protection:
  - Older (but unexpired) collaterals can no longer replace newer entries.
 
- Each collateral now includes two linked attestations:
  - Tracks the content hash and validity window.
 
- Automatically reverts duplicate collateral upserts.
 
- Event logs are emitted for all state-changing functions.
 
---
 
[👉 Full Changelog (`v0.1.1...v1.0.0`)](https://github.com/automata-network/automata-on-chain-pccs/compare/v0.1.1...v1.0.0)
