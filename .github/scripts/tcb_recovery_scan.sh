#!/usr/bin/env bash
set -euo pipefail

INTEL_API_URL="${INTEL_API_URL:-https://api.trustedservices.intel.com/tdx/certification/v4/tcbevaluationdatanumbers}"
DEPLOYMENT_DIR="${DEPLOYMENT_DIR:-deployment}"
OUTPUT_PATH="${1:-}"

network_name() {
    case "$1" in
        1) echo "Ethereum" ;;
        10) echo "Optimism" ;;
        56) echo "BNB Smart Chain" ;;
        97) echo "BNB Testnet" ;;
        130) echo "Unichain" ;;
        137) echo "Polygon" ;;
        480) echo "World Chain" ;;
        998) echo "HyperEVM" ;;
        999) echo "HyperEVM Testnet" ;;
        1301) echo "Unichain Sepolia" ;;
        4326) echo "Chain 4326" ;;
        6343) echo "Chain 6343" ;;
        42429) echo "Chain 42429" ;;
        43113) echo "Avalanche Fuji" ;;
        43114) echo "Avalanche" ;;
        65536) echo "ATA Sepolia" ;;
        80002) echo "Polygon Amoy" ;;
        8453) echo "Base" ;;
        84532) echo "Base Sepolia" ;;
        11155111) echo "Sepolia" ;;
        11155420) echo "OP Sepolia" ;;
        42161) echo "Arbitrum One" ;;
        421614) echo "Arbitrum Sepolia" ;;
        560048) echo "Hoodi Testnet" ;;
        1398243) echo "ATA" ;;
        4801) echo "World Sepolia" ;;
        *) echo "Chain $1" ;;
    esac
}

date_add_one_year_epoch() {
    input_date="$1"

    if date -u -d "$input_date + 1 year" +%s >/dev/null 2>&1; then
        date -u -d "$input_date + 1 year" +%s
        return 0
    fi

    if command -v gdate >/dev/null 2>&1; then
        if gdate -u -d "$input_date + 1 year" +%s >/dev/null 2>&1; then
            gdate -u -d "$input_date + 1 year" +%s
            return 0
        fi
    fi

    # macOS / BSD date fallback for common ISO8601 formats.
    if date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$input_date" -v+1y +%s >/dev/null 2>&1; then
        date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$input_date" -v+1y +%s
        return 0
    fi

    if date -j -u -f "%Y-%m-%d" "$input_date" -v+1y +%s >/dev/null 2>&1; then
        date -j -u -f "%Y-%m-%d" "$input_date" -v+1y +%s
        return 0
    fi

    return 1
}

if [ ! -d "$DEPLOYMENT_DIR" ]; then
    echo "deployment directory not found: $DEPLOYMENT_DIR" >&2
    exit 1
fi

raw_file="$(mktemp)"
entries_file="$(mktemp)"
missing_file="$(mktemp)"

curl -fsSL "$INTEL_API_URL" -o "$raw_file"

