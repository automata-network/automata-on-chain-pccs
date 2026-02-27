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

select_all_section=0
select_all_network=0
select_all_tcb=0

while IFS= read -r line || [ -n "$line" ]; do
    # Top-level section heading: # Mainnet or # Testnet
    if [[ "$line" =~ ^#\ (Mainnet|Testnet)[[:space:]]*$ ]]; then
        select_all_section=0
        select_all_network=0
        select_all_tcb=0
        continue
    fi

    # Network heading: ## Network Name (ChainID):
    if [[ "$line" =~ ^##\ (.+)\ \(([0-9]+)\):[[:space:]]*$ ]]; then
        current_network="${BASH_REMATCH[1]}"
        current_chain_id="${BASH_REMATCH[2]}"
        current_tcb=""
        select_all_network=0
        select_all_tcb=0
        continue
    fi

    # TCB heading: ### TCB Evaluation Data Number N
    if [[ "$line" =~ ^###\ TCB\ Evaluation\ Data\ Number\ ([0-9]+)[[:space:]]*$ ]]; then
        current_tcb="${BASH_REMATCH[1]}"
        select_all_tcb=0
        continue
    fi

    # Select all - TCB level (check first, most specific)
    if [[ "$line" =~ ^-\ \[([xX])\]\ Select\ all\ TCB\ [0-9]+[[:space:]]*$ ]]; then
        select_all_tcb=1
        continue
    fi

    # Select all - section level (Mainnet/Testnet)
    if [[ "$line" =~ ^-\ \[([xX])\]\ Select\ all\ (Mainnet|Testnet)[[:space:]]*$ ]]; then
        select_all_section=1
        continue
    fi

    # Select all - network level
    if [[ "$line" =~ ^-\ \[([xX])\]\ Select\ all\ .+[[:space:]]*$ ]]; then
        select_all_network=1
        continue
    fi

    # Contract checkbox (checked or unchecked)
    if [[ "$line" =~ ^-\ \[([xX\ ])\]\ ([A-Za-z0-9_.-]+\.sol)[[:space:]]*$ ]]; then
        check_mark="${BASH_REMATCH[1]}"
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

        individually_checked=0
        if [[ "$check_mark" =~ [xX] ]]; then
            individually_checked=1
        fi

        if [ "$individually_checked" -eq 1 ] || [ "$select_all_section" -eq 1 ] || [ "$select_all_network" -eq 1 ] || [ "$select_all_tcb" -eq 1 ]; then
            jq -cn \
                --arg chain_id "$current_chain_id" \
                --arg network "$current_network" \
                --argjson tcb "$current_tcb" \
                --arg contract "$contract_name" \
                '{chain_id: $chain_id, network: $network, tcb: $tcb, contract: $contract}' >> "$tmp_file"
        fi
    fi
done < "$ISSUE_BODY_FILE"

if [ -s "$tmp_file" ]; then
    jq -s 'unique_by(.chain_id, .tcb, .contract) | sort_by((.chain_id|tonumber), .tcb, .contract)' "$tmp_file"
else
    echo '[]'
fi
