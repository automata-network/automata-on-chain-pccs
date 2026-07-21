# CRL V2 PCCS deployment helpers

`deploy.sh` deploys and validates the three CRL V2 contracts against an
existing PCCS deployment. `index-stored-crls.sh` migrates the ROOT, PROCESSOR,
and PLATFORM CRLs already stored by V1. Each stored CRL is authenticated and
indexed atomically in one transaction before the Router switches to V2.

Once V2 is active, normal CRL upserts complete the exact serial index in the
same transaction. The helper keys membership by the hash of the canonical
`revokedCertificates` sequence, so metadata/signature-only reissues reuse an
identical set without rewriting every serial.

Both scripts require:

```bash
export RPC_URL=https://rpc.example.invalid
export CHAIN_ID=1315
export KEYSTORE_PATH=/secure/path/to/dcap_prod
```

`KEYSTORE_PASSWORD_FILE` is optional; without it, each standalone script asks
for the keystore password. Raw private keys are not accepted.

```bash
./script/crl-v2/deploy.sh
./script/crl-v2/index-stored-crls.sh
```

For the full cross-repository rollout, use the numbered scripts under
`automata-dcap-attestation/scripts/deploy-crl-v2`.
