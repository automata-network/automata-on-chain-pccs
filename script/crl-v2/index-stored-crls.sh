#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

init_deployment_context

DEPLOYMENT_FILE="$PCCS_ROOT/deployment/$CHAIN_ID.json"
PCS_DAO_ADDRESS="$(json_address "$DEPLOYMENT_FILE" AutomataPcsDaoV2)"
CRL_HELPER_ADDRESS="$(json_address "$DEPLOYMENT_FILE" X509CRLHelperV2)"
INDEX_BATCH_SIZE="${INDEX_BATCH_SIZE:-50}"
MAX_INDEX_BATCHES="${MAX_INDEX_BATCHES:-64}"
CA_LIST="${CA_LIST:-root processor platform}"

[[ "$INDEX_BATCH_SIZE" =~ ^[1-9][0-9]*$ ]] || die "INDEX_BATCH_SIZE must be a positive integer"
[[ "$MAX_INDEX_BATCHES" =~ ^[1-9][0-9]*$ ]] || die "MAX_INDEX_BATCHES must be a positive integer"
require_contract_code AutomataPcsDaoV2 "$PCS_DAO_ADDRESS"
require_contract_code X509CRLHelperV2 "$CRL_HELPER_ADDRESS"

CAST_SEND_ARGS=(
    --rpc-url "$RPC_URL"
    "${CAST_WALLET_ARGS[@]}"
)
if [[ "${LEGACY:-false}" == "true" ]]; then
    CAST_SEND_ARGS+=(--legacy)
fi
if [[ -n "${CONFIRMATIONS:-}" ]]; then
    CAST_SEND_ARGS+=(--confirmations "$CONFIRMATIONS")
fi
if [[ -n "${INDEX_GAS_LIMIT:-}" ]]; then
    CAST_SEND_ARGS+=(--gas-limit "$INDEX_GAS_LIMIT")
fi

for ca_name in $CA_LIST; do
    ca="$(ca_number "$ca_name")"
    der_hash="$(stored_crl_hash "$PCS_DAO_ADDRESS" "$ca")"
    info "Indexing ${ca_name^^} CRL ($der_hash) with batches of $INDEX_BATCH_SIZE"

    complete="$(
        cast call "$CRL_HELPER_ADDRESS" \
            'indexedCrls(bytes32)(bool)' "$der_hash" \
            --rpc-url "$RPC_URL"
    )"
    if [[ "$complete" == "true" ]]; then
        success "${ca_name^^} CRL is already fully indexed"
        continue
    fi

    for ((batch = 1; batch <= MAX_INDEX_BATCHES; batch++)); do
        info "${ca_name^^}: submitting batch $batch"
        cast send "$PCS_DAO_ADDRESS" \
            'indexStoredCrlBatch(uint8,bytes32,uint256)' \
            "$ca" "$der_hash" "$INDEX_BATCH_SIZE" \
            "${CAST_SEND_ARGS[@]}"

        complete="$(
            cast call "$CRL_HELPER_ADDRESS" \
                'indexedCrls(bytes32)(bool)' "$der_hash" \
                --rpc-url "$RPC_URL"
        )"
        if [[ "$complete" == "true" ]]; then
            progress="$(
                cast call "$CRL_HELPER_ADDRESS" \
                    'getIndexProgress(bytes32)(uint256,uint256,uint256,bool)' "$der_hash" \
                    --rpc-url "$RPC_URL"
            )"
            success "${ca_name^^} CRL indexing complete: $progress"
            break
        fi
    done

    [[ "$complete" == "true" ]] \
        || die "${ca_name^^} CRL did not finish after $MAX_INDEX_BATCHES batches; re-run to continue"
done

success "All requested stored CRLs are fully indexed"
