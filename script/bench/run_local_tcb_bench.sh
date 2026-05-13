#!/usr/bin/env bash
set -euo pipefail

unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy

ROOT="/home/rustdev/shared/code/automata-on-chain-pccs"
QPL_REPO="/home/rustdev/shared/code/automata-dcap-qpl/automata-dcap-qpl-tool"
RUN_ROOT="${RUN_ROOT:-/tmp/local-tcb-bench-$(date +%s)}"
BENCH_JSON_PATH="$ROOT/script/bench/local-tcb-bench.json"
ANVIL_PORT="${ANVIL_PORT:-8547}"
RPC_URL="http://127.0.0.1:${ANVIL_PORT}"
CHAIN_ID="${CHAIN_ID:-31337}"
PRIVATE_KEY="${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
ATTESTER_ADDR="${ATTESTER_ADDR:-0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266}"
QPL_GAS_PRICE="${QPL_GAS_PRICE:-50000000000}"
QPL_FALLBACK_GAS_LIMIT="${QPL_FALLBACK_GAS_LIMIT:-30000000}"
TCB_INFO_PATH="${TCB_INFO_PATH:-$ROOT/test/tcb/fixtures/case3_sgx_tcbinfo.json}"
SIG_PATH="${SIG_PATH:-$ROOT/test/tcb/fixtures/case3_sgx_signature.txt}"
SNAPSHOT_ID=""
DEPLOY_TIMESTAMP="${DEPLOY_TIMESTAMP:-1718785993}"
UPSERT_TIMESTAMP="${UPSERT_TIMESTAMP:-1778889600}"
BATCHES="${BATCHES:-1 3 999}"

mkdir -p "$RUN_ROOT"