jq -c '
  def data_list:
    if type == "array" then .
    elif (.tcbEvaluationDataNumberDTOs? | type) == "array" then .tcbEvaluationDataNumberDTOs
    elif (.tcbEvaluationDataNumbers? | type) == "array" then .tcbEvaluationDataNumbers
    elif (.tcbEvaluationDataNumbers?.tcbEvalNumbers? | type) == "array" then .tcbEvaluationDataNumbers.tcbEvalNumbers
    elif (.tcbEvaluationDataNumbers?.tcbEvaluationDataNumbers? | type) == "array" then .tcbEvaluationDataNumbers.tcbEvaluationDataNumbers
    elif (.data? | type) == "array" then .data
    elif (.items? | type) == "array" then .items
    else []
    end;

  data_list
  | map({
      number: (.tcbEvaluationDataNumber // .tcbEvalDataNumber // .number // .id // null),
      recovery: (.tcbRecoveryEventDate // .recoveryEventDate // .recoveryDate // null)
    })
  | map(select(.number != null and .recovery != null))
' "$raw_file" > "$entries_file"

entry_count="$(jq 'length' "$entries_file")"
if [ "$entry_count" -eq 0 ]; then
    echo "could not parse any tcb evaluation data numbers from Intel API response" >&2
    exit 1
fi

early="$(jq -r 'map(.number | tonumber) | max' "$entries_file")"
now_epoch="$(date -u +%s)"
standard=""

while IFS= read -r row; do
    number="$(jq -r '.number | tonumber' <<<"$row")"
    recovery_raw="$(jq -r '.recovery' <<<"$row")"
    recovery_plus_1y_epoch="$(date_add_one_year_epoch "$recovery_raw" || true)"

    if [ -n "$recovery_plus_1y_epoch" ] && [ "$recovery_plus_1y_epoch" -le "$now_epoch" ]; then
        if [ -z "$standard" ] || [ "$number" -gt "$standard" ]; then
            standard="$number"
        fi
    fi
done < <(jq -c '.[]' "$entries_file")

targets=("$early")
if [ -n "$standard" ] && [ "$standard" != "$early" ]; then
    targets+=("$standard")
fi

for deployment_file in "$DEPLOYMENT_DIR"/*.json; do
    [ -f "$deployment_file" ] || continue

    chain_id="$(basename "$deployment_file" .json)"
    network="$(network_name "$chain_id")"

    for eval_number in "${targets[@]}"; do
        enclave_key="AutomataEnclaveIdentityDaoVersioned_tcbeval_${eval_number}"
        fmspc_key="AutomataFmspcTcbDaoVersioned_tcbeval_${eval_number}"

        if ! jq -e --arg key "$enclave_key" 'has($key) and .[$key] != null and .[$key] != ""' "$deployment_file" >/dev/null; then
            jq -cn \
                --arg chain_id "$chain_id" \
                --arg network "$network" \
                --argjson tcb "$eval_number" \
                --arg contract "AutomataEnclaveIdentityDaoVersioned.sol" \
                '{chain_id: $chain_id, network: $network, tcb: $tcb, contract: $contract}' >> "$missing_file"
        fi

        if ! jq -e --arg key "$fmspc_key" 'has($key) and .[$key] != null and .[$key] != ""' "$deployment_file" >/dev/null; then
            jq -cn \
                --arg chain_id "$chain_id" \
                --arg network "$network" \
                --argjson tcb "$eval_number" \
                --arg contract "AutomataFmspcTcbDaoVersioned.sol" \
                '{chain_id: $chain_id, network: $network, tcb: $tcb, contract: $contract}' >> "$missing_file"
        fi
    done
done

if [ -s "$missing_file" ]; then
    missing_json="$(jq -s 'sort_by((.chain_id|tonumber), .tcb, .contract)' "$missing_file")"
else
    missing_json='[]'
fi

missing_count="$(jq 'length' <<<"$missing_json")"
generated_at="$(date -u '+%Y-%m-%d, %H:%M UTC')"
issue_title="Missing Deployment Found, ${generated_at}"

if [ -n "$standard" ]; then
    target_text="early=${early}, standard=${standard}"
else
    target_text="early=${early}, standard=unavailable"
fi

issue_body=$'# Intel TCB Recovery Deployment Check\n\n'
issue_body+="Detected missing deployments for target TCB evaluation data numbers (${target_text}).\n"
issue_body+="Check the boxes for contracts approved for deployment, then close this issue to trigger the deployment workflow.\n\n"
issue_body+="<!-- tcb-recovery-monitor: early=${early} standard=${standard:-none} generated_at=${generated_at} -->\n\n"

if [ "$missing_count" -eq 0 ]; then
    issue_body+="No missing deployments detected.\n"
else
    current_chain=""
    current_tcb=""

    while IFS= read -r row; do
        row_chain="$(jq -r '.chain_id' <<<"$row")"
        row_network="$(jq -r '.network' <<<"$row")"
        row_tcb="$(jq -r '.tcb' <<<"$row")"
        row_contract="$(jq -r '.contract' <<<"$row")"

        if [ "$row_chain" != "$current_chain" ]; then
            if [ -n "$current_chain" ]; then
                issue_body+="\n"
            fi
            issue_body+="# ${row_network} (${row_chain}):\n\n"
            current_chain="$row_chain"
            current_tcb=""
        fi

        if [ "$row_tcb" != "$current_tcb" ]; then
            issue_body+="## TCB Evaluation Data Number ${row_tcb}\n"
            current_tcb="$row_tcb"
        fi

        issue_body+="- [ ] ${row_contract}\n"
    done < <(jq -c '.[]' <<<"$missing_json")
fi

if [ -n "$standard" ]; then
    standard_json="$standard"
else
    standard_json="null"
fi

result_json="$(jq -n \
    --argjson early "$early" \
    --argjson standard "$standard_json" \
    --arg issue_title "$issue_title" \
    --arg issue_body "$issue_body" \
    --argjson missing "$missing_json" \
    --arg generated_at "$generated_at" \
    '{
      early: $early,
      standard: $standard,
      issue_title: $issue_title,
      issue_body: $issue_body,
      missing: $missing,
      missing_count: ($missing | length),
      generated_at: $generated_at
    }')"

if [ -n "$OUTPUT_PATH" ]; then
    printf '%s\n' "$result_json" > "$OUTPUT_PATH"
else
    printf '%s\n' "$result_json"
fi
