#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

init_deployment_context
forge_broadcast_args

DEPLOYMENT_FILE="$PCCS_ROOT/deployment/$CHAIN_ID.json"
STORAGE_ADDRESS="$(json_address "$DEPLOYMENT_FILE" AutomataDaoStorage)"
PCK_HELPER_ADDRESS="$(json_address "$DEPLOYMENT_FILE" PCKHelper)"

require_contract_code AutomataDaoStorage "$STORAGE_ADDRESS"
require_contract_code PCKHelper "$PCK_HELPER_ADDRESS"

STORAGE_OWNER="$(cast call "$STORAGE_ADDRESS" 'owner()(address)' --rpc-url "$RPC_URL")"
assert_address_eq "AutomataDaoStorage owner" "$STORAGE_OWNER" "$OWNER_ADDRESS"

existing_contracts=0
deployed_contracts=0
for key in X509CRLHelperV2 PccsDependencyConfig AutomataPcsDaoV2 AutomataPckDaoV2; do
    if address="$(json_address_if_present "$DEPLOYMENT_FILE" "$key")"; then
        existing_contracts=$((existing_contracts + 1))
        if [[ "$(cast code "$address" --rpc-url "$RPC_URL")" != "0x" ]]; then
            deployed_contracts=$((deployed_contracts + 1))
        fi
    fi
done

resume_broadcast=false
if [[ "$deployed_contracts" -eq 4 ]]; then
    info "All four CRL V2 contracts already have code; validating bindings"
else
    if [[ "$existing_contracts" -ne 0 ]]; then
        [[ "${RESUME:-false}" == "true" ]] \
            || die "Partial CRL V2 deployment detected. Re-run with RESUME=true to resume the Foundry broadcast"
        resume_broadcast=true
    fi

    require_command forge
    info "Building automata-on-chain-pccs"
    (cd "$PCCS_ROOT" && forge build)

    command=(
        forge script script/automata/DeployCrlV2.s.sol:DeployCrlV2
        "${FORGE_BROADCAST_ARGS[@]}"
    )
    if [[ "$resume_broadcast" == "true" ]]; then
        command+=(--resume)
    fi

    info "Deploying X509CRLHelperV2, PccsDependencyConfig, AutomataPcsDaoV2, and AutomataPckDaoV2"
    (cd "$PCCS_ROOT" && OWNER="$OWNER_ADDRESS" "${command[@]}")
fi

CRL_HELPER_ADDRESS="$(json_address "$DEPLOYMENT_FILE" X509CRLHelperV2)"
DEPENDENCY_CONFIG_ADDRESS="$(json_address "$DEPLOYMENT_FILE" PccsDependencyConfig)"
PCS_DAO_ADDRESS="$(json_address "$DEPLOYMENT_FILE" AutomataPcsDaoV2)"
PCK_DAO_ADDRESS="$(json_address "$DEPLOYMENT_FILE" AutomataPckDaoV2)"

require_contract_code X509CRLHelperV2 "$CRL_HELPER_ADDRESS"
require_contract_code PccsDependencyConfig "$DEPENDENCY_CONFIG_ADDRESS"
require_contract_code AutomataPcsDaoV2 "$PCS_DAO_ADDRESS"
require_contract_code AutomataPckDaoV2 "$PCK_DAO_ADDRESS"

assert_address_eq \
    "X509CRLHelperV2 owner" \
    "$(cast call "$CRL_HELPER_ADDRESS" 'owner()(address)' --rpc-url "$RPC_URL")" \
    "$OWNER_ADDRESS"
assert_address_eq \
    "PccsDependencyConfig owner" \
    "$(cast call "$DEPENDENCY_CONFIG_ADDRESS" 'owner()(address)' --rpc-url "$RPC_URL")" \
    "$OWNER_ADDRESS"
assert_address_eq \
    "PccsDependencyConfig PCS DAO" \
    "$(cast call "$DEPENDENCY_CONFIG_ADDRESS" 'pcsDao()(address)' --rpc-url "$RPC_URL")" \
    "$PCS_DAO_ADDRESS"
assert_address_eq \
    "PccsDependencyConfig CRL helper" \
    "$(cast call "$DEPENDENCY_CONFIG_ADDRESS" 'crlHelper()(address)' --rpc-url "$RPC_URL")" \
    "$CRL_HELPER_ADDRESS"
[[ "$(cast call "$DEPENDENCY_CONFIG_ADDRESS" 'dependencyConfigState()(uint8)' --rpc-url "$RPC_URL")" == "1" ]] \
    || die "PccsDependencyConfig is not in Active state"
