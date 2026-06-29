#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  script/fmspc-v2-verify.sh [--evals "19 20 21"] [--verifier blockscout] [--verifier-url URL] [--guess-constructor-args]

Verifies only the FMSPC async upsert V2 delta contracts:
  - FmspcTcbHelperV2
  - AutomataDaoStorageV2
  - AutomataFmspcTcbDaoVersionedV2_tcbeval_${eval}

Required environment:
  RPC_URL
  OWNER        Constructor owner address used for deployment

Optional environment:
  CHAIN_ID     Expected chain id. If omitted, detected from RPC.
  VERIFIER     Defaults to blockscout.
  VERIFIER_URL Defaults to https://aeneid.storyscan.io/api/ for chain 1315.
  GUESS_CONSTRUCTOR_ARGS
               Set true to ask Foundry to recover constructor args from creation input.

Example:
  OWNER=0x... RPC_URL=$RPC_URL script/fmspc-v2-verify.sh --evals "19 20 21"
EOF
}

TCB_EVALS="${TCB_EVALS:-19 20 21}"
VERIFIER="${VERIFIER:-blockscout}"
VERIFIER_URL="${VERIFIER_URL:-}"
GUESS_CONSTRUCTOR_ARGS="${GUESS_CONSTRUCTOR_ARGS:-false}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --evals)
      TCB_EVALS="${2:?missing value for --evals}"
      shift 2
      ;;
    --verifier)
      VERIFIER="${2:?missing value for --verifier}"
      shift 2
      ;;
    --verifier-url)
      VERIFIER_URL="${2:?missing value for --verifier-url}"
      shift 2
      ;;
    --guess-constructor-args)
      GUESS_CONSTRUCTOR_ARGS=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

RPC_URL="${RPC_URL:?missing RPC_URL}"
OWNER="${OWNER:?missing OWNER}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCCS_REPO="${PCCS_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"

CHAIN_ID_DETECTED="$(cast chain-id --rpc-url "$RPC_URL")"
if [[ -n "${CHAIN_ID:-}" && "$CHAIN_ID" != "$CHAIN_ID_DETECTED" ]]; then
  echo "CHAIN_ID mismatch: env=$CHAIN_ID rpc=$CHAIN_ID_DETECTED" >&2
  exit 1
fi
CHAIN_ID="$CHAIN_ID_DETECTED"

if [[ "$CHAIN_ID" == "1315" && -z "$VERIFIER_URL" && "$VERIFIER" == "blockscout" ]]; then
  VERIFIER_URL="https://aeneid.storyscan.io/api/"
fi

DEPLOYMENT_FILE="$PCCS_REPO/deployment/$CHAIN_ID.json"
if [[ ! -f "$DEPLOYMENT_FILE" ]]; then
  echo "missing deployment file: $DEPLOYMENT_FILE" >&2
  exit 1
fi

VERIFY_ARGS=(--rpc-url "$RPC_URL" --verifier "$VERIFIER" --watch)
if [[ -n "$VERIFIER_URL" ]]; then
  VERIFY_ARGS+=(--verifier-url "$VERIFIER_URL")
fi

# Foundry still interpolates ${ETHERSCAN_API_KEY} from foundry.toml while loading
# config, even when the active verifier is Blockscout. Storyscan does not require
# an Etherscan key, so provide a harmless placeholder unless the caller set one.
export ETHERSCAN_API_KEY="${ETHERSCAN_API_KEY:-dummy}"

if [[ -n "${VERIFIER_API_KEY:-${BLOCKSCOUT_API_KEY:-}}" ]]; then
  VERIFY_ARGS+=(--verifier-api-key "${VERIFIER_API_KEY:-$BLOCKSCOUT_API_KEY}")
fi

json_addr() {
  local key="$1"
  jq -er --arg key "$key" '.[$key]' "$DEPLOYMENT_FILE"
}

has_code() {
  local addr="$1"
  local code
  code="$(cast code "$addr" --rpc-url "$RPC_URL")"
  [[ -n "$code" && "$code" != "0x" ]]
}

verify_contract() {
  local addr="$1"
  local contract="$2"
  local args="${3:-}"

  if ! has_code "$addr"; then
    echo "missing deployed code at $addr for $contract" >&2
    exit 1
  fi

  echo "[verify] $contract at $addr"
  if [[ "$GUESS_CONSTRUCTOR_ARGS" == "true" ]]; then
    forge verify-contract "${VERIFY_ARGS[@]}" "$addr" "$contract" --guess-constructor-args
  elif [[ -n "$args" ]]; then
    forge verify-contract "${VERIFY_ARGS[@]}" "$addr" "$contract" --constructor-args "$args"
  else
    forge verify-contract "${VERIFY_ARGS[@]}" "$addr" "$contract"
  fi
}

cd "$PCCS_REPO"
forge build

echo "Chain ID: $CHAIN_ID"
echo "Verifier: $VERIFIER"
if [[ -n "$VERIFIER_URL" ]]; then
  echo "Verifier URL: $VERIFIER_URL"
fi

P256_ADDR="$(forge script script/utils/P256Configuration.sol:P256Configuration --rpc-url "$RPC_URL" --sig "simulateVerify()" -vv | awk '/P256Verifier address:/ { print $NF; exit }')"
if [[ -z "$P256_ADDR" ]]; then
  echo "failed to resolve P256 verifier address" >&2
  exit 1
fi

STORAGE_ADDR="$(json_addr AutomataDaoStorage)"
STORAGE_V2_ADDR="$(json_addr AutomataDaoStorageV2)"
PCS_DAO_ADDR="$(json_addr AutomataPcsDao)"
FMSPC_HELPER_ADDR="$(json_addr FmspcTcbHelper)"
FMSPC_HELPER_V2_ADDR="$(json_addr FmspcTcbHelperV2)"
X509_HELPER_ADDR="$(json_addr PCKHelper)"
CRL_HELPER_ADDR="$(json_addr X509CRLHelper)"

verify_contract \
  "$FMSPC_HELPER_V2_ADDR" \
  "src/helpers/FmspcTcbHelperV2.sol:FmspcTcbHelperV2"

storage_v2_args="$(cast abi-encode "constructor(address,address)" "$OWNER" "$STORAGE_ADDR")"
verify_contract \
  "$STORAGE_V2_ADDR" \
  "src/automata_pccs/shared/AutomataDaoStorageV2.sol:AutomataDaoStorageV2" \
  "$storage_v2_args"

for eval in $TCB_EVALS; do
  dao_addr="$(json_addr "AutomataFmspcTcbDaoVersionedV2_tcbeval_${eval}")"
  dao_args="$(cast abi-encode "constructor(address,address,address,address,address,address,address,address,uint32)" \
    "$STORAGE_V2_ADDR" \
    "$P256_ADDR" \
    "$PCS_DAO_ADDR" \
    "$FMSPC_HELPER_ADDR" \
    "$FMSPC_HELPER_V2_ADDR" \
    "$X509_HELPER_ADDR" \
    "$CRL_HELPER_ADDR" \
    "$OWNER" \
    "$eval")"
  verify_contract \
    "$dao_addr" \
    "src/automata_pccs/versioned/AutomataFmspcTcbDaoVersionedV2.sol:AutomataFmspcTcbDaoVersionedV2" \
    "$dao_args"
done

echo "Done"
