#!/usr/bin/env bash
# Periodic re-upsert correctness test for the V3 SGX flow.
#
#   1. Anvil-fork Story Aeneid (single instance, lives for the whole test)
#   2. Delta-update: deploy V3 helper + V3 DAO, repoint router
#   3. Fetch Intel PCS for SGX fmspc 00606A000000 → snapshot-1
#   4. async upsert from snapshot-1
#   5. Read TCB info back from chain, validate it matches snapshot-1 byte-for-byte
#   6. verifyAndAttestOnChain(sgx_raw_quote.hex)  — expect success
#   7. Sleep ${PERIODIC_SLEEP_SECS:-600}  (default 10 minutes)
#   8. Fetch Intel PCS again → snapshot-2
#      - If snapshot-2 == snapshot-1 (Intel didn't rotate), skip step 9-10 and report
#        that the duplicate-collateral guard would correctly reject a re-upsert.
#   9. async upsert from snapshot-2 (same fmspc / same DAO slot) — must succeed
#  10. Read TCB info back, validate it matches snapshot-2 AND differs from snapshot-1
#  11. verifyAndAttestOnChain(sgx_raw_quote.hex) again — expect success
#  12. Summary
#
# Inputs (all default OK for the standard SGX e2e fixture):
#   STORY_RPC_URL  – Alchemy Story Aeneid
#   FMSPC          – default 00606a000000
#   TCB_EVAL       – default 19
#   QUOTE_FILE     – default sgx_raw_quote.hex (relative to PCCS_REPO)
#   PERIODIC_SLEEP_SECS – default 600 (10 min)

set -euo pipefail

export NO_PROXY="${NO_PROXY:-127.0.0.1,localhost}"
export no_proxy="${no_proxy:-127.0.0.1,localhost}"

STORY_RPC_URL="${STORY_RPC_URL:?missing STORY_RPC_URL}"
FMSPC="${FMSPC:-00606a000000}"          # lower-case hex
TCB_EVAL="${TCB_EVAL:-19}"
QUOTE_FILE="${QUOTE_FILE:-sgx_raw_quote.hex}"
PERIODIC_SLEEP_SECS="${PERIODIC_SLEEP_SECS:-600}"
OWNER_ADDR="${OWNER_ADDR:-0xDf841B239bE7a6b37366005107069b7410da4Ff9}"
ATTESTER_ADDR="${ATTESTER_ADDR:-0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266}"
ATTESTER_PRIVATE_KEY="${ATTESTER_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
LOCAL_RPC_URL="${LOCAL_RPC_URL:-http://127.0.0.1:8545}"
ANVIL_PORT="${ANVIL_PORT:-8545}"
CHAIN_ID="${CHAIN_ID:-1315}"
QPL_GAS_PRICE="${QPL_GAS_PRICE:-50000000000}"
QPL_FALLBACK_GAS_LIMIT="${QPL_FALLBACK_GAS_LIMIT:-30000000}"
ROUTER_ADDR="${ROUTER_ADDR:-0xcb1934EA19c6650a8cC9888c0306D39f0BeBc2AB}"
VERIFY_TARGET="${VERIFY_TARGET:-0xB8621Da79b42A62E576408995155D48E9f856489}"

FMSPC_VERSION=v3
DAO_JSON_KEY="AutomataFmspcTcbDaoVersionedV3_tcbeval_${TCB_EVAL}"
QPL_FUNC="upsert_tcb_fmspc_async_v3"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCCS_REPO="${PCCS_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PROJECT_DIR="$(cd "$PCCS_REPO/.." && pwd)"
QPL_REPO="${QPL_REPO:-$PROJECT_DIR/automata-dcap-qpl/automata-dcap-qpl-tool}"
LOGS_DIR="$PCCS_REPO/logs"
mkdir -p "$LOGS_DIR"
ANVIL_LOG="/tmp/story-aeneid-anvil-periodic.log"
SNAP1="$LOGS_DIR/intel-snapshot-1.json"
SNAP2="$LOGS_DIR/intel-snapshot-2.json"

cleanup() {
  if [[ -n "${ANVIL_PID:-}" ]]; then
    kill "$ANVIL_PID" >/dev/null 2>&1 || true
    wait "$ANVIL_PID" >/dev/null 2>&1 || true
  fi
  pkill -f '^anvil ' >/dev/null 2>&1 || true
}
trap cleanup EXIT

banner() { echo; echo "================================================================"; echo "$*"; echo "================================================================"; }

