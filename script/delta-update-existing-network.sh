#!/usr/bin/env bash
set -euo pipefail

RPC_URL="${RPC_URL:?missing RPC_URL}"
CHAIN_ID="${CHAIN_ID:?missing CHAIN_ID}"
TCB_EVAL="${TCB_EVAL:?missing TCB_EVAL}"
ATTESTER="${ATTESTER:?missing ATTESTER}"
USE_CREATE2="${USE_CREATE2:-false}"
FMSPC_V2_GAS_LIMIT="${FMSPC_V2_GAS_LIMIT:-30000000}"
SKIP_DCAP_SUBMODULE_UPDATE="${SKIP_DCAP_SUBMODULE_UPDATE:-true}"

if [[ -n "${PRIVATE_KEY:-}" ]]; then
  AUTH_ENV=(PRIVATE_KEY="$PRIVATE_KEY")
  FORGE_AUTH_ARGS=(--private-key "$PRIVATE_KEY")
  OWNER_ADDR=$(cast wallet address --private-key "$PRIVATE_KEY")
elif [[ "${UNLOCKED:-}" == "true" && -n "${OWNER:-}" ]]; then
  AUTH_ENV=(UNLOCKED=true OWNER="$OWNER")
  FORGE_AUTH_ARGS=(--unlocked --sender "$OWNER")
  OWNER_ADDR="$OWNER"
else
  echo "missing auth: set PRIVATE_KEY, or set UNLOCKED=true and OWNER"
  exit 1
fi

# Resolve repo paths relative to this script (pccs-async-upsert-project/automata-on-chain-pccs/script/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCCS_REPO="${PCCS_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PROJECT_DIR="$(cd "$PCCS_REPO/.." && pwd)"
DCAP_REPO="${DCAP_REPO:-$PROJECT_DIR/automata-dcap-attestation}"
DCAP_PCCS_SUBMODULE_DEPLOYMENT="$DCAP_REPO/evm/lib/automata-on-chain-pccs/deployment"

echo "[1/7] Build on-chain-pccs"
cd "$PCCS_REPO"
forge build

DEPLOY_CMD="fmspc-v2"
CONFIG_CMD="fmspc-v2"
DAO_JSON_KEY="AutomataFmspcTcbDaoVersionedV2_tcbeval_${TCB_EVAL}"

echo "[2/7] Deploy FmspcTcbHelperV2"
OWNER="$OWNER_ADDR" USE_CREATE2=false forge script script/helper/DeployHelpers.s.sol:DeployHelpers \
  --rpc-url "$RPC_URL" \
  "${FORGE_AUTH_ARGS[@]}" \
  --broadcast --skip-simulation -vv \
  --sig "deployFmspcTcbHelperV2()"

echo "[3/7] Deploy StorageV2"
env RPC_URL="$RPC_URL" USE_CREATE2="$USE_CREATE2" "${AUTH_ENV[@]}" \
  ./script/automata/versioned/deploy_versioned.sh storage-v2

echo "[4/7] Deploy FmspcTcbDaoVersionedV2"
env RPC_URL="$RPC_URL" USE_CREATE2="$USE_CREATE2" GAS_LIMIT="$FMSPC_V2_GAS_LIMIT" SKIP_POST_DEPLOY_GRANTS=true "${AUTH_ENV[@]}" \
  ./script/automata/versioned/deploy_versioned.sh "$DEPLOY_CMD" "$TCB_EVAL"

NEW_DAO=$(jq -r ".${DAO_JSON_KEY}" "$PCCS_REPO/deployment/$CHAIN_ID.json")

echo "[4.5/7] Grant StorageV2 access to new FmspcTcbDaoVersioned"
OWNER="$OWNER_ADDR" forge script script/automata/ConfigAutomataDao.s.sol:ConfigAutomataDao \
  --rpc-url "$RPC_URL" \
  "${FORGE_AUTH_ARGS[@]}" \
  --broadcast --skip-simulation -vv \
  --sig "grantDaoV2(address)" "$NEW_DAO"

echo "[5/7] Grant attester role to new DAO"
env RPC_URL="$RPC_URL" "${AUTH_ENV[@]}" \
  ./script/automata/versioned/config_versioned.sh "$CONFIG_CMD" "$TCB_EVAL" "$ATTESTER" 1 true

echo "[6/7] Sync deployment into attestation repo"
mkdir -p "$DCAP_PCCS_SUBMODULE_DEPLOYMENT"
cp "$PCCS_REPO/deployment/$CHAIN_ID.json" "$DCAP_PCCS_SUBMODULE_DEPLOYMENT/$CHAIN_ID.json"

cd "$DCAP_REPO/rust-crates"
./scripts/update_pccs_deployment.sh --local "$CHAIN_ID"

echo "[7/7] Update router config"
cd "$DCAP_REPO"
if [[ "$SKIP_DCAP_SUBMODULE_UPDATE" != "true" ]]; then
  git submodule update --init --recursive
fi

cd "$DCAP_REPO/evm"
forge build
env "${AUTH_ENV[@]}" make setup-router RPC_URL="$RPC_URL"

OWNER="$OWNER_ADDR" forge script forge-script/DeployRouter.s.sol:DeployRouter \
    --rpc-url "$RPC_URL" \
    "${FORGE_AUTH_ARGS[@]}" \
    --broadcast --skip-simulation -vv \
    --sig "updateVersionedDaoConfig(uint32)" "$TCB_EVAL"

echo "Done"
