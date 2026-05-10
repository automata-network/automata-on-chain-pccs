#!/usr/bin/env bash
set -euo pipefail

RPC_URL="${RPC_URL:?missing RPC_URL}"
CHAIN_ID="${CHAIN_ID:?missing CHAIN_ID}"
TCB_EVAL="${TCB_EVAL:?missing TCB_EVAL}"
ATTESTER="${ATTESTER:?missing ATTESTER}"

if [[ -n "${PRIVATE_KEY:-}" ]]; then
  AUTH_ENV=(PRIVATE_KEY="$PRIVATE_KEY")
elif [[ "${UNLOCKED:-}" == "true" && -n "${OWNER:-}" ]]; then
  AUTH_ENV=(UNLOCKED=true OWNER="$OWNER")
else
  echo "missing auth: set PRIVATE_KEY, or set UNLOCKED=true and OWNER"
  exit 1
fi

PCCS_REPO="/home/rustdev/shared/code/automata-on-chain-pccs"
DCAP_REPO="/home/rustdev/shared/code/automata-dcap-attestation"
DCAP_PCCS_SUBMODULE_DEPLOYMENT="$DCAP_REPO/evm/lib/automata-on-chain-pccs/deployment"

echo "[1/8] Build on-chain-pccs"
cd "$PCCS_REPO"
forge build

echo "[2/8] Deploy PCCS helpers (including FmspcTcbHelperV2)"
env "${AUTH_ENV[@]}" make deploy-helpers RPC_URL="$RPC_URL"

echo "[3/8] Deploy PCCS base DAO set"
env "${AUTH_ENV[@]}" make deploy-dao RPC_URL="$RPC_URL"

echo "[4/8] Deploy TcbEvalDao"
env RPC_URL="$RPC_URL" "${AUTH_ENV[@]}" \
  ./script/automata/versioned/deploy_versioned.sh tcb-eval

echo "[5/8] Deploy legacy versioned DAO set"
env RPC_URL="$RPC_URL" "${AUTH_ENV[@]}" \
  ./script/automata/versioned/deploy_versioned.sh versioned "$TCB_EVAL"

echo "[6/8] Deploy StorageV2 and FmspcTcbDaoVersionedV2"
env RPC_URL="$RPC_URL" "${AUTH_ENV[@]}" \
  ./script/automata/versioned/deploy_versioned.sh storage-v2

env RPC_URL="$RPC_URL" "${AUTH_ENV[@]}" \
  ./script/automata/versioned/deploy_versioned.sh fmspc-v2 "$TCB_EVAL"

echo "[7/8] Configure roles"
env RPC_URL="$RPC_URL" "${AUTH_ENV[@]}" \
  ./script/automata/versioned/config_versioned.sh tcb-eval "$ATTESTER" 1 true

env RPC_URL="$RPC_URL" "${AUTH_ENV[@]}" \
  ./script/automata/versioned/config_versioned.sh versioned "$TCB_EVAL" "$ATTESTER" 1 true

env RPC_URL="$RPC_URL" "${AUTH_ENV[@]}" \
  ./script/automata/versioned/config_versioned.sh fmspc-v2 "$TCB_EVAL" "$ATTESTER" 1 true

echo "[8/8] Sync deployment into attestation repo and deploy router/attestation"
mkdir -p "$DCAP_PCCS_SUBMODULE_DEPLOYMENT"
cp "$PCCS_REPO/deployment/$CHAIN_ID.json" "$DCAP_PCCS_SUBMODULE_DEPLOYMENT/$CHAIN_ID.json"

cd "$DCAP_REPO/rust-crates"
./scripts/update_pccs_deployment.sh --local "$CHAIN_ID"

cd "$DCAP_REPO"
git submodule update --init --recursive

cd "$DCAP_REPO/evm"
forge build
env "${AUTH_ENV[@]}" make deploy-router RPC_URL="$RPC_URL"
env "${AUTH_ENV[@]}" make setup-router RPC_URL="$RPC_URL"

if [[ -n "${PRIVATE_KEY:-}" ]]; then
  SCRIPT_ARGS=(--private-key "$PRIVATE_KEY")
  OWNER_ADDR=$(cast wallet address --private-key "$PRIVATE_KEY")
else
  SCRIPT_ARGS=(--unlocked --sender "$OWNER")
  OWNER_ADDR="$OWNER"
fi

OWNER="$OWNER_ADDR" forge script forge-script/DeployRouter.s.sol:DeployRouter \
  --rpc-url "$RPC_URL" \
  "${SCRIPT_ARGS[@]}" \
  --broadcast --skip-simulation -vv \
  --sig "updateVersionedDaoConfig(uint32)" "$TCB_EVAL"

env "${AUTH_ENV[@]}" make deploy-attestation RPC_URL="$RPC_URL"
env "${AUTH_ENV[@]}" make deploy-all-verifiers RPC_URL="$RPC_URL"

env "${AUTH_ENV[@]}" make config-verifier RPC_URL="$RPC_URL" QUOTE_VERIFIER_VERSION=3
env "${AUTH_ENV[@]}" make config-verifier RPC_URL="$RPC_URL" QUOTE_VERIFIER_VERSION=4
env "${AUTH_ENV[@]}" make config-verifier RPC_URL="$RPC_URL" QUOTE_VERIFIER_VERSION=5

echo "Done"
