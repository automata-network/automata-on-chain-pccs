#!/usr/bin/env bash
set -euo pipefail

# Network policy: anvil's --fork-url and the QPL tool's Intel PCS fetch reach external services
# (Alchemy, api.trustedservices.intel.com), so we keep https_proxy/http_proxy/all_proxy if the
# caller exported them via `allproxy`. NO_PROXY ensures cast calls against the local fork
# (127.0.0.1:8545) bypass the proxy. If the proxy env is unset and the network is reachable
# directly, the script still works — only the bypass list matters.
export NO_PROXY="${NO_PROXY:-127.0.0.1,localhost}"
export no_proxy="${no_proxy:-127.0.0.1,localhost}"
if [[ -z "${https_proxy:-}${http_proxy:-}${all_proxy:-}" ]]; then
  echo "[warn] no proxy env detected; if Alchemy/Intel PCS aren't directly reachable, run \`allproxy\` before this script" >&2
fi

STORY_RPC_URL="${STORY_RPC_URL:?missing STORY_RPC_URL}"
TCB_EVAL="${TCB_EVAL:-19}"
FMSPC="${FMSPC:-00606a000000}"      # 12 hex chars, lower-case
TCB_TYPE="${TCB_TYPE:-0}"           # 0=SGX, 1=TDX (matches PCCSRouter index)
OWNER_ADDR="${OWNER_ADDR:-0xDf841B239bE7a6b37366005107069b7410da4Ff9}"
ATTESTER_ADDR="${ATTESTER_ADDR:-0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266}"
ATTESTER_PRIVATE_KEY="${ATTESTER_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
LOCAL_RPC_URL="${LOCAL_RPC_URL:-http://127.0.0.1:8545}"
ANVIL_PORT="${ANVIL_PORT:-8545}"
CHAIN_ID="${CHAIN_ID:-1315}"
QPL_GAS_PRICE="${QPL_GAS_PRICE:-50000000000}"
QPL_FALLBACK_GAS_LIMIT="${QPL_FALLBACK_GAS_LIMIT:-30000000}"
REFRESH_PLATFORM_CRL_WITH_TEST_FIXTURE="${REFRESH_PLATFORM_CRL_WITH_TEST_FIXTURE:-false}"
VERIFY_SEND="${VERIFY_SEND:-false}"
QUOTE_FILE="${QUOTE_FILE:-}"
QUOTE_TX_HASH="${QUOTE_TX_HASH:-0xa7b1120210ccb7dc8ef0ce05f9b3db9fe90e611418b5ff7174efba89b2eb22a0}"
# FMSPC_VERSION selects which generation of FmspcTcbDao to deploy + drive: v2 (default) or v3.
FMSPC_VERSION="${FMSPC_VERSION:-v2}"
if [[ "$FMSPC_VERSION" != "v2" && "$FMSPC_VERSION" != "v3" ]]; then
  echo "invalid FMSPC_VERSION: $FMSPC_VERSION (expected v2 or v3)" >&2
  exit 1
fi

case "$FMSPC_VERSION" in
  v2)
    DAO_JSON_KEY="AutomataFmspcTcbDaoVersionedV2_tcbeval_${TCB_EVAL}"
    QPL_FUNC="upsert_tcb_fmspc_async"
    ;;
  v3)
    DAO_JSON_KEY="AutomataFmspcTcbDaoVersionedV3_tcbeval_${TCB_EVAL}"
    QPL_FUNC="upsert_tcb_fmspc_async_v3"
    ;;
esac
extract_quote_from_tx() {
  local tx_hash="$1"
  local tx_input
  tx_input=$(cast tx "$tx_hash" --rpc-url "$STORY_RPC_URL" | awk '/^input /{$1=""; sub(/^ +/,""); print}')
  perl -e '
    use strict;
    use warnings;
    my $hex = lc($ARGV[0]);
    $hex =~ s/^0x//;
    while ($hex =~ /(?:0{56})([0-9a-f]{8})(0300(?:02|03|04|05)[0-9a-f]+)/g) {
      my $len = hex($1);
      my $need = $len * 2;
      next if $len < 512 || $len > 20000;
      next if length($2) < $need;
      my $candidate = substr($2, 0, $need);
      print "0x$candidate";
      exit 0;
    }
    exit 1;
  ' "$tx_input"
}
if [[ -n "$QUOTE_FILE" ]]; then
  QUOTE_HEX="$(tr -d '\n\r' < "$QUOTE_FILE")"
elif [[ -n "${QUOTE_HEX:-}" ]]; then
  QUOTE_HEX="$QUOTE_HEX"
else
  QUOTE_HEX="$(extract_quote_from_tx "$QUOTE_TX_HASH")"
