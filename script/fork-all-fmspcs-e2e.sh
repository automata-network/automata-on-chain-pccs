#!/usr/bin/env bash
# Loops the V2 async upsert flow against every published Intel SGX + TDX fmspc V4 endpoint,
# against a single forked Story Aeneid anvil instance. The fork starts once; for each
# TCB_EVALS entry we deploy/repoint a V2 DAO, then loop step 5 per fmspc with the
# correct --pck_ca and TCB_TYPE so each goes to the right Intel PCS endpoint and lands in
# the right DAO key. Step 6-8 (router lookup / quote verify) are skipped — this script only
# proves that the V2 upsert pipeline handles every published fmspc.
#
# Each fmspc's qpl-tool run produces several txs; the summary records every tx gas value
# instead of reducing a run to a total, so gas changes are visible at the ABI step level.
set -euo pipefail

export NO_PROXY="${NO_PROXY:-127.0.0.1,localhost}"
export no_proxy="${no_proxy:-127.0.0.1,localhost}"

STORY_RPC_URL="${STORY_RPC_URL:?missing STORY_RPC_URL}"
TCB_EVAL="${TCB_EVAL:-19}"
TCB_EVALS="${TCB_EVALS:-$TCB_EVAL}"
ONLY_TEE="${ONLY_TEE:-}"       # optional: sgx or tdx
ONLY_FMSPC="${ONLY_FMSPC:-}"   # optional: 12-char hex, case-insensitive
OWNER_ADDR="${OWNER_ADDR:-0xDf841B239bE7a6b37366005107069b7410da4Ff9}"
ATTESTER_ADDR="${ATTESTER_ADDR:-0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266}"
ATTESTER_PRIVATE_KEY="${ATTESTER_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
LOCAL_RPC_URL="${LOCAL_RPC_URL:-http://127.0.0.1:8545}"
ANVIL_PORT="${ANVIL_PORT:-8545}"
CHAIN_ID="${CHAIN_ID:-1315}"
QPL_GAS_PRICE="${QPL_GAS_PRICE:-50000000000}"
QPL_FALLBACK_GAS_LIMIT="${QPL_FALLBACK_GAS_LIMIT:-30000000}"
QPL_FUNC="upsert_tcb_fmspc_async"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCCS_REPO="${PCCS_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PROJECT_DIR="$(cd "$PCCS_REPO/.." && pwd)"
QPL_REPO="${QPL_REPO:-$PROJECT_DIR/automata-dcap-qpl/automata-dcap-qpl-tool}"
ANVIL_LOG="/tmp/story-aeneid-anvil-all.log"

# Published Intel PCS V4 fmspcs (as of 2026-05). Keep in sync with test/tcb/fixtures/pcs/fetch.sh.
SGX=(
  00606C040000 00906EC10000 00806F050000 00706E470000 00906EA10000 00906EA50000
  C0806F000000 00A06E050000 00A06D080000 20A06E050000 10A06F010000 B0C06F000000
  00606A000000 00806F000000 00906ED50000 F0806F000000 00906EB10000 10A06D000000
  00806EB70000 00A065510000 20A06D080000 90806F000000 30606A000000 00A067110000
  20806EB70000 70A06D070000 50806F000000 00706A100000 30806F040000 60A06F000000
  20A06F000000 20906EC10000 20606C040000 00706A800000 00906EC50000 00806EA60000
  90C06F000000
)
TDX=(
  10A06F010000 60A06F000000 20A06E050000 C0806F000000 70A06D070000 20A06D080000
  10A06D000000 00806F050000 20A06F000000 90C06F000000 50806F000000 B0C06F000000
  00A06D080000 00A06E050000
)

