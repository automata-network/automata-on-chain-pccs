# FMSPC Async Upsert V2 Deployment Guide

This guide covers the delta deployment needed to promote async FMSPC TCB
upsert V2 on an existing network. It is written for Story Aeneid Testnet
(`chainId = 1315`), but the same sequence applies to any network where the
legacy PCCS contracts are already deployed.

## Current Story Aeneid State

Observed on 2026-05-26 against the live Story Aeneid Testnet router
`0xcb1934EA19c6650a8cC9888c0306D39f0BeBc2AB`.

The live router still points eval 19/20/21 FMSPC reads to the legacy
`AutomataFmspcTcbDaoVersioned` contracts:

| Eval | Current router FMSPC DAO | Current router QE ID DAO |
| ---: | --- | --- |
| 19 | `0x0353eFD9c0e0b208442c62Bd7Dd704d456C4FF3d` | `0xeA9A65A523D6e173b825841A8278d2448dEecFb1` |
| 20 | `0x8b77798BABc976f0b4739B0e859e6f2F1dE269C9` | `0xfC4140d90b3Ee14D3Fe557Be3B1f552F383C7dEE` |
| 21 | `0x0b6Fb1b2E963d105F92Ca8115a17E67F0ab69794` | `0x41C4FD8e73e20ef177A2367170D5e807D39c2526` |

The V2 addresses currently present in the local `deployment/1315.json` were
produced by forked E2E runs and have no code on the live Story Aeneid chain:

| Deployment key | Local/fork address | Live code |
| --- | --- | --- |
| `FmspcTcbHelperV2` | `0x9d5e95109E13C6Fc88804eca6B76AF6372e939a8` | empty |
| `AutomataDaoStorageV2` | `0x8E85537d56E5Eb80578E52c97E2174c1206aB036` | empty |
| `AutomataFmspcTcbDaoVersionedV2_tcbeval_19` | `0xC3D2e1b9065b678a00Fe55524750B33911BFc315` | empty |
| `AutomataFmspcTcbDaoVersionedV2_tcbeval_20` | `0xd5f8a65aaDAaA7EA4eC3907ADfaf01561B4238ab` | empty |
| `AutomataFmspcTcbDaoVersionedV2_tcbeval_21` | `0x07935C3085Fe2427038537E46BaCAE64796CC3A0` | empty |

Treat those V2 addresses as fork artifacts until the live deployment is
broadcast and confirmed.

## Contracts To Update

Deploy once:

| Key | Contract |
| --- | --- |
| `FmspcTcbHelperV2` | `src/helpers/FmspcTcbHelperV2.sol:FmspcTcbHelperV2` |
| `AutomataDaoStorageV2` | `src/automata_pccs/shared/AutomataDaoStorageV2.sol:AutomataDaoStorageV2` |

Deploy once per enabled TCB evaluation data number:

| Key pattern | Contract |
| --- | --- |
| `AutomataFmspcTcbDaoVersionedV2_tcbeval_${eval}` | `src/automata_pccs/versioned/AutomataFmspcTcbDaoVersionedV2.sol:AutomataFmspcTcbDaoVersionedV2` |

For Story Aeneid, the current V2 enablement target is eval `19`, `20`, and
`21`.

## Contracts Not To Update

Do not redeploy or overwrite these only because of async FMSPC V2:

| Key | Reason |
| --- | --- |
| `AutomataFmspcTcbDaoVersioned_tcbeval_${eval}` | Legacy FMSPC DAO remains available as rollback/fallback. |
| `AutomataEnclaveIdentityDaoVersioned_tcbeval_${eval}` | QE/TDQE identity flow is unchanged. Router QE mapping should stay pointed here. |
| `AutomataDaoStorage` | V2 storage wraps/falls back to the existing storage. |
| `FmspcTcbHelper` | Still used by legacy contracts and as a constructor dependency. |
| `PCCSRouter` | The existing router already has versioned DAO mappings; update its config instead of deploying a new router. |
| `AutomataPcsDao`, `AutomataPckDao`, `AutomataTcbEvalDao`, PCK/X509/CRL helpers | No async FMSPC V2 bytecode change. |

The easy naming trap is `AutomataFmspcTcbDaoVersioned` vs
`AutomataFmspcTcbDaoVersionedV2`: only deploy and route the V2 key for eval
19/20/21. Keep the legacy key present in deployment JSON.

## Preconditions

Use the latest feature branches for both repositories:

- `automata-on-chain-pccs`
- `automata-dcap-attestation`, with its `evm/lib/automata-on-chain-pccs`
  submodule updated to the on-chain PCCS commit that contains V2.

Set the common environment:

```bash
export CHAIN_ID=1315
export RPC_URL="https://story-aeneid.g.alchemy.com/v2/<key>"
export PRIVATE_KEY="<owner-private-key>"
export OWNER="$(cast wallet address --private-key "$PRIVATE_KEY")"
export ATTESTER="<async-upsert-worker-or-backend-address>"
export PCCS_ROUTER="0xcb1934EA19c6650a8cC9888c0306D39f0BeBc2AB"
export TCB_EVALS="19 20 21"
export USE_CREATE2=true
```

For an unlocked local fork, replace `PRIVATE_KEY` with:

```bash
export UNLOCKED=true
export OWNER="<unlocked-owner-address>"
```

## on-chain-pccs Deployment

Run from `automata-on-chain-pccs`.

Build first:

```bash
forge build
```

Deploy `FmspcTcbHelperV2` once:

```bash
OWNER="$OWNER" USE_CREATE2="$USE_CREATE2" forge script script/helper/DeployHelpers.s.sol:DeployHelpers \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast --skip-simulation -vv \
  --sig "deployFmspcTcbHelperV2()"
```

