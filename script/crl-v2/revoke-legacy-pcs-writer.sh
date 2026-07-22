#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

init_deployment_context

DEPLOYMENT_FILE="$PCCS_ROOT/deployment/$CHAIN_ID.json"
STORAGE_ADDRESS="$(json_address "$DEPLOYMENT_FILE" AutomataDaoStorage)"
LEGACY_PCS_DAO_ADDRESS="$(json_address "$DEPLOYMENT_FILE" AutomataPcsDao)"
PCS_DAO_ADDRESS="$(json_address "$DEPLOYMENT_FILE" AutomataPcsDaoV2)"

require_contract_code AutomataDaoStorage "$STORAGE_ADDRESS"
require_contract_code AutomataPcsDao "$LEGACY_PCS_DAO_ADDRESS"
require_contract_code AutomataPcsDaoV2 "$PCS_DAO_ADDRESS"
require_storage_writer AutomataPcsDaoV2 "$STORAGE_ADDRESS" "$PCS_DAO_ADDRESS"

STORAGE_OWNER="$(cast call "$STORAGE_ADDRESS" 'owner()(address)' --rpc-url "$RPC_URL")"
assert_address_eq "AutomataDaoStorage owner" "$STORAGE_OWNER" "$OWNER_ADDRESS"

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

if storage_writer_is_authorized "$STORAGE_ADDRESS" "$LEGACY_PCS_DAO_ADDRESS"; then
    info "Revoking legacy AutomataPcsDao storage authorization"
    cast send "$STORAGE_ADDRESS" \
        'revokeDao(address)' "$LEGACY_PCS_DAO_ADDRESS" \
        "${CAST_SEND_ARGS[@]}"
else
    info "Legacy AutomataPcsDao storage authorization is already revoked"
fi

require_storage_writer_revoked AutomataPcsDao "$STORAGE_ADDRESS" "$LEGACY_PCS_DAO_ADDRESS"
success "Legacy AutomataPcsDao can no longer read or write AutomataDaoStorage"