cleanup() {
  if [[ -n "${ANVIL_PID:-}" ]]; then
    kill "$ANVIL_PID" >/dev/null 2>&1 || true
    wait "$ANVIL_PID" >/dev/null 2>&1 || true
  fi
  pkill -f '^anvil ' >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ---------- one-time setup ----------
echo "[setup 1/4] Start Story Aeneid fork"
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
  if cast chain-id --rpc-url "$LOCAL_RPC_URL" >/dev/null 2>&1; then break; fi
  sleep 1
done
if ! cast chain-id --rpc-url "$LOCAL_RPC_URL" >/dev/null 2>&1; then
  echo "anvil failed to become ready; recent log:"
  tail -n 100 "$ANVIL_LOG" || true
  exit 1
fi

echo "[setup 2/4] Fund impersonated owner"
curl -sS -X POST "$LOCAL_RPC_URL" -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","method":"anvil_setBalance","params":["'"$OWNER_ADDR"'","0x3635C9ADC5DEA00000"],"id":1}' >/dev/null

deploy_eval_dao() {
  local eval_number="$1"
  local dao_json_key="AutomataFmspcTcbDaoVersionedV2_tcbeval_${eval_number}"
  echo "[setup 3/4] Delta update — deploy V2 helper + DAO + repoint router (TCB_EVAL=$eval_number)"
  cd "$PCCS_REPO"
  RPC_URL="$LOCAL_RPC_URL" \
  CHAIN_ID="$CHAIN_ID" \
  TCB_EVAL="$eval_number" \
  ATTESTER="$ATTESTER_ADDR" \
  UNLOCKED=true \
  OWNER="$OWNER_ADDR" \
  ./script/delta-update-existing-network.sh

  NEW_DAO=$(jq -r ".${dao_json_key}" "$PCCS_REPO/deployment/$CHAIN_ID.json")
  echo "[setup 4/4] DAO deployed for TCB_EVAL=$eval_number at: $NEW_DAO"
  echo
}

# ---------- per-fmspc upsert loop ----------
TMP_DIR="$(mktemp -d)"
SUMMARY=()    # rows of "eval platform fmspc status tx_gas_list elapsed"
cd "$QPL_REPO"
export QPL_FALLBACK_GAS_LIMIT
[[ -n "${QPL_ASYNC_PARSE_BATCH_SIZE:-}" ]] && export QPL_ASYNC_PARSE_BATCH_SIZE

run_one() {
  local eval_number="$1"
  local platform="$2"   # "sgx" or "tdx"
  local fmspc="$3"      # 12-char hex (any case)
  cd "$QPL_REPO"
  local pck_ca=""
  [[ "$platform" == "tdx" ]] && pck_ca="tdx"
  local out_file="$TMP_DIR/eval${eval_number}_${platform}_${fmspc}.log"
  echo "================================================================"
  echo "[upsert] tcbEval=$eval_number platform=$platform fmspc=$fmspc"
  echo "================================================================"
  local started_at
  started_at=$(date +%s)
  if cargo run --release --quiet -- \
        --function "$QPL_FUNC" \
        --private_key "$ATTESTER_PRIVATE_KEY" \
        --rpc_url "$LOCAL_RPC_URL" \
        --chain_id "$CHAIN_ID" \
        --gas_price "$QPL_GAS_PRICE" \
        --collateral_version v4 \
        --fmspc "$(echo "$fmspc" | tr 'A-Z' 'a-z')" \
        --pck_ca "$pck_ca" \
        --fmspc_tcb_dao_contract_addr "$NEW_DAO" \
        --tcb_evaluation_data_number "$eval_number" 2>&1 | tee "$out_file"; then
    local elapsed=$(( $(date +%s) - started_at ))
    # Parse the qpl receipts for per-tx gas
    local stats
    stats=$(grep -oE "txn\[[a-z_0-9]+\] receipt: Some\(TransactionReceipt \{[^}]*gas_used: Some\([0-9]+\)" "$out_file" \
            | sed -E 's/.*txn\[([a-z_0-9]+)\].*gas_used: Some\(([0-9]+).*/\1 \2/')
    if [[ -z "$stats" ]]; then
      SUMMARY+=("$eval_number|$platform|$fmspc|FAIL_NO_RECEIPTS|-|$elapsed")
      return
    fi
    local tx_gas_list
    tx_gas_list=$(echo "$stats" | awk '{printf "%s%s=%s", sep, $1, $2; sep=", "}')
    SUMMARY+=("$eval_number|$platform|$fmspc|OK|$tx_gas_list|$elapsed")
  else
    local elapsed=$(( $(date +%s) - started_at ))
    SUMMARY+=("$eval_number|$platform|$fmspc|FAIL|-|$elapsed")
  fi
}

should_run() {
  local platform="$1"
  local fmspc="$2"
  local want_tee want_fmspc
  want_tee="$(echo "$ONLY_TEE" | tr 'A-Z' 'a-z')"
  want_fmspc="$(echo "$ONLY_FMSPC" | tr 'a-z' 'A-Z')"
  if [[ -n "$want_tee" && "$platform" != "$want_tee" ]]; then
    return 1
  fi
  if [[ -n "$want_fmspc" && "$(echo "$fmspc" | tr 'a-z' 'A-Z')" != "$want_fmspc" ]]; then
    return 1
  fi
  return 0
}

IFS=',' read -r -a EVAL_LIST <<<"$TCB_EVALS"
for eval_number in "${EVAL_LIST[@]}"; do
  eval_number="$(echo "$eval_number" | xargs)"
  deploy_eval_dao "$eval_number"
  for fmspc in "${SGX[@]}"; do
    should_run sgx "$fmspc" && run_one "$eval_number" sgx "$fmspc"
  done
  for fmspc in "${TDX[@]}"; do
    should_run tdx "$fmspc" && run_one "$eval_number" tdx "$fmspc"
  done
done

# ---------- final summary ----------
echo
echo "================================================================"
echo "SUMMARY — async upsert against every published Intel V4 fmspc"
echo "TCB_EVALS=$TCB_EVALS"
[[ -n "$ONLY_TEE" ]] && echo "ONLY_TEE=$ONLY_TEE"
[[ -n "$ONLY_FMSPC" ]] && echo "ONLY_FMSPC=$ONLY_FMSPC"
echo "================================================================"
printf "| %-4s | %-3s | %-12s | %-16s | %-120s | %5s |\n" \
  "EVAL" "TEE" "FMSPC" "STATUS" "TX GAS" "WALL"
printf "|------|-----|--------------|------------------|--------------------------------------------------------------------------------------------------------------------------|------:|\n"
for row in "${SUMMARY[@]}"; do
  IFS='|' read -r eval_number platform fmspc status tx_gas_list elapsed <<<"$row"
  printf "| %-4s | %-3s | %-12s | %-16s | %-120s | %4ss |\n" \
    "$eval_number" "$(echo "$platform" | tr 'a-z' 'A-Z')" "$fmspc" "$status" "$tx_gas_list" "$elapsed"
done
echo
total_runs=${#SUMMARY[@]}
ok_runs=$(printf '%s\n' "${SUMMARY[@]}" | awk -F'|' '$4=="OK"{c++} END{print c+0}')
echo "Passed: $ok_runs / $total_runs"
echo "Done."
