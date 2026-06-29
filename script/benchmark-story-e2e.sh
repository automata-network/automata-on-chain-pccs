#!/usr/bin/env bash
set -euo pipefail

unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy

MODE="${1:?usage: benchmark-story-e2e.sh <repeat-batch1|compare-batches|single-batch>}"

STORY_RPC_URL="${STORY_RPC_URL:?missing STORY_RPC_URL}"
TCB_EVAL="${TCB_EVAL:-19}"
FMSPC_HEX="${FMSPC_HEX:-00606a000000}"
COLLATERAL_VERSION="${COLLATERAL_VERSION:-v4}"
OWNER_ADDR="${OWNER_ADDR:-0xDf841B239bE7a6b37366005107069b7410da4Ff9}"
ATTESTER_ADDR="${ATTESTER_ADDR:-0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266}"
ATTESTER_PRIVATE_KEY="${ATTESTER_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
LOCAL_RPC_URL="${LOCAL_RPC_URL:-http://127.0.0.1:8545}"
ANVIL_PORT="${ANVIL_PORT:-8545}"
CHAIN_ID="${CHAIN_ID:-1315}"
QPL_GAS_PRICE="${QPL_GAS_PRICE:-50000000000}"
QPL_FALLBACK_GAS_LIMIT="${QPL_FALLBACK_GAS_LIMIT:-30000000}"
QUOTE_TX_HASH="${QUOTE_TX_HASH:-0xa7b1120210ccb7dc8ef0ce05f9b3db9fe90e611418b5ff7174efba89b2eb22a0}"
P256_SHIM_ADDR="${P256_SHIM_ADDR:-0xc2b78104907F722DABAc4C69f826a522B2754De4}"
RIP7212_ADDR="0x0000000000000000000000000000000000000100"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-75}"
POLL_ATTEMPTS="${POLL_ATTEMPTS:-4}"
NETWORK_RETRIES="${NETWORK_RETRIES:-5}"
NETWORK_RETRY_DELAY="${NETWORK_RETRY_DELAY:-5}"
BENCH_BATCH="${BENCH_BATCH:-1}"
PAYLOAD_FILE="${PAYLOAD_FILE:-}"

PCCS_REPO="/home/rustdev/shared/code/automata-on-chain-pccs"
DCAP_REPO="/home/rustdev/shared/code/automata-dcap-attestation"
QPL_REPO="/home/rustdev/shared/code/automata-dcap-qpl/automata-dcap-qpl-tool"
RUN_ROOT="${RUN_ROOT:-/tmp/story-bench-$(date +%s)}"
mkdir -p "$RUN_ROOT"

ANVIL_PID=""
ANVIL_LOG="$RUN_ROOT/anvil.log"

cleanup() {
  if [[ -n "$ANVIL_PID" ]]; then
    kill "$ANVIL_PID" >/dev/null 2>&1 || true
    wait "$ANVIL_PID" >/dev/null 2>&1 || true
  fi
  pkill -f '^anvil ' >/dev/null 2>&1 || true
}
trap cleanup EXIT