cleanup() {
  if [[ -n "${ANVIL_PID:-}" ]]; then
    kill "$ANVIL_PID" >/dev/null 2>&1 || true
    wait "$ANVIL_PID" >/dev/null 2>&1 || true
  fi
  pkill -f "^anvil .*--port ${ANVIL_PORT}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

start_anvil() {
  pkill -f "^anvil .*--port ${ANVIL_PORT}" >/dev/null 2>&1 || true
  anvil --port "$ANVIL_PORT" --chain-id "$CHAIN_ID" --gas-price 0 --block-base-fee-per-gas 0 \
    --timestamp "$DEPLOY_TIMESTAMP" \
    >"$RUN_ROOT/anvil.log" 2>&1 &
  ANVIL_PID=$!
  for _ in $(seq 1 30); do
    if cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "anvil failed to start" >&2
  tail -n 50 "$RUN_ROOT/anvil.log" >&2 || true
  return 1
}

deploy_bench() {
  (
    cd "$ROOT"
    forge script script/bench/DeployLocalTcbBench.s.sol:DeployLocalTcbBench \
      --rpc-url "$RPC_URL" \
      --private-key "$PRIVATE_KEY" \
      --broadcast --skip-simulation -vv
  ) >"$RUN_ROOT/deploy.log" 2>&1
  cp "$BENCH_JSON_PATH" "$RUN_ROOT/bench.json"
}

snapshot_chain() {
  SNAPSHOT_ID=$(curl -sS -X POST "$RPC_URL" -H 'content-type: application/json' \
    --data '{"jsonrpc":"2.0","method":"evm_snapshot","params":[],"id":1}' | jq -r '.result')
}

revert_chain() {
  curl -sS -X POST "$RPC_URL" -H 'content-type: application/json' \
    --data '{"jsonrpc":"2.0","method":"evm_revert","params":["'"$SNAPSHOT_ID"'"],"id":1}' >/dev/null
  snapshot_chain
}

set_upsert_time() {
  curl -sS -X POST "$RPC_URL" -H 'content-type: application/json' \
    --data '{"jsonrpc":"2.0","method":"evm_setNextBlockTimestamp","params":['"$UPSERT_TIMESTAMP"'],"id":1}' >/dev/null
  curl -sS -X POST "$RPC_URL" -H 'content-type: application/json' \
    --data '{"jsonrpc":"2.0","method":"evm_mine","params":[],"id":1}' >/dev/null
}

parse_async_log() {
  local logfile="$1"
  local outfile="$2"
  perl -ne '
    if (/txn\[(.+?)\] receipt: .*?transaction_hash: (0x[0-9a-f]+).*?gas_used: Some\((\d+)\).*?status: Some\((\d+)\)/i) {
      my ($label, $hash, $gas, $status) = ($1, $2, $3, $4);
      my $success = $status == 1 ? "true" : "false";
      print "{\"label\":\"$label\",\"success\":$success,\"tx_hash\":\"$hash\",\"gas\":$gas}\n";
    }
  ' "$logfile" | jq -s '.' >"$outfile"
}

sum_gas() {
  jq '[.[].gas] | add // 0' "$1"
}

run_legacy() {
  local dao
  dao=$(jq -r '.dao_v1' "$RUN_ROOT/bench.json")
  local tcb_info signature
  tcb_info=$(jq -c '.' "$TCB_INFO_PATH")
  signature="0x$(tr -d '\n\r ' < "$SIG_PATH")"

  (
    cd "$ROOT"
    LEGACY_FMSPC_DAO="$dao" \
    LEGACY_TCB_INFO_JSON="$tcb_info" \
    LEGACY_TCB_INFO_SIGNATURE="$signature" \
    forge script script/bench/LegacyFmspcSyncUpsert.s.sol:LegacyFmspcSyncUpsert \
      --rpc-url "$RPC_URL" \
      --private-key "$PRIVATE_KEY" \
      --broadcast --skip-simulation -vv
  ) >"$RUN_ROOT/legacy.log" 2>&1

  jq -n \
    --arg tx_hash "$(jq -r '.receipts[0].transactionHash' "$ROOT/broadcast/LegacyFmspcSyncUpsert.s.sol/$CHAIN_ID/run-latest.json")" \
    --argjson gas "$(cast to-dec "$(jq -r '.receipts[0].gasUsed' "$ROOT/broadcast/LegacyFmspcSyncUpsert.s.sol/$CHAIN_ID/run-latest.json")")" \
    --arg status "$(jq -r '.receipts[0].status' "$ROOT/broadcast/LegacyFmspcSyncUpsert.s.sol/$CHAIN_ID/run-latest.json")" \
    '[{label:"legacy_sync_upsert", success:($status=="0x1"), tx_hash:$tx_hash, gas:$gas}]' >"$RUN_ROOT/legacy.json"
}

run_async_batch() {
  local batch="$1"
  local tag="batch${batch}"
  local dao
  dao=$(jq -r '.dao_v2' "$RUN_ROOT/bench.json")

  (
    cd "$QPL_REPO"
    QPL_FALLBACK_GAS_LIMIT="$QPL_FALLBACK_GAS_LIMIT" \
    QPL_ASYNC_PARSE_BATCH_SIZE="$batch" \
    cargo run -- \
      --function upsert_tcb_fmspc_async \
      --private_key "$PRIVATE_KEY" \
      --rpc_url "$RPC_URL" \
      --chain_id "$CHAIN_ID" \
      --gas_price "$QPL_GAS_PRICE" \
      --collateral_version v4 \
      --fmspc 00606a000000 \
      --fmspc_tcb_dao_contract_addr "$dao" \
      --tcb_info_json_file "$TCB_INFO_PATH"
  ) >"$RUN_ROOT/${tag}.log" 2>&1 || true

  parse_async_log "$RUN_ROOT/${tag}.log" "$RUN_ROOT/${tag}.json"
}

emit_summary() {
  RUN_ROOT="$RUN_ROOT" BATCHES="$BATCHES" python3 - <<'PY' >"$RUN_ROOT/summary.json"
import json
import os
from pathlib import Path

run_root = Path(os.environ["RUN_ROOT"])
batches = [int(x) for x in os.environ["BATCHES"].split()]

with open(run_root / "legacy.json") as f:
    legacy = json.load(f)

def load_batch(batch: int):
    with open(run_root / f"batch{batch}.json") as f:
        return json.load(f)

def total(entries):
    return sum(item["gas"] for item in entries)

summary = {
    "legacy": legacy,
    "totals": {"legacy": total(legacy)},
    "extra_vs_legacy": {},
}

for batch in batches:
    entries = load_batch(batch)
    key = f"batch{batch}"
    batch_total = total(entries)
    summary[key] = entries
    summary["totals"][key] = batch_total
    summary["extra_vs_legacy"][key] = batch_total - summary["totals"]["legacy"]

print(json.dumps(summary))
PY
}

start_anvil
deploy_bench
set_upsert_time
snapshot_chain

run_legacy
revert_chain

first_batch=true
for batch in $BATCHES; do
  if [[ "$first_batch" != "true" ]]; then
    revert_chain
  fi
  run_async_batch "$batch"
  first_batch=false
done

emit_summary
echo "Results written to: $RUN_ROOT"
