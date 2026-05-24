#!/usr/bin/env bash
# Loops the V2 async upsert flow against every published Intel SGX + TDX fmspc V4 endpoint,
# against a single forked Story Aeneid anvil instance. Deploy/setup happens ONCE up front;
# steps 1-4 of fork-story-aeneid-e2e.sh are reused, then we loop step 5 per fmspc with the
# correct --pck_ca and TCB_TYPE so each goes to the right Intel PCS endpoint and lands in
# the right DAO key. Step 6-8 (router lookup / quote verify) are skipped — this script only
# proves that the V2 upsert pipeline handles every published fmspc.
#
# Each fmspc's qpl-tool run produces ~5-12 txs; we summarise per-fmspc totals + the heaviest
# single tx at the end as a markdown table.
set -euo pipefail

export NO_PROXY="${NO_PROXY:-127.0.0.1,localhost}"
export no_proxy="${no_proxy:-127.0.0.1,localhost}"

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
DAO_JSON_KEY="AutomataFmspcTcbDaoVersionedV2_tcbeval_${TCB_EVAL}"
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

echo "[setup 3/4] Delta update — deploy V2 helper + DAO + repoint router (one-time)"
cd "$PCCS_REPO"
RPC_URL="$LOCAL_RPC_URL" \
CHAIN_ID="$CHAIN_ID" \
TCB_EVAL="$TCB_EVAL" \
ATTESTER="$ATTESTER_ADDR" \
UNLOCKED=true \
OWNER="$OWNER_ADDR" \
./script/delta-update-existing-network.sh

NEW_DAO=$(jq -r ".${DAO_JSON_KEY}" "$PCCS_REPO/deployment/$CHAIN_ID.json")
echo "[setup 4/4] DAO deployed at: $NEW_DAO"
echo

# ---------- per-fmspc upsert loop ----------
TMP_DIR="$(mktemp -d)"
SUMMARY=()    # rows of "platform fmspc status total_gas heaviest_tx heaviest_gas"
cd "$QPL_REPO"
export QPL_FALLBACK_GAS_LIMIT
[[ -n "${QPL_ASYNC_PARSE_BATCH_SIZE:-}" ]] && export QPL_ASYNC_PARSE_BATCH_SIZE

run_one() {
  local platform="$1"   # "sgx" or "tdx"
  local fmspc="$2"      # 12-char hex (any case)
  local pck_ca=""
  [[ "$platform" == "tdx" ]] && pck_ca="tdx"
  local out_file="$TMP_DIR/${platform}_${fmspc}.log"
  echo "================================================================"
  echo "[upsert] platform=$platform fmspc=$fmspc"
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
        --tcb_evaluation_data_number "$TCB_EVAL" 2>&1 | tee "$out_file"; then
    local elapsed=$(( $(date +%s) - started_at ))
    # Parse the qpl receipts for per-tx gas
    local stats
    stats=$(grep -oE "txn\[[a-z_0-9]+\] receipt: Some\(TransactionReceipt \{[^}]*gas_used: Some\([0-9]+\)" "$out_file" \
            | sed -E 's/.*txn\[([a-z_0-9]+)\].*gas_used: Some\(([0-9]+).*/\1 \2/')
    if [[ -z "$stats" ]]; then
      SUMMARY+=("$platform|$fmspc|FAIL_NO_RECEIPTS|0|-|0|$elapsed")
      return
    fi
    local total
    total=$(echo "$stats" | awk '{s+=$2} END{print s}')
    local heaviest
    heaviest=$(echo "$stats" | sort -k2 -n | tail -1)
    local heaviest_name=$(echo "$heaviest" | awk '{print $1}')
    local heaviest_gas=$(echo "$heaviest" | awk '{print $2}')
    SUMMARY+=("$platform|$fmspc|OK|$total|$heaviest_name|$heaviest_gas|$elapsed")
  else
    local elapsed=$(( $(date +%s) - started_at ))
    SUMMARY+=("$platform|$fmspc|FAIL|0|-|0|$elapsed")
  fi
}

for fmspc in "${SGX[@]}"; do run_one sgx "$fmspc"; done
for fmspc in "${TDX[@]}"; do run_one tdx "$fmspc"; done

# ---------- final summary ----------
echo
echo "================================================================"
echo "SUMMARY — async upsert against every published Intel V4 fmspc"
echo "TCB_EVAL=$TCB_EVAL DAO=$NEW_DAO"
echo "================================================================"
printf "| %-3s | %-12s | %-6s | %14s | %-37s | %14s | %5s |\n" \
  "TEE" "FMSPC" "STATUS" "TOTAL GAS" "HEAVIEST TX" "HEAVIEST GAS" "WALL"
printf "|-----|--------------|--------|---------------:|---------------------------------------|---------------:|------:|\n"
for row in "${SUMMARY[@]}"; do
  IFS='|' read -r platform fmspc status total heaviest_name heaviest_gas elapsed <<<"$row"
  printf "| %-3s | %-12s | %-6s | %14s | %-37s | %14s | %4ss |\n" \
    "$(echo "$platform" | tr 'a-z' 'A-Z')" "$fmspc" "$status" \
    "$(printf "%'d" "$total")" "$heaviest_name" \
    "$(printf "%'d" "$heaviest_gas")" "$elapsed"
done
echo
total_runs=${#SUMMARY[@]}
ok_runs=$(printf '%s\n' "${SUMMARY[@]}" | awk -F'|' '$3=="OK"{c++} END{print c+0}')
echo "Passed: $ok_runs / $total_runs"
echo "Done."