extract_quote_from_tx() {
  local tx_hash="$1"
  local tx_input
  local attempt
  for attempt in $(seq 1 "$NETWORK_RETRIES"); do
    if tx_input=$(cast tx "$tx_hash" --rpc-url "$STORY_RPC_URL" | awk '/^input /{$1=""; sub(/^ +/,""); print}'); then
      break
    fi
    sleep "$NETWORK_RETRY_DELAY"
  done
  if [[ -z "${tx_input:-}" ]]; then
    echo "failed to fetch quote tx input after retries" >&2
    return 1
  fi
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

QUOTE_HEX="$(extract_quote_from_tx "$QUOTE_TX_HASH")"

start_fork() {
  local rip7212_code
  local shim_code
  local attempt
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

  cast chain-id --rpc-url "$LOCAL_RPC_URL" >/dev/null
  curl -sS -X POST "$LOCAL_RPC_URL" -H 'content-type: application/json' \
    --data '{"jsonrpc":"2.0","method":"anvil_setBalance","params":["'"$OWNER_ADDR"'","0x3635C9ADC5DEA00000"],"id":1}' >/dev/null

  rip7212_code=$(cast code "$RIP7212_ADDR" --rpc-url "$LOCAL_RPC_URL")
  if [[ "$rip7212_code" == "0x" ]]; then
    for attempt in $(seq 1 "$NETWORK_RETRIES"); do
      if shim_code=$(cast code "$P256_SHIM_ADDR" --rpc-url "$STORY_RPC_URL"); then
        break
      fi
      sleep "$NETWORK_RETRY_DELAY"
    done
    if [[ -z "${shim_code:-}" || "$shim_code" == "0x" ]]; then
      echo "failed to fetch P256 shim code after retries" >&2
      return 1
    fi
    curl -sS -X POST "$LOCAL_RPC_URL" -H 'content-type: application/json' \
      --data '{"jsonrpc":"2.0","method":"anvil_setCode","params":["'"$RIP7212_ADDR"'","'"$shim_code"'"],"id":1}' >/dev/null
  fi
}

stop_fork() {
  cleanup
  ANVIL_PID=""
}

fetch_payload() {
  local outfile="$1"
  local attempt
  for attempt in $(seq 1 "$NETWORK_RETRIES"); do
    if curl -sS "https://api.trustedservices.intel.com/sgx/certification/${COLLATERAL_VERSION}/tcb?fmspc=${FMSPC_HEX}&tcbEvaluationDataNumber=${TCB_EVAL}" >"$outfile" && \
      jq -e '.tcbInfo and .signature' "$outfile" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$NETWORK_RETRY_DELAY"
  done
  echo "failed to fetch Intel PCS payload after retries" >&2
  return 1
}

payload_digest() {
  local infile="$1"
  sha256sum "$infile" | awk '{print $1}'
}

wait_for_new_payload() {
  local old_digest="$1"
  local outfile="$2"
  local attempt
  for attempt in $(seq 1 "$POLL_ATTEMPTS"); do
    sleep "$POLL_INTERVAL_SECONDS"
    fetch_payload "$outfile"
    local new_digest
    new_digest=$(payload_digest "$outfile")
    if [[ "$new_digest" != "$old_digest" ]]; then
      echo "$new_digest"
      return 0
    fi
  done
  echo "$old_digest"
  return 2
}

run_delta_update() {
  local logfile="$1"
  (
    cd "$PCCS_REPO"
    RPC_URL="$LOCAL_RPC_URL" \
    CHAIN_ID="$CHAIN_ID" \
    TCB_EVAL="$TCB_EVAL" \
    ATTESTER="$ATTESTER_ADDR" \
    UNLOCKED=true \
    OWNER="$OWNER_ADDR" \
    ./script/delta-update-existing-network.sh
  ) 2>&1 | tee "$logfile"
}

get_new_dao() {
  jq -r ".AutomataFmspcTcbDaoVersionedV2_tcbeval_${TCB_EVAL}" "$PCCS_REPO/deployment/$CHAIN_ID.json"
}

get_old_dao() {
  jq -r ".AutomataFmspcTcbDaoVersioned_tcbeval_${TCB_EVAL}" "$PCCS_REPO/deployment/$CHAIN_ID.json"
}

run_async_upsert() {
  local dao="$1"
  local batch="$2"
  local payload_file="$3"
  local logfile="$4"

  (
    cd "$QPL_REPO"
    export QPL_FALLBACK_GAS_LIMIT
    export QPL_ASYNC_PARSE_BATCH_SIZE="$batch"
    cargo run -- \
      --function upsert_tcb_fmspc_async \
      --private_key "$ATTESTER_PRIVATE_KEY" \
      --rpc_url "$LOCAL_RPC_URL" \
      --chain_id "$CHAIN_ID" \
      --gas_price "$QPL_GAS_PRICE" \
      --collateral_version "$COLLATERAL_VERSION" \
      --fmspc "$FMSPC_HEX" \
      --fmspc_tcb_dao_contract_addr "$dao" \
      --tcb_info_json_file "$payload_file"
  ) 2>&1 | tee "$logfile"
}

grant_legacy_attester_role() {
  local dao="$1"
  cast send "$dao" "grantRoles(address,uint256)" "$ATTESTER_ADDR" 1 \
    --rpc-url "$LOCAL_RPC_URL" \
    --unlocked \
    --from "$OWNER_ADDR" >/dev/null
}

run_legacy_sync_upsert() {
  local dao="$1"
  local payload_file="$2"
  local logfile="$3"
  local tcb_info_json
  local signature_hex
  tcb_info_json=$(jq -c '.tcbInfo' "$payload_file")
  signature_hex="0x$(jq -r '.signature' "$payload_file")"
  (
    cd "$PCCS_REPO"
    LEGACY_FMSPC_DAO="$dao" \
    LEGACY_TCB_INFO_JSON="$tcb_info_json" \
    LEGACY_TCB_INFO_SIGNATURE="$signature_hex" \
    forge script script/bench/LegacyFmspcSyncUpsert.s.sol:LegacyFmspcSyncUpsert \
      --rpc-url "$LOCAL_RPC_URL" \
      --private-key "$ATTESTER_PRIVATE_KEY" \
      --broadcast --skip-simulation -vv
  ) 2>&1 | tee "$logfile"
}

run_verify_send() {
  local logfile="$1"
  local tx_hash
  tx_hash=$(cast send 0xB8621Da79b42A62E576408995155D48E9f856489 \
    "verifyAndAttestOnChain(bytes,uint32)(bool,bytes)" \
    "$QUOTE_HEX" "$TCB_EVAL" \
    --rpc-url "$LOCAL_RPC_URL" \
    --private-key "$ATTESTER_PRIVATE_KEY" \
    --json | jq -r '.transactionHash // .hash')
  cast receipt "$tx_hash" --rpc-url "$LOCAL_RPC_URL" | tee "$logfile" >/dev/null
}

emit_deploy_summary() {
  local outfile="$1"
  jq -n \
    --arg helper_hash "$(jq -r '.receipts[0].transactionHash' "$PCCS_REPO/broadcast/DeployHelpers.s.sol/$CHAIN_ID/deployFmspcTcbHelperV2-latest.json")" \
    --argjson helper_gas "$(cast to-dec "$(jq -r '.receipts[0].gasUsed' "$PCCS_REPO/broadcast/DeployHelpers.s.sol/$CHAIN_ID/deployFmspcTcbHelperV2-latest.json")")" \
    --arg storage_hash "$(jq -r '.receipts[0].transactionHash' "$PCCS_REPO/broadcast/DeployAutomataVersioned.s.sol/$CHAIN_ID/deployStorageV2-latest.json")" \
    --argjson storage_gas "$(cast to-dec "$(jq -r '.receipts[0].gasUsed' "$PCCS_REPO/broadcast/DeployAutomataVersioned.s.sol/$CHAIN_ID/deployStorageV2-latest.json")")" \
    --arg old_grant_hash "$(jq -r '.receipts[1].transactionHash' "$PCCS_REPO/broadcast/DeployAutomataVersioned.s.sol/$CHAIN_ID/deployStorageV2-latest.json")" \
    --argjson old_grant_gas "$(cast to-dec "$(jq -r '.receipts[1].gasUsed' "$PCCS_REPO/broadcast/DeployAutomataVersioned.s.sol/$CHAIN_ID/deployStorageV2-latest.json")")" \
    --arg dao_hash "$(jq -r '.receipts[0].transactionHash' "$PCCS_REPO/broadcast/DeployAutomataVersioned.s.sol/$CHAIN_ID/deployFmspcTcbDaoVersionedV2-latest.json")" \
    --argjson dao_gas "$(cast to-dec "$(jq -r '.receipts[0].gasUsed' "$PCCS_REPO/broadcast/DeployAutomataVersioned.s.sol/$CHAIN_ID/deployFmspcTcbDaoVersionedV2-latest.json")")" \
    --arg storage_v2_grant_hash "$(jq -r '.receipts[0].transactionHash' "$PCCS_REPO/broadcast/ConfigAutomataDao.s.sol/$CHAIN_ID/grantDaoV2-latest.json")" \
    --argjson storage_v2_grant_gas "$(cast to-dec "$(jq -r '.receipts[0].gasUsed' "$PCCS_REPO/broadcast/ConfigAutomataDao.s.sol/$CHAIN_ID/grantDaoV2-latest.json")")" \
    --arg attester_role_hash "$(jq -r '.receipts[0].transactionHash' "$PCCS_REPO/broadcast/ConfigAutomataDaoVersioned.s.sol/$CHAIN_ID/configureFmspcTcbDaoVersionedV2Roles-latest.json")" \
    --argjson attester_role_gas "$(cast to-dec "$(jq -r '.receipts[0].gasUsed' "$PCCS_REPO/broadcast/ConfigAutomataDaoVersioned.s.sol/$CHAIN_ID/configureFmspcTcbDaoVersionedV2Roles-latest.json")")" \
    --arg router_qe_hash "$(jq -r '.receipts[0].transactionHash' "$DCAP_REPO/evm/broadcast/DeployRouter.s.sol/$CHAIN_ID/updateVersionedDaoConfig-latest.json")" \
    --argjson router_qe_gas "$(cast to-dec "$(jq -r '.receipts[0].gasUsed' "$DCAP_REPO/evm/broadcast/DeployRouter.s.sol/$CHAIN_ID/updateVersionedDaoConfig-latest.json")")" \
    --arg router_fmspc_hash "$(jq -r '.receipts[1].transactionHash' "$DCAP_REPO/evm/broadcast/DeployRouter.s.sol/$CHAIN_ID/updateVersionedDaoConfig-latest.json")" \
    --argjson router_fmspc_gas "$(cast to-dec "$(jq -r '.receipts[1].gasUsed' "$DCAP_REPO/evm/broadcast/DeployRouter.s.sol/$CHAIN_ID/updateVersionedDaoConfig-latest.json")")" \
    '[
      {label:"deploy_helper_v2", success:true, tx_hash:$helper_hash, gas:$helper_gas},
      {label:"deploy_storage_v2", success:true, tx_hash:$storage_hash, gas:$storage_gas},
      {label:"grant_old_storage_to_storage_v2", success:true, tx_hash:$old_grant_hash, gas:$old_grant_gas},
      {label:"deploy_fmspc_dao_v2", success:true, tx_hash:$dao_hash, gas:$dao_gas},
      {label:"grant_storage_v2_to_new_dao", success:true, tx_hash:$storage_v2_grant_hash, gas:$storage_v2_grant_gas},
      {label:"grant_v2_attester_role", success:true, tx_hash:$attester_role_hash, gas:$attester_role_gas},
      {label:"router_set_qe_dao", success:true, tx_hash:$router_qe_hash, gas:$router_qe_gas},
      {label:"router_set_fmspc_dao", success:true, tx_hash:$router_fmspc_hash, gas:$router_fmspc_gas}
    ]' >"$outfile"
}