[[ "$(cast call "$DEPENDENCY_CONFIG_ADDRESS" 'pendingExecutableAt()(uint64)' --rpc-url "$RPC_URL")" == "0" ]] \
    || die "PccsDependencyConfig unexpectedly has a pending update"
assert_address_eq \
    "AutomataPcsDaoV2 resolver" \
    "$(cast call "$PCS_DAO_ADDRESS" 'resolver()(address)' --rpc-url "$RPC_URL")" \
    "$STORAGE_ADDRESS"
assert_address_eq \
    "AutomataPcsDaoV2 CRL helper" \
    "$(cast call "$PCS_DAO_ADDRESS" 'crlLib()(address)' --rpc-url "$RPC_URL")" \
    "$CRL_HELPER_ADDRESS"
assert_address_eq \
    "AutomataPcsDaoV2 PCK helper" \
    "$(cast call "$PCS_DAO_ADDRESS" 'x509()(address)' --rpc-url "$RPC_URL")" \
    "$PCK_HELPER_ADDRESS"
PCS_P256_ADDRESS="$(cast call "$PCS_DAO_ADDRESS" 'P256_VERIFIER()(address)' --rpc-url "$RPC_URL")"
assert_address_eq \
    "AutomataPckDaoV2 resolver" \
    "$(cast call "$PCK_DAO_ADDRESS" 'resolver()(address)' --rpc-url "$RPC_URL")" \
    "$STORAGE_ADDRESS"
assert_address_eq \
    "AutomataPckDaoV2 PCS DAO" \
    "$(cast call "$PCK_DAO_ADDRESS" 'Pcs()(address)' --rpc-url "$RPC_URL")" \
    "$PCS_DAO_ADDRESS"
assert_address_eq \
    "AutomataPckDaoV2 CRL helper" \
    "$(cast call "$PCK_DAO_ADDRESS" 'crlLib()(address)' --rpc-url "$RPC_URL")" \
    "$CRL_HELPER_ADDRESS"
assert_address_eq \
    "AutomataPckDaoV2 PCK helper" \
    "$(cast call "$PCK_DAO_ADDRESS" 'x509()(address)' --rpc-url "$RPC_URL")" \
    "$PCK_HELPER_ADDRESS"
assert_address_eq \
    "AutomataPckDaoV2 P256 verifier" \
    "$(cast call "$PCK_DAO_ADDRESS" 'P256_VERIFIER()(address)' --rpc-url "$RPC_URL")" \
    "$PCS_P256_ADDRESS"

AUTHORIZED="$(
    cast call "$CRL_HELPER_ADDRESS" \
        'authorizedIndexers(address)(bool)' "$PCS_DAO_ADDRESS" \
        --rpc-url "$RPC_URL"
)"
[[ "$AUTHORIZED" == "true" ]] || die "AutomataPcsDaoV2 is not an authorized CRL indexer"

require_storage_writer AutomataPcsDaoV2 "$STORAGE_ADDRESS" "$PCS_DAO_ADDRESS"
require_storage_writer AutomataPckDaoV2 "$STORAGE_ADDRESS" "$PCK_DAO_ADDRESS"

# This read crosses the DAO -> shared-storage authorization boundary. It also
# confirms the migration has the ROOT collateral needed to validate the three
# currently stored CRLs.
cast call "$PCS_DAO_ADDRESS" \
    'getCertificateById(uint8)(bytes,bytes)' 0 \
    --rpc-url "$RPC_URL" >/dev/null \
    || die "AutomataPcsDaoV2 cannot read ROOT collateral from AutomataDaoStorage"

# Empty identifiers still exercise AutomataPckDaoV2 -> AutomataDaoStorage's
# writer-gated TCB mapping read, without requiring a known PCK fixture.
cast call "$PCK_DAO_ADDRESS" \
    'getCert(string,string,string,string)(bytes)' "" "" "" "" \
    --rpc-url "$RPC_URL" >/dev/null \
    || die "AutomataPckDaoV2 cannot read through AutomataDaoStorage"

validate_crl_v2_runtime_code "$OWNER_ADDRESS"

success "CRL V2 contracts are deployed and bound correctly"
printf '  X509CRLHelperV2: %s\n' "$CRL_HELPER_ADDRESS"
printf '  PccsDependencyConfig: %s\n' "$DEPENDENCY_CONFIG_ADDRESS"
printf '  AutomataPcsDaoV2: %s\n' "$PCS_DAO_ADDRESS"
printf '  AutomataPckDaoV2: %s\n' "$PCK_DAO_ADDRESS"
