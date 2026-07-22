# CRL V2 PCCS deployment helpers

`deploy.sh` deploys and validates the three CRL V2 contracts against an
existing PCCS deployment. `index-stored-crls.sh` migrates the ROOT, PROCESSOR,
and PLATFORM CRLs already stored by V1. Each stored CRL is authenticated and
indexed atomically in one transaction before the Router switches to V2.

After the Router switches to V2, `revoke-legacy-pcs-writer.sh` removes the
legacy `AutomataPcsDao` storage authorization. This prevents V1 from replacing
an indexed CRL with unindexed DER. The cross-repository rollout immediately
reconciles all three current CRLs after revocation, closing any race between
the Router switch and the revocation transaction. A rollback must re-grant the
legacy DAO before switching the Router back.

Once V2 is active, normal CRL upserts complete the exact serial index in the
same transaction. The helper keys membership by a domain-separated hash of the
strictly parsed serial sequence, so reissues with the same ordered serial set
reuse an identical index even if validity, revocation dates, entry metadata, or
the signature changes.

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
./script/crl-v2/revoke-legacy-pcs-writer.sh
```

For the full cross-repository rollout, use the numbered scripts under
`automata-dcap-attestation/scripts/deploy-crl-v2`.
