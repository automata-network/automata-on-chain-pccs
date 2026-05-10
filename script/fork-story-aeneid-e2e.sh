#!/usr/bin/env bash
set -euo pipefail

unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy

STORY_RPC_URL="${STORY_RPC_URL:?missing STORY_RPC_URL}"
TCB_EVAL="${TCB_EVAL:-19}"
OWNER_ADDR="${OWNER_ADDR:-0xDf841B239bE7a6b37366005107069b7410da4Ff9}"
ATTESTER_ADDR="${ATTESTER_ADDR:-0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266}"
ATTESTER_PRIVATE_KEY="${ATTESTER_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
LOCAL_RPC_URL="${LOCAL_RPC_URL:-http://127.0.0.1:8545}"
ANVIL_PORT="${ANVIL_PORT:-8545}"
CHAIN_ID="${CHAIN_ID:-1315}"
QPL_GAS_PRICE="${QPL_GAS_PRICE:-50000000000}"
QPL_FALLBACK_GAS_LIMIT="${QPL_FALLBACK_GAS_LIMIT:-30000000}"
REFRESH_PLATFORM_CRL_WITH_TEST_FIXTURE="${REFRESH_PLATFORM_CRL_WITH_TEST_FIXTURE:-false}"
QUOTE_FILE="${QUOTE_FILE:-}"
QUOTE_TX_HASH="${QUOTE_TX_HASH:-0xa7b1120210ccb7dc8ef0ce05f9b3db9fe90e611418b5ff7174efba89b2eb22a0}"
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

PCCS_REPO="/home/rustdev/shared/code/automata-on-chain-pccs"
DCAP_REPO="/home/rustdev/shared/code/automata-dcap-attestation"
QPL_REPO="/home/rustdev/shared/code/automata-dcap-qpl/automata-dcap-qpl-tool"
ANVIL_LOG="/tmp/story-aeneid-anvil.log"

cleanup() {
  if [[ -n "${ANVIL_PID:-}" ]]; then
    kill "$ANVIL_PID" >/dev/null 2>&1 || true
    wait "$ANVIL_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "[1/8] Start Story Aeneid fork"
anvil --fork-url "$STORY_RPC_URL" --chain-id "$CHAIN_ID" --port "$ANVIL_PORT" --auto-impersonate --disable-code-size-limit >"$ANVIL_LOG" 2>&1 &
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

echo "[4/8] Run delta update against the fork"
cd "$PCCS_REPO"
RPC_URL="$LOCAL_RPC_URL" \
CHAIN_ID="$CHAIN_ID" \
TCB_EVAL="$TCB_EVAL" \
ATTESTER="$ATTESTER_ADDR" \
UNLOCKED=true \
OWNER="$OWNER_ADDR" \
./script/delta-update-existing-network.sh

NEW_DAO=$(jq -r ".AutomataFmspcTcbDaoVersionedV2_tcbeval_${TCB_EVAL}" "$PCCS_REPO/deployment/$CHAIN_ID.json")
NEW_STORAGE=$(jq -r ".AutomataDaoStorageV2" "$PCCS_REPO/deployment/$CHAIN_ID.json")
ROUTER_DAO=$(cast call 0xcb1934EA19c6650a8cC9888c0306D39f0BeBc2AB "fmspcTcbDaoVersionedAddr(uint32)(address)" "$TCB_EVAL" --rpc-url "$LOCAL_RPC_URL")
echo "New StorageV2: $NEW_STORAGE"
echo "New DAO V2[$TCB_EVAL]: $NEW_DAO"
echo "Router DAO[$TCB_EVAL] after update: $ROUTER_DAO"
test "$ROUTER_DAO" = "$NEW_DAO"

echo "[5/8] Run async upsert from qpl tool via Intel PCS fetch"
cd "$QPL_REPO"
export QPL_FALLBACK_GAS_LIMIT
if [[ -n "${QPL_ASYNC_PARSE_BATCH_SIZE:-}" ]]; then
  export QPL_ASYNC_PARSE_BATCH_SIZE
fi
cargo run -- \
  --function upsert_tcb_fmspc_async \
  --private_key "$ATTESTER_PRIVATE_KEY" \
  --rpc_url "$LOCAL_RPC_URL" \
  --chain_id "$CHAIN_ID" \
  --gas_price "$QPL_GAS_PRICE" \
  --collateral_version v4 \
  --fmspc 00606a000000 \
  --fmspc_tcb_dao_contract_addr "$NEW_DAO" \
  --tcb_evaluation_data_number "$TCB_EVAL"

echo "[6/8] Verify router now serves the new V3 TCB collateral path"
cast call 0xcb1934EA19c6650a8cC9888c0306D39f0BeBc2AB \
  "getFmspcTcbContentHash(uint8,bytes6,uint32,uint32)(bytes32)" \
  0 0x00606a000000 3 "$TCB_EVAL" \
  --rpc-url "$LOCAL_RPC_URL" \
  --from 0xccEa687519596944CE2b9f1f13BEAE5DC0c7F97C

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
VERIFY_RESULT=$(cast call 0xB8621Da79b42A62E576408995155D48E9f856489 \
  "verifyAndAttestOnChain(bytes,uint32)(bool,bytes)" \
  "$QUOTE_HEX" "$TCB_EVAL" \
  --rpc-url "$LOCAL_RPC_URL" \
  --from "$ATTESTER_ADDR")
echo "$VERIFY_RESULT"
echo "$VERIFY_RESULT" | rg "true" >/dev/null

echo "[8/8] Complete"
echo "Fork delta update, async upsert, and entrypoint verification all succeeded."