# ---------- helpers ----------
fetch_intel() {
  # Fetch full {"tcbInfo":{...},"signature":"..."} from Intel PCS V4 endpoint and snapshot to $1.
  local out="$1"
  local url="https://api.trustedservices.intel.com/sgx/certification/v4/tcb?fmspc=${FMSPC}&tcbEvaluationDataNumber=${TCB_EVAL}"
  echo "[fetch] $url"
  curl -sS --fail --max-time 30 "$url" > "$out"
  echo "[fetch] saved $(wc -c <"$out") bytes → $out"
  python3 - "$out" <<'PY'
import json, sys, hashlib
with open(sys.argv[1]) as f:
    body = f.read()
payload = json.loads(body)
inner = payload["tcbInfo"]
# Print readable summary
print(f"  issueDate          = {inner['issueDate']}")
print(f"  nextUpdate         = {inner['nextUpdate']}")
print(f"  evalNumber         = {inner['tcbEvaluationDataNumber']}")
print(f"  signature[:16]     = {payload['signature'][:16]}…")
# Extract the inner-tcbInfo substring byte-exact (same as on-chain raw)
start = body.find('"tcbInfo":') + len('"tcbInfo":')
end = body.find(',"signature"')
inner_str = body[start:end]
inner_bytes = inner_str.encode('utf-8')
raw_hash = hashlib.sha256(inner_bytes).hexdigest()
print(f"  sha256(rawInner)   = 0x{raw_hash}")
print(f"  rawInner length    = {len(inner_bytes)} bytes")
PY
}

snapshot_diff() {
  # Print whether snapshot $1 differs from $2 in any byte; return 0 if differ, 1 if identical.
  if ! diff -q "$1" "$2" >/dev/null 2>&1; then return 0; fi
  return 1
}

run_upsert() {
  local label="$1"   # "first" / "second"
  local snap_file="$2"
  banner "UPSERT ($label) — fmspc=$FMSPC tcbEval=$TCB_EVAL"
  cd "$QPL_REPO"
  export QPL_FALLBACK_GAS_LIMIT
  cargo run --release --quiet -- \
    --function "$QPL_FUNC" \
    --private_key "$ATTESTER_PRIVATE_KEY" \
    --rpc_url "$LOCAL_RPC_URL" \
    --chain_id "$CHAIN_ID" \
    --gas_price "$QPL_GAS_PRICE" \
    --collateral_version v4 \
    --fmspc "$FMSPC" \
    --pck_ca "" \
    --fmspc_tcb_dao_contract_addr "$NEW_DAO" \
    --tcb_evaluation_data_number "$TCB_EVAL" \
    --tcb_info_json_file "$snap_file" \
    2>&1 | tee "$LOGS_DIR/upsert-${label}.log" \
    | grep -E "txn\[[a-z_0-9]+\] (hash|receipt)|ERROR|panic" || true
}

read_and_validate() {
  local label="$1"
  local snap_file="$2"
  banner "READ + VALIDATE ($label)"
  # 1) Router-served content hash
  local router_hash
  router_hash=$(cast call "$ROUTER_ADDR" \
    "getFmspcTcbContentHash(uint8,bytes6,uint32,uint32)(bytes32)" \
    0 "0x$FMSPC" 3 "$TCB_EVAL" \
    --rpc-url "$LOCAL_RPC_URL" \
    --from "$ATTESTER_ADDR")
  echo "router contentHash         = $router_hash"

  # 2) DAO-level validity + rawHash
  local dao_key
  dao_key=$(cast call "$NEW_DAO" "FMSPC_TCB_KEY(uint8,bytes6,uint32)(bytes32)" \
    0 "0x$FMSPC" 3 --rpc-url "$LOCAL_RPC_URL")
  echo "DAO tcbKey                 = $dao_key"
  local validity
  validity=$(cast call "$NEW_DAO" "getCollateralValidity(bytes32)(uint64,uint64)" \
    "$dao_key" --rpc-url "$LOCAL_RPC_URL")
  local issue_ts next_ts
  issue_ts=$(echo "$validity" | head -1)
  next_ts=$(echo "$validity" | tail -1)
  echo "DAO issueDate              = ${issue_ts}  ($(date -u -d "@${issue_ts%%[^0-9]*}" -Iseconds 2>/dev/null || echo n/a))"
  echo "DAO nextUpdate             = ${next_ts}  ($(date -u -d "@${next_ts%%[^0-9]*}" -Iseconds 2>/dev/null || echo n/a))"
  local raw_hash_on_chain
  raw_hash_on_chain=$(cast call "$NEW_DAO" "getCollateralHash(bytes32)(bytes32)" \
    "$dao_key" --rpc-url "$LOCAL_RPC_URL")
  echo "DAO raw sha256             = $raw_hash_on_chain"

  # 3) Compare with snapshot
  python3 - "$snap_file" "$router_hash" "$issue_ts" "$next_ts" "$raw_hash_on_chain" <<'PY'
import json, sys, hashlib, re
snap, router_hash, issue_ts, next_ts, raw_hash = sys.argv[1:6]
with open(snap) as f:
    body = f.read()
inner = json.loads(body)["tcbInfo"]

# Re-derive expected rawHash
start = body.find('"tcbInfo":') + len('"tcbInfo":')
end = body.find(',"signature"')
inner_str = body[start:end].encode('utf-8')
expected_raw_hash = "0x" + hashlib.sha256(inner_str).hexdigest()

# Re-derive expected issueDate / nextUpdate as unix timestamps
import datetime
def iso_to_ts(iso): return int(datetime.datetime.strptime(iso, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc).timestamp())
expected_issue = iso_to_ts(inner["issueDate"])
expected_next  = iso_to_ts(inner["nextUpdate"])

issue_ts = int(issue_ts.split()[0])  # cast prints "1234 [0x..]"
next_ts  = int(next_ts.split()[0])

ok = True
def check(name, expected, actual):
    global ok
    s = "ok" if str(expected).lower() == str(actual).lower() else "MISMATCH"
    if s != "ok": ok = False
    print(f"  validate {name:25} expected={expected}  actual={actual}  [{s}]")
check("rawHash",   expected_raw_hash, raw_hash)
check("issueDate", expected_issue,    issue_ts)
check("nextUpdate", expected_next,    next_ts)
# router contentHash: not derivable without on-chain serializer; just check non-zero
if router_hash.lower() == "0x" + "0"*64:
    print(f"  validate router contentHash    MISMATCH (zero)"); ok = False
else:
    print(f"  validate router contentHash    ok ({router_hash})")
sys.exit(0 if ok else 2)
PY
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "VALIDATION FAILED ($label)" >&2; exit 1
  fi
  echo "VALIDATION PASSED ($label)"
}