append_router_auth_summary() {
  local source_log="$1"
  local outfile="$2"
  local old_hash old_gas v2_hash v2_gas
  old_hash=$(awk '
    /Granting PCCSRouter authorization to call PCCS Storage\.\.\./ {seen=1; next}
    seen && /^transactionHash[[:space:]]/ {print $2; exit}
  ' "$source_log")
  old_gas=$(awk '
    /Granting PCCSRouter authorization to call PCCS Storage\.\.\./ {seen=1; next}
    seen && /^gasUsed[[:space:]]/ {print $2; exit}
  ' "$source_log")
  v2_hash=$(awk '
    /Granting PCCSRouter authorization to call PCCS Storage V2\.\.\./ {seen=1; next}
    seen && /^transactionHash[[:space:]]/ {print $2; exit}
  ' "$source_log")
  v2_gas=$(awk '
    /Granting PCCSRouter authorization to call PCCS Storage V2\.\.\./ {seen=1; next}
    seen && /^gasUsed[[:space:]]/ {print $2; exit}
  ' "$source_log")
  jq \
    --arg old_hash "$old_hash" \
    --argjson old_gas "$old_gas" \
    --arg v2_hash "$v2_hash" \
    --argjson v2_gas "$v2_gas" \
    '. += [
      {label:"router_auth_old_storage", success:true, tx_hash:$old_hash, gas:$old_gas},
      {label:"router_auth_storage_v2", success:true, tx_hash:$v2_hash, gas:$v2_gas}
    ]' "$outfile" >"$outfile.tmp" && mv "$outfile.tmp" "$outfile"
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

parse_verify_receipt() {
  local logfile="$1"
  local outfile="$2"
  local tx_hash gas status
  tx_hash=$(awk '/^transactionHash[[:space:]]/ {print $2; exit}' "$logfile")
  gas=$(awk '/^gasUsed[[:space:]]/ {print $2; exit}' "$logfile")
  status=$(awk '/^status[[:space:]]/ {print $2; exit}' "$logfile")
  jq -n --arg tx_hash "$tx_hash" --argjson gas "$gas" --arg status "$status" \
    '[{label:"verify_and_attest_on_chain", success:($status=="1"), tx_hash:$tx_hash, gas:$gas}]' >"$outfile"
}

parse_legacy_sync_log() {
  local logfile="$1"
  local outfile="$2"
  local tx_hash gas status
  tx_hash=$(jq -r '.receipts[0].transactionHash' "$PCCS_REPO/broadcast/LegacyFmspcSyncUpsert.s.sol/$CHAIN_ID/run-latest.json")
  gas=$(cast to-dec "$(jq -r '.receipts[0].gasUsed' "$PCCS_REPO/broadcast/LegacyFmspcSyncUpsert.s.sol/$CHAIN_ID/run-latest.json")")
  status=$(jq -r '.receipts[0].status' "$PCCS_REPO/broadcast/LegacyFmspcSyncUpsert.s.sol/$CHAIN_ID/run-latest.json")
  jq -n --arg tx_hash "$tx_hash" --argjson gas "$gas" --arg status "$status" \
    '[{label:"legacy_sync_upsert", success:($status=="0x1"), tx_hash:$tx_hash, gas:$gas}]' >"$outfile"
}

sum_gas() {
  jq '[.[].gas] | add // 0' "$1"
}

run_batch_e2e() {
  local batch="$1"
  local payload_file="$2"
  local run_dir="$3"
  mkdir -p "$run_dir"
  start_fork
  run_delta_update "$run_dir/delta.log"
  local dao
  dao=$(get_new_dao)
  run_async_upsert "$dao" "$batch" "$payload_file" "$run_dir/upsert.log"
  run_verify_send "$run_dir/verify.log"
  emit_deploy_summary "$run_dir/deploy.json"
  append_router_auth_summary "$run_dir/delta.log" "$run_dir/deploy.json"
  parse_async_log "$run_dir/upsert.log" "$run_dir/upsert.json"
  parse_verify_receipt "$run_dir/verify.log" "$run_dir/verify.json"
  jq -n \
    --argjson deploy "$(cat "$run_dir/deploy.json")" \
    --argjson upsert "$(cat "$run_dir/upsert.json")" \
    --argjson verify "$(cat "$run_dir/verify.json")" \
    --argjson deploy_total "$(sum_gas "$run_dir/deploy.json")" \
    --argjson upsert_total "$(sum_gas "$run_dir/upsert.json")" \
    --argjson verify_total "$(sum_gas "$run_dir/verify.json")" \
    '{deploy:$deploy, upsert:$upsert, verify:$verify, totals:{deploy:$deploy_total, upsert:$upsert_total, verify:$verify_total, overall:($deploy_total + $upsert_total + $verify_total)}}' \
    >"$run_dir/summary.json"
  stop_fork
}

run_repeat_batch1() {
  local run_dir="$RUN_ROOT/repeat-batch1"
  mkdir -p "$run_dir"
  local payload1="$run_dir/payload-first.json"
  local payload2="$run_dir/payload-second.json"
  fetch_payload "$payload1"
  local digest1
  digest1=$(payload_digest "$payload1")

  start_fork
  run_delta_update "$run_dir/delta.log"
  local dao
  dao=$(get_new_dao)

  run_async_upsert "$dao" 1 "$payload1" "$run_dir/upsert-first.log"
  run_verify_send "$run_dir/verify-first.log"

  local digest2
  local payload_changed=true
  if digest2=$(wait_for_new_payload "$digest1" "$payload2"); then
    :
  else
    local wait_status=$?
    if [[ "$wait_status" -eq 2 ]]; then
      payload_changed=false
    else
      return "$wait_status"
    fi
  fi

  run_async_upsert "$dao" 1 "$payload2" "$run_dir/upsert-second.log"
  run_verify_send "$run_dir/verify-second.log"

  emit_deploy_summary "$run_dir/deploy.json"
  append_router_auth_summary "$run_dir/delta.log" "$run_dir/deploy.json"
  parse_async_log "$run_dir/upsert-first.log" "$run_dir/upsert-first.json"
  parse_verify_receipt "$run_dir/verify-first.log" "$run_dir/verify-first.json"
  parse_async_log "$run_dir/upsert-second.log" "$run_dir/upsert-second.json"
  parse_verify_receipt "$run_dir/verify-second.log" "$run_dir/verify-second.json"

  jq -n \
    --arg payload1_digest "$digest1" \
    --arg payload2_digest "$digest2" \
    --argjson payload_changed "$payload_changed" \
    --argjson deploy "$(cat "$run_dir/deploy.json")" \
    --argjson first_upsert "$(cat "$run_dir/upsert-first.json")" \
    --argjson first_verify "$(cat "$run_dir/verify-first.json")" \
    --argjson second_upsert "$(cat "$run_dir/upsert-second.json")" \
    --argjson second_verify "$(cat "$run_dir/verify-second.json")" \
    --argjson deploy_total "$(sum_gas "$run_dir/deploy.json")" \
    --argjson first_upsert_total "$(sum_gas "$run_dir/upsert-first.json")" \
    --argjson first_verify_total "$(sum_gas "$run_dir/verify-first.json")" \
    --argjson second_upsert_total "$(sum_gas "$run_dir/upsert-second.json")" \
    --argjson second_verify_total "$(sum_gas "$run_dir/verify-second.json")" \
    '{
      payload_digests:{first:$payload1_digest, second:$payload2_digest, changed:$payload_changed},
      deploy:$deploy,
      first:{upsert:$first_upsert, verify:$first_verify, totals:{upsert:$first_upsert_total, verify:$first_verify_total, overall:($first_upsert_total + $first_verify_total)}},
      second:{upsert:$second_upsert, verify:$second_verify, totals:{upsert:$second_upsert_total, verify:$second_verify_total, overall:($second_upsert_total + $second_verify_total)}},
      deploy_total:$deploy_total
    }' >"$run_dir/summary.json"
  stop_fork
}

run_compare_batches() {
  local run_dir="$RUN_ROOT/compare-batches"
  mkdir -p "$run_dir"
  local payload="$run_dir/payload.json"
  fetch_payload "$payload"

  local legacy_dir="$run_dir/legacy"
  mkdir -p "$legacy_dir"
  start_fork
  local old_dao
  old_dao=$(get_old_dao)
  grant_legacy_attester_role "$old_dao"
  run_legacy_sync_upsert "$old_dao" "$payload" "$legacy_dir/upsert.log"
  run_verify_send "$legacy_dir/verify.log"
  parse_legacy_sync_log "$legacy_dir/upsert.log" "$legacy_dir/upsert.json"
  parse_verify_receipt "$legacy_dir/verify.log" "$legacy_dir/verify.json"
  jq -n \
    --argjson upsert "$(cat "$legacy_dir/upsert.json")" \
    --argjson verify "$(cat "$legacy_dir/verify.json")" \
    --argjson upsert_total "$(sum_gas "$legacy_dir/upsert.json")" \
    --argjson verify_total "$(sum_gas "$legacy_dir/verify.json")" \
    '{upsert:$upsert, verify:$verify, totals:{upsert:$upsert_total, verify:$verify_total, overall:($upsert_total + $verify_total)}}' \
    >"$legacy_dir/summary.json"
  stop_fork

  run_batch_e2e 1 "$payload" "$run_dir/batch1"
  run_batch_e2e 3 "$payload" "$run_dir/batch3"

  if run_batch_e2e 999 "$payload" "$run_dir/batch999"; then
    :
  else
    echo "batch999 run failed" >"$run_dir/batch999/error.txt"
  fi

  jq -n \
    --argjson legacy "$(cat "$legacy_dir/summary.json")" \
    --argjson batch1 "$(cat "$run_dir/batch1/summary.json")" \
    --argjson batch3 "$(cat "$run_dir/batch3/summary.json")" \
    --argjson batch999 "$(cat "$run_dir/batch999/summary.json" 2>/dev/null || echo 'null')" \
    '{
      legacy_sync:$legacy,
      batch1:$batch1,
      batch3:$batch3,
      batch999:$batch999,
      comparison:{
        upsert_extra_vs_legacy:{
          batch1:($batch1.totals.upsert - $legacy.totals.upsert),
          batch3:($batch3.totals.upsert - $legacy.totals.upsert),
          batch999: (if $batch999 == null then null else ($batch999.totals.upsert - $legacy.totals.upsert) end)
        }
      }
    }' >"$run_dir/summary.json"
}

run_single_batch() {
  local run_dir="$RUN_ROOT/single-batch"
  local payload="$run_dir/payload.json"
  mkdir -p "$run_dir"

  if [[ -n "$PAYLOAD_FILE" ]]; then
    cp "$PAYLOAD_FILE" "$payload"
  else
    fetch_payload "$payload"
  fi

  run_batch_e2e "$BENCH_BATCH" "$payload" "$run_dir"
}

case "$MODE" in
  repeat-batch1) run_repeat_batch1 ;;
  compare-batches) run_compare_batches ;;
  single-batch) run_single_batch ;;
  *) echo "unknown mode: $MODE" >&2; exit 1 ;;
esac

echo "Results written to: $RUN_ROOT/$MODE"