Deploy `AutomataDaoStorageV2` once:

```bash
env RPC_URL="$RPC_URL" PRIVATE_KEY="$PRIVATE_KEY" USE_CREATE2="$USE_CREATE2" \
  ./script/automata/versioned/deploy_versioned.sh storage-v2
```

Deploy one `AutomataFmspcTcbDaoVersionedV2` per eval:

```bash
for eval in $TCB_EVALS; do
  env RPC_URL="$RPC_URL" PRIVATE_KEY="$PRIVATE_KEY" USE_CREATE2="$USE_CREATE2" \
    GAS_LIMIT=30000000 SKIP_POST_DEPLOY_GRANTS=true \
    ./script/automata/versioned/deploy_versioned.sh fmspc-v2 "$eval"

  dao="$(jq -r ".AutomataFmspcTcbDaoVersionedV2_tcbeval_${eval}" "deployment/${CHAIN_ID}.json")"

  OWNER="$OWNER" forge script script/automata/ConfigAutomataDao.s.sol:ConfigAutomataDao \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast --skip-simulation -vv \
    --sig "grantDaoV2(address)" "$dao"

  env RPC_URL="$RPC_URL" PRIVATE_KEY="$PRIVATE_KEY" \
    ./script/automata/versioned/config_versioned.sh fmspc-v2 "$eval" "$ATTESTER" 1 true
done
```

`SKIP_POST_DEPLOY_GRANTS=true` is intentional here: the deploy step and grant
step are separated so the deployment receipt list stays easy to audit.

## dcap-attestation Router And Registry Update

After the live V2 addresses are written to `automata-on-chain-pccs/deployment/1315.json`,
sync them into the attestation repo and network registry:

```bash
cp deployment/${CHAIN_ID}.json ../automata-dcap-attestation/evm/lib/automata-on-chain-pccs/deployment/${CHAIN_ID}.json

cd ../automata-dcap-attestation/rust-crates
./scripts/update_pccs_deployment.sh --local "$CHAIN_ID"
```

Then update router access and versioned DAO routing:

```bash
cd ../evm
forge build

env PRIVATE_KEY="$PRIVATE_KEY" make setup-router RPC_URL="$RPC_URL"

for eval in $TCB_EVALS; do
  OWNER="$OWNER" forge script forge-script/DeployRouter.s.sol:DeployRouter \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast --skip-simulation -vv \
    --sig "updateVersionedDaoConfig(uint32)" "$eval"
done
```

`make setup-router` grants the existing `PCCSRouter` read access to both
`AutomataDaoStorage` and `AutomataDaoStorageV2`. `updateVersionedDaoConfig`
keeps the QE identity mapping pointed at `AutomataEnclaveIdentityDaoVersioned`
and switches only the FMSPC mapping to `AutomataFmspcTcbDaoVersionedV2` when
that key exists in the synced PCCS deployment file.

## Verification Checklist

Check that V2 bytecode exists on the live chain:

```bash
cast code "$(jq -r '.FmspcTcbHelperV2' deployment/${CHAIN_ID}.json)" --rpc-url "$RPC_URL"
cast code "$(jq -r '.AutomataDaoStorageV2' deployment/${CHAIN_ID}.json)" --rpc-url "$RPC_URL"
```

For each eval:

```bash
dao="$(jq -r ".AutomataFmspcTcbDaoVersionedV2_tcbeval_${eval}" "deployment/${CHAIN_ID}.json")"
qe="$(jq -r ".AutomataEnclaveIdentityDaoVersioned_tcbeval_${eval}" "deployment/${CHAIN_ID}.json")"

cast call "$dao" "asyncUpsertProtocolVersion()(uint8)" --rpc-url "$RPC_URL"
cast call "$dao" "TCB_EVALUATION_NUMBER()(uint32)" --rpc-url "$RPC_URL"
cast call "$dao" "hasAnyRole(address,uint256)(bool)" "$ATTESTER" 1 --rpc-url "$RPC_URL"

cast call "$PCCS_ROUTER" "fmspcTcbDaoVersionedAddr(uint32)(address)" "$eval" --rpc-url "$RPC_URL"
cast call "$PCCS_ROUTER" "qeIdDaoVersionedAddr(uint32)(address)" "$eval" --rpc-url "$RPC_URL"
```

Expected results:

- `asyncUpsertProtocolVersion()` returns `2`.
- `TCB_EVALUATION_NUMBER()` returns the eval being checked.
- `hasAnyRole($ATTESTER, 1)` returns `true`.
- Router `fmspcTcbDaoVersionedAddr(eval)` equals the new V2 DAO.
- Router `qeIdDaoVersionedAddr(eval)` equals the existing QE DAO and does not
  change during this rollout.

Finally run at least one SGX and one TDX async upsert against a forked Story
Aeneid node, then verify quote attestation through the router.

## Rollback

Rollback does not require deleting the V2 contracts. Re-sync a deployment file
without the `AutomataFmspcTcbDaoVersionedV2_tcbeval_${eval}` key, or explicitly
point the router FMSPC mapping back to the legacy
`AutomataFmspcTcbDaoVersioned_tcbeval_${eval}` address. Keep
`AutomataDaoStorageV2` deployed; it is harmless when no router mapping points
to a V2 DAO.

## Existing Helper Script

`script/delta-update-existing-network.sh` is useful for forked E2E and a single
eval delta rollout. It deploys helper V2, storage V2, one V2 DAO, grants roles,
syncs the attestation deployment, and updates the router in one path.

For production multi-eval deployment, prefer the explicit sequence above so
`FmspcTcbHelperV2` and `AutomataDaoStorageV2` are deployed once, then reused by
all eval-specific V2 DAOs.
