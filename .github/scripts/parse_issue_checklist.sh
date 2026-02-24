#!/usr/bin/env bash
set -euo pipefail

ISSUE_BODY_FILE="${1:-}"
if [ -z "$ISSUE_BODY_FILE" ] || [ ! -f "$ISSUE_BODY_FILE" ]; then
    echo "usage: $0 <issue-body-file>" >&2
    exit 1
fi

tmp_file="$(mktemp)"
current_chain_id=""
current_network=""
current_tcb=""

while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^#\ (.+)\ \(([0-9]+)\):[[:space:]]*$ ]]; then
        current_network="${BASH_REMATCH[1]}"
        current_chain_id="${BASH_REMATCH[2]}"
        current_tcb=""
        continue
    fi

    if [[ "$line" =~ ^##\ TCB\ Evaluation\ Data\ Number\ ([0-9]+)[[:space:]]*$ ]]; then
        current_tcb="${BASH_REMATCH[1]}"
        continue
    fi

    if [[ "$line" =~ ^-\ \[([xX])\]\ ([A-Za-z0-9_.-]+\.sol)[[:space:]]*$ ]]; then
        contract_name="${BASH_REMATCH[2]}"

        case "$contract_name" in
            AutomataEnclaveIdentityDaoVersioned.sol|AutomataFmspcTcbDaoVersioned.sol)
                ;;
            *)
                continue
                ;;
        esac

        if [ -z "$current_chain_id" ] || [ -z "$current_tcb" ]; then
            continue
        fi

        jq -cn \
            --arg chain_id "$current_chain_id" \
            --arg network "$current_network" \
            --argjson tcb "$current_tcb" \
            --arg contract "$contract_name" \
            '{chain_id: $chain_id, network: $network, tcb: $tcb, contract: $contract}' >> "$tmp_file"
    fi
done < "$ISSUE_BODY_FILE"

if [ -s "$tmp_file" ]; then
    jq -s 'unique_by(.chain_id, .tcb, .contract) | sort_by((.chain_id|tonumber), .tcb, .contract)' "$tmp_file"
else
    echo '[]'
fi
