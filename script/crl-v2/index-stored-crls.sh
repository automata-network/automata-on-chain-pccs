#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

init_deployment_context

DEPLOYMENT_FILE="$PCCS_ROOT/deployment/$CHAIN_ID.json"
PCS_DAO_ADDRESS="$(json_address "$DEPLOYMENT_FILE" AutomataPcsDaoV2)"
CRL_HELPER_ADDRESS="$(json_address "$DEPLOYMENT_FILE" X509CRLHelperV2)"
CA_LIST="${CA_LIST:-root processor platform}"

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
    info "Atomically indexing stored ${ca_name^^} CRL ($der_hash)"

    complete="$(
        cast call "$CRL_HELPER_ADDRESS" \
            'indexedCrls(bytes32)(bool)' "$der_hash" \
            --rpc-url "$RPC_URL"
    )"
    if [[ "$complete" == "true" ]]; then
        success "${ca_name^^} CRL is already fully indexed"
        continue
    fi

    cast send "$PCS_DAO_ADDRESS" \
        'indexStoredCrl(uint8,bytes32)' \
        "$ca" "$der_hash" \
        "${CAST_SEND_ARGS[@]}"

    complete="$(
        cast call "$CRL_HELPER_ADDRESS" \
            'indexedCrls(bytes32)(bool)' "$der_hash" \
            --rpc-url "$RPC_URL"
    )"
    [[ "$complete" == "true" ]] \
        || die "${ca_name^^} CRL was not indexed by the migration transaction"
    success "${ca_name^^} CRL indexing complete"
done

success "All requested stored CRLs are fully indexed"
