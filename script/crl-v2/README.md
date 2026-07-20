# CRL V2 PCCS deployment helpers

`deploy.sh` deploys and validates the three CRL V2 contracts against an
existing PCCS deployment. `index-stored-crls.sh` indexes the ROOT, PROCESSOR,
and PLATFORM CRLs in resumable batches. A legacy stored CRL is fully
authenticated once by the first batch; later batches reuse the CA-scoped DER
authentication result and validate only their bounded serial range.

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
