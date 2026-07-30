#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

init_deployment_context

[[ "${CONFIRM_LEGACY_PCS_REVOKE:-false}" == "true" ]] \
    || die "Set CONFIRM_LEGACY_PCS_REVOKE=true after completing the dependent-DAO migration preflight"
[[ -n "${ACTIVE_DEPENDENT_DAOS:-}" ]] \
    || die "ACTIVE_DEPENDENT_DAOS must list every Router-reachable TCB/identity DAO"

DEPLOYMENT_FILE="$PCCS_ROOT/deployment/$CHAIN_ID.json"
STORAGE_ADDRESS="$(json_address "$DEPLOYMENT_FILE" AutomataDaoStorage)"
LEGACY_PCS_DAO_ADDRESS="$(json_address "$DEPLOYMENT_FILE" AutomataPcsDao)"
PCS_DAO_ADDRESS="$(json_address "$DEPLOYMENT_FILE" AutomataPcsDaoV2)"

require_contract_code AutomataDaoStorage "$STORAGE_ADDRESS"
require_contract_code AutomataPcsDao "$LEGACY_PCS_DAO_ADDRESS"
require_contract_code AutomataPcsDaoV2 "$PCS_DAO_ADDRESS"
require_storage_writer AutomataPcsDaoV2 "$STORAGE_ADDRESS" "$PCS_DAO_ADDRESS"

# revokeDao removes both write and read authorization. Refuse revocation until
# every caller-declared active dependent DAO resolves the new PCS DAO. The
# cross-repository rollout constructs this manifest from the Router-selected
# TCB evaluation, Enclave Identity, and FMSPC DAOs after retiring eval 19.
for dao_address in $ACTIVE_DEPENDENT_DAOS; do
    require_contract_code "active dependent DAO" "$dao_address"
    active_pcs="$(cast call "$dao_address" 'Pcs()(address)' --rpc-url "$RPC_URL")" \
        || die "Active dependent DAO $dao_address does not expose Pcs()"
    assert_address_eq "active dependent DAO $dao_address PCS binding" "$active_pcs" "$PCS_DAO_ADDRESS"
done

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

info "Revoking legacy AutomataPcsDao storage authorization (idempotent)"
cast send "$STORAGE_ADDRESS" \
    'revokeDao(address)' "$LEGACY_PCS_DAO_ADDRESS" \
    "${CAST_SEND_ARGS[@]}"

require_storage_writer_revoked AutomataPcsDao "$STORAGE_ADDRESS" "$LEGACY_PCS_DAO_ADDRESS"
success "Legacy AutomataPcsDao can no longer read or write AutomataDaoStorage"