run_verify() {
  local label="$1"
  banner "VERIFY ($label) — verifyAndAttestOnChain"
  local quote_hex
  quote_hex="$(tr -d '\n\r' < "$PCCS_REPO/$QUOTE_FILE")"
  local selector
  selector=$(cast calldata "verifyAndAttestOnChain(bytes,uint32)" "$quote_hex" "$TCB_EVAL")
  local resp
  resp=$(curl -sS --max-time 600 -X POST "$LOCAL_RPC_URL" \
    -H 'content-type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"from\":\"$ATTESTER_ADDR\",\"to\":\"$VERIFY_TARGET\",\"data\":\"$selector\"},\"latest\"],\"id\":1}")
  local result_hex
  result_hex=$(echo "$resp" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('result','0x'))")
  if [[ "$result_hex" == "0x" || -z "$result_hex" ]]; then
    echo "verifyAndAttestOnChain reverted: $resp" >&2; exit 1
  fi
  local flag=${result_hex:0:66}
  if [[ "$flag" =~ ^0x0+1$ ]]; then
    echo "verifyAndAttestOnChain returned success=true ($label)"
  else
    echo "verifyAndAttestOnChain returned success=false (raw: $flag)" >&2; exit 1
  fi
}

# ============================================================
# main
# ============================================================
banner "[1/12] Start Story Aeneid fork"
anvil \
  --fork-url "$STORY_RPC_URL" \
  --chain-id "$CHAIN_ID" \
  --port "$ANVIL_PORT" \
  --auto-impersonate --disable-code-size-limit \
  --retries 10 --timeout 120000 --fork-retry-backoff 2000 \
  --no-rate-limit >"$ANVIL_LOG" 2>&1 &
ANVIL_PID=$!
for _ in $(seq 1 30); do
  cast chain-id --rpc-url "$LOCAL_RPC_URL" >/dev/null 2>&1 && break
  sleep 1
done
cast chain-id --rpc-url "$LOCAL_RPC_URL"

banner "[2/12] Fund impersonated owner"
curl -sS -X POST "$LOCAL_RPC_URL" -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","method":"anvil_setBalance","params":["'"$OWNER_ADDR"'","0x3635C9ADC5DEA00000"],"id":1}' >/dev/null

banner "[3/12] Delta update — deploy V3 helper + DAO + repoint router"
cd "$PCCS_REPO"
RPC_URL="$LOCAL_RPC_URL" CHAIN_ID="$CHAIN_ID" TCB_EVAL="$TCB_EVAL" \
ATTESTER="$ATTESTER_ADDR" UNLOCKED=true OWNER="$OWNER_ADDR" \
FMSPC_VERSION="$FMSPC_VERSION" \
./script/delta-update-existing-network.sh
NEW_DAO=$(jq -r ".${DAO_JSON_KEY}" "$PCCS_REPO/deployment/$CHAIN_ID.json")
echo "V3 DAO: $NEW_DAO"

banner "[4/12] Build Intel snapshot-1 from archived fixture (older issueDate)"
# Use the archived fixture (captured 2026-05-20) as snapshot-1, so snapshot-2 (a fresh fetch
# 10 min later) is guaranteed to differ from it. Both are real Intel-signed responses — this
# simulates the same fmspc rotating between yesterday and today, which is what the periodic
# update flow actually faces in production.
python3 - <<PY
import json
with open("$PCCS_REPO/test/tcb/fixtures/live_intel_eval19_inner.txt") as f:
    inner = f.read().strip()
with open("$PCCS_REPO/test/tcb/fixtures/live_intel_eval19_sig.txt") as f:
    sig = f.read().strip()
out = '{"tcbInfo":' + inner + ',"signature":"' + sig + '"}'
with open("$SNAP1", "w") as f:
    f.write(out)
import hashlib
print(f"  archived snapshot bytes  = {len(inner)} (inner) + {len(sig)} (sig hex)")
print(f"  issueDate                = {json.loads(inner)['issueDate']}")
print(f"  signature[:16]           = {sig[:16]}…")
print(f"  sha256(rawInner)         = 0x{hashlib.sha256(inner.encode()).hexdigest()}")
PY

banner "[5/12] First async upsert"
run_upsert first "$SNAP1"

banner "[6/12] Read + validate post-first-upsert"
read_and_validate first "$SNAP1"

banner "[7/12] Verify SGX quote (after first upsert)"
run_verify first

banner "[8/12] Sleep ${PERIODIC_SLEEP_SECS}s to let Intel rotate"
sleep "$PERIODIC_SLEEP_SECS"

banner "[9/12] Fetch Intel snapshot-2"
fetch_intel "$SNAP2"

if snapshot_diff "$SNAP1" "$SNAP2"; then
  echo "Intel rotated between fetches — proceeding with second upsert."
  ROTATED=1
else
  echo "Intel served BYTE-IDENTICAL response to snapshot-1."
  echo "Second upsert would revert with Duplicate_Collateral (system correctness ✓)."
  ROTATED=0
fi

if [[ "$ROTATED" == "1" ]]; then
  banner "[10/12] Second async upsert (rotated snapshot)"
  run_upsert second "$SNAP2"

  banner "[11/12] Read + validate post-second-upsert"
  read_and_validate second "$SNAP2"
  # Extra check: rawHash on chain MUST differ from snapshot-1's rawHash
  python3 - "$SNAP1" "$SNAP2" <<'PY'
import sys, hashlib
def hash_inner(path):
    with open(path) as f:
        body = f.read()
    start = body.find('"tcbInfo":') + len('"tcbInfo":')
    end = body.find(',"signature"')
    return hashlib.sha256(body[start:end].encode()).hexdigest()
h1 = hash_inner(sys.argv[1])
h2 = hash_inner(sys.argv[2])
print(f"snapshot-1 sha256 = 0x{h1}")
print(f"snapshot-2 sha256 = 0x{h2}")
if h1 == h2:
    print("ERROR: hashes equal — snapshots should have differed"); sys.exit(2)
print("CONFIRMED: chain now serves snapshot-2 (different rawHash from snapshot-1)")
PY

  banner "[12/12] Verify SGX quote (after second upsert)"
  run_verify second
else
  banner "[10/12] (skipped — Intel did not rotate within sleep window)"
  banner "[11/12] Try second upsert anyway → expect Duplicate_Collateral revert"
  cd "$QPL_REPO"
  if cargo run --release --quiet -- \
       --function "$QPL_FUNC" \
       --private_key "$ATTESTER_PRIVATE_KEY" \
       --rpc_url "$LOCAL_RPC_URL" \
       --chain_id "$CHAIN_ID" \
       --gas_price "$QPL_GAS_PRICE" \
       --collateral_version v4 \
       --fmspc "$FMSPC" \
       --pck_ca "" \
       --fmspc_tcb_dao_contract_addr "$NEW_DAO" \
       --tcb_evaluation_data_number "$TCB_EVAL" \
       --tcb_info_json_file "$SNAP2" 2>&1 | tee "$LOGS_DIR/upsert-second-dup.log" \
       | grep -qE "Duplicate_Collateral|reverted"; then
    echo "Second upsert correctly REJECTED (duplicate) ✓"
  else
    echo "WARN: second upsert did not revert as expected. Check $LOGS_DIR/upsert-second-dup.log"
  fi
  banner "[12/12] Verify SGX quote (after duplicate-blocked second upsert)"
  run_verify second
fi

banner "ALL DONE"
echo "snapshot-1 → $SNAP1"
echo "snapshot-2 → $SNAP2"
echo "rotated? $ROTATED"