fi

# Resolve repo paths relative to this script (pccs-async-upsert-project/automata-on-chain-pccs/script/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCCS_REPO="${PCCS_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PROJECT_DIR="$(cd "$PCCS_REPO/.." && pwd)"
DCAP_REPO="${DCAP_REPO:-$PROJECT_DIR/automata-dcap-attestation}"
QPL_REPO="${QPL_REPO:-$PROJECT_DIR/automata-dcap-qpl/automata-dcap-qpl-tool}"
ANVIL_LOG="/tmp/story-aeneid-anvil.log"

cleanup() {
  if [[ -n "${ANVIL_PID:-}" ]]; then
    kill "$ANVIL_PID" >/dev/null 2>&1 || true
    wait "$ANVIL_PID" >/dev/null 2>&1 || true
  fi
  pkill -f '^anvil ' >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "[1/8] Start Story Aeneid fork"
anvil \
  --fork-url "$STORY_RPC_URL" \
  --chain-id "$CHAIN_ID" \
  --port "$ANVIL_PORT" \
  --auto-impersonate \
  --disable-code-size-limit \
  --retries 10 \
  --timeout 120000 \
  --fork-retry-backoff 2000 \
  --no-rate-limit >"$ANVIL_LOG" 2>&1 &
ANVIL_PID=$!

for _ in $(seq 1 30); do
  if cast chain-id --rpc-url "$LOCAL_RPC_URL" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! cast chain-id --rpc-url "$LOCAL_RPC_URL" >/dev/null 2>&1; then
  echo "anvil failed to become ready; recent log:"
  tail -n 100 "$ANVIL_LOG" || true
  exit 1
fi

echo "[2/8] Confirm local fork and fund impersonated owner"
cast chain-id --rpc-url "$LOCAL_RPC_URL"
curl -sS -X POST "$LOCAL_RPC_URL" -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","method":"anvil_setBalance","params":["'"$OWNER_ADDR"'","0x3635C9ADC5DEA00000"],"id":1}' >/dev/null

echo "[3/8] Show current router target"
OLD_DAO=$(cast call 0xcb1934EA19c6650a8cC9888c0306D39f0BeBc2AB "fmspcTcbDaoVersionedAddr(uint32)(address)" "$TCB_EVAL" --rpc-url "$LOCAL_RPC_URL")
echo "Old router DAO[$TCB_EVAL]: $OLD_DAO"

echo "[4/8] Run delta update against the fork (FMSPC_VERSION=$FMSPC_VERSION)"
cd "$PCCS_REPO"
RPC_URL="$LOCAL_RPC_URL" \
CHAIN_ID="$CHAIN_ID" \
TCB_EVAL="$TCB_EVAL" \
ATTESTER="$ATTESTER_ADDR" \
UNLOCKED=true \
OWNER="$OWNER_ADDR" \
FMSPC_VERSION="$FMSPC_VERSION" \
./script/delta-update-existing-network.sh

NEW_DAO=$(jq -r ".${DAO_JSON_KEY}" "$PCCS_REPO/deployment/$CHAIN_ID.json")
NEW_STORAGE=$(jq -r ".AutomataDaoStorageV2" "$PCCS_REPO/deployment/$CHAIN_ID.json")
ROUTER_DAO=$(cast call 0xcb1934EA19c6650a8cC9888c0306D39f0BeBc2AB "fmspcTcbDaoVersionedAddr(uint32)(address)" "$TCB_EVAL" --rpc-url "$LOCAL_RPC_URL")
echo "New StorageV2: $NEW_STORAGE"
echo "New DAO ${FMSPC_VERSION}[$TCB_EVAL]: $NEW_DAO"
echo "Router DAO[$TCB_EVAL] after update: $ROUTER_DAO"
test "$ROUTER_DAO" = "$NEW_DAO"

echo "[5/8] Run async upsert from qpl tool via Intel PCS fetch (function: $QPL_FUNC)"
cd "$QPL_REPO"
export QPL_FALLBACK_GAS_LIMIT
if [[ -n "${QPL_ASYNC_PARSE_BATCH_SIZE:-}" ]]; then
  export QPL_ASYNC_PARSE_BATCH_SIZE
fi
QPL_PCK_CA=""
if [[ "$TCB_TYPE" == "1" ]]; then
  # TCB_TYPE=1 ⇒ TDX. The QPL tool uses --pck_ca to pick the Intel PCS endpoint
  # (TDX vs SGX). Without this it'd fetch the SGX TCB info for the same fmspc,
  # which has the wrong shape (no tdxModuleIdentities, wrong tcb_type in DAO).
  QPL_PCK_CA="tdx"
fi
cargo run --release -- \
  --function "$QPL_FUNC" \
  --private_key "$ATTESTER_PRIVATE_KEY" \
  --rpc_url "$LOCAL_RPC_URL" \
  --chain_id "$CHAIN_ID" \
  --gas_price "$QPL_GAS_PRICE" \
  --collateral_version v4 \
  --fmspc "$FMSPC" \
  --pck_ca "$QPL_PCK_CA" \
  --fmspc_tcb_dao_contract_addr "$NEW_DAO" \
  --tcb_evaluation_data_number "$TCB_EVAL"

echo "[6/8] Verify router serves the upserted TCBInfo content hash"
CONTENT_HASH=$(cast call 0xcb1934EA19c6650a8cC9888c0306D39f0BeBc2AB \
  "getFmspcTcbContentHash(uint8,bytes6,uint32,uint32)(bytes32)" \
  "$TCB_TYPE" "0x$FMSPC" 3 "$TCB_EVAL" \
  --rpc-url "$LOCAL_RPC_URL" \
  --from 0xccEa687519596944CE2b9f1f13BEAE5DC0c7F97C)
echo "Router-served content hash: $CONTENT_HASH"
test "$CONTENT_HASH" != "0x0000000000000000000000000000000000000000000000000000000000000000"

if [[ "$REFRESH_PLATFORM_CRL_WITH_TEST_FIXTURE" == "true" ]]; then
  echo "[6.5/8] Refresh Platform CRL on fork with test fixture"
  PCS_DAO=$(jq -r ".AutomataPcsDao" "$PCCS_REPO/deployment/$CHAIN_ID.json")
  PLATFORM_CRL_HEX=$(perl -0ne 'print $1 if /bytes constant platformCrlDer\s*=\s*hex"([0-9a-f]+)";/s' \
    "$DCAP_REPO/evm/forge-test/AutomataDcapOnChainAttestationTest.t.sol")
  test -n "$PLATFORM_CRL_HEX"
  cast send "$PCS_DAO" "grantRoles(address,uint256)" "$OWNER_ADDR" 1 \
    --rpc-url "$LOCAL_RPC_URL" \
    --unlocked \
    --from "$OWNER_ADDR" >/dev/null
  cast send "$PCS_DAO" "upsertPckCrl(uint8,bytes)" 2 "0x$PLATFORM_CRL_HEX" \
    --rpc-url "$LOCAL_RPC_URL" \
    --unlocked \
    --from "$OWNER_ADDR" >/dev/null
fi

echo "[7/8] Verify quote through attestation entrypoint"
# verifyAndAttestOnChain does cert chain + signature + TCB lookups on a fork — slow under
# anvil's lazy state fetch. cast call/cast send both hit a ~30s HTTP timeout that's too tight.
# Use a raw curl eth_call with a generous timeout instead.
VERIFY_TARGET=0xB8621Da79b42A62E576408995155D48E9f856489
VERIFY_SELECTOR=$(cast calldata "verifyAndAttestOnChain(bytes,uint32)" "$QUOTE_HEX" "$TCB_EVAL")
VERIFY_RESPONSE=$(curl -sS --max-time 600 -X POST "$LOCAL_RPC_URL" \
  -H 'content-type: application/json' \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"from\":\"$ATTESTER_ADDR\",\"to\":\"$VERIFY_TARGET\",\"data\":\"$VERIFY_SELECTOR\"},\"latest\"],\"id\":1}")
echo "verifyAndAttestOnChain raw response:"
echo "$VERIFY_RESPONSE"
# (bool success, bytes output) is the return. Decode the boolean: first 32 bytes after 0x of `result`.
VERIFY_RESULT_HEX=$(echo "$VERIFY_RESPONSE" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('result','0x'))")
if [[ "$VERIFY_RESULT_HEX" == "0x" || -z "$VERIFY_RESULT_HEX" ]]; then
  echo "verifyAndAttestOnChain reverted or empty: $VERIFY_RESPONSE" >&2
  exit 1
fi
# bool is at bytes [0..32] of the ABI-encoded (bool,bytes) tuple → first 32 bytes = 0x000...001 for true.
SUCCESS_FLAG=${VERIFY_RESULT_HEX:0:66}
if [[ "$SUCCESS_FLAG" =~ ^0x0+1$ ]]; then
  echo "verifyAndAttestOnChain returned success=true"
else
  echo "verifyAndAttestOnChain returned success=false (raw: $SUCCESS_FLAG)" >&2
  exit 1
fi

echo "[8/8] Complete"
echo "Fork delta update, async upsert, and entrypoint verification all succeeded."
