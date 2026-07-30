#!/usr/bin/env bash

set -Eeuo pipefail

CRL_V2_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCCS_ROOT="${PCCS_ROOT:-$(cd "$CRL_V2_SCRIPT_DIR/../.." && pwd)}"

_CRL_V2_OWNS_PASSWORD_FILE=false
_CRL_V2_FORBIDDEN_REVERT_DATA="0x08c379a000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000009464f5242494444454e0000000000000000000000000000000000000000000000"

info() {
    printf '[INFO] %s\n' "$*"
}

success() {
    printf '[OK] %s\n' "$*"
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

cleanup_crl_v2_wallet() {
    if [[ "$_CRL_V2_OWNS_PASSWORD_FILE" == "true" && -n "${KEYSTORE_PASSWORD_FILE:-}" ]]; then
        rm -f -- "$KEYSTORE_PASSWORD_FILE"
    fi
}

init_network() {
    require_command cast
    require_command jq

    [[ -n "${RPC_URL:-}" ]] || die "RPC_URL is required"
    [[ -n "${CHAIN_ID:-}" ]] || die "CHAIN_ID is required"
    [[ "$CHAIN_ID" =~ ^[0-9]+$ ]] || die "CHAIN_ID must be an unsigned integer"

    local rpc_chain_id
    rpc_chain_id="$(cast chain-id --rpc-url "$RPC_URL")"
    [[ "$rpc_chain_id" == "$CHAIN_ID" ]] \
        || die "RPC chain ID $rpc_chain_id does not match configured CHAIN_ID $CHAIN_ID"

    info "Target chain ID: $CHAIN_ID"
}

init_keystore() {
    [[ -z "${PRIVATE_KEY:-}" ]] || die "PRIVATE_KEY is not supported by these scripts; use KEYSTORE_PATH"
    [[ -n "${KEYSTORE_PATH:-}" ]] || die "KEYSTORE_PATH is required"
    [[ -f "$KEYSTORE_PATH" ]] || die "Keystore file not found: $KEYSTORE_PATH"

    if [[ -n "${KEYSTORE_PASSWORD_FILE:-}" ]]; then
        [[ -f "$KEYSTORE_PASSWORD_FILE" ]] \
            || die "Keystore password file not found: $KEYSTORE_PASSWORD_FILE"
    else
        local keystore_password
        read -r -s -p "Keystore password: " keystore_password
        printf '\n'

        umask 077
        KEYSTORE_PASSWORD_FILE="$(mktemp "${TMPDIR:-/tmp}/crl-v2-keystore-password.XXXXXX")"
        printf '%s\n' "$keystore_password" > "$KEYSTORE_PASSWORD_FILE"
        unset keystore_password
        export KEYSTORE_PASSWORD_FILE
        _CRL_V2_OWNS_PASSWORD_FILE=true
    fi

    trap cleanup_crl_v2_wallet EXIT

    OWNER_ADDRESS="$(
        cast wallet address \
            --keystore "$KEYSTORE_PATH" \
            --password-file "$KEYSTORE_PASSWORD_FILE"
    )"
    [[ "$OWNER_ADDRESS" =~ ^0x[0-9a-fA-F]{40}$ ]] \
        || die "Could not derive an address from KEYSTORE_PATH"

    export OWNER="$OWNER_ADDRESS"
    FORGE_WALLET_ARGS=(
        --keystore "$KEYSTORE_PATH"
        --password-file "$KEYSTORE_PASSWORD_FILE"
    )
    CAST_WALLET_ARGS=(
        --keystore "$KEYSTORE_PATH"
        --password-file "$KEYSTORE_PASSWORD_FILE"
    )

    info "Keystore signer: $OWNER_ADDRESS"
}

init_deployment_context() {
    init_network
    init_keystore
}

forge_broadcast_args() {
    FORGE_BROADCAST_ARGS=(
        --rpc-url "$RPC_URL"
        "${FORGE_WALLET_ARGS[@]}"
        --sender "$OWNER_ADDRESS"
        --broadcast
        -vv
    )

    if [[ "${SKIP_SIMULATION:-false}" == "true" ]]; then
        FORGE_BROADCAST_ARGS+=(--skip-simulation)
    fi
    if [[ "${LEGACY:-false}" == "true" ]]; then
        FORGE_BROADCAST_ARGS+=(--legacy)
    fi
    if [[ "${SLOW:-false}" == "true" ]]; then
        FORGE_BROADCAST_ARGS+=(--slow)
    fi
    if [[ -n "${GAS_ESTIMATE_MULTIPLIER:-}" ]]; then
        [[ "$GAS_ESTIMATE_MULTIPLIER" =~ ^[1-9][0-9]*$ ]] \
            || die "GAS_ESTIMATE_MULTIPLIER must be a positive integer percentage"
        FORGE_BROADCAST_ARGS+=(--gas-estimate-multiplier "$GAS_ESTIMATE_MULTIPLIER")
    fi
}

json_address() {
    local json_file="$1"
    local key="$2"
    local value

    [[ -f "$json_file" ]] || die "Deployment file not found: $json_file"
    value="$(jq -er --arg key "$key" '.[$key] | select(type == "string")' "$json_file")" \
        || die "Missing deployment address '$key' in $json_file"
    [[ "$value" =~ ^0x[0-9a-fA-F]{40}$ ]] \
        || die "Invalid deployment address '$key' in $json_file: $value"
    [[ "${value,,}" != "0x0000000000000000000000000000000000000000" ]] \
        || die "Zero deployment address '$key' in $json_file"
    printf '%s\n' "$value"
}

json_address_if_present() {
    local json_file="$1"
    local key="$2"
    local value

    [[ -f "$json_file" ]] || return 1
    value="$(jq -er --arg key "$key" '.[$key] | select(type == "string")' "$json_file" 2>/dev/null)" \
        || return 1
    [[ "$value" =~ ^0x[0-9a-fA-F]{40}$ ]] || return 1
    [[ "${value,,}" != "0x0000000000000000000000000000000000000000" ]] || return 1
    printf '%s\n' "$value"
}

require_contract_code() {
    local label="$1"
    local address="$2"
    local code

    code="$(cast code "$address" --rpc-url "$RPC_URL")"
    [[ -n "$code" && "$code" != "0x" ]] || die "$label has no contract code at $address"
}

_is_forbidden_storage_revert() {
    local output="${1,,}"

    if [[ "$output" == *"$_CRL_V2_FORBIDDEN_REVERT_DATA"* ]]; then
        return 0
    fi

    # Some cast versions decode Error(string) without printing the raw revert
    # data. Match the complete reason token, not an arbitrary FORBIDDEN
    # substring, so unrelated failures remain unknown.
    [[ "$output" =~ execution[[:space:]]reverted:[[:space:]]forbidden([^a-z0-9_]|$) ]]
}

storage_writer_state() {
    local storage_address="$1"
    local dao_address="$2"
    local probe_id="0x0000000000000000000000000000000000000000000000000000000000000000"
    local output

    if output="$(
        cast call "$storage_address" \
            'readAttestation(bytes32)(bytes)' "$probe_id" \
            --from "$dao_address" \
            --rpc-url "$RPC_URL" 2>&1
    )"; then
        if [[ "$output" =~ ^0x([0-9a-fA-F]{2})*$ ]]; then
            printf 'authorized\n'
            return
        fi
        die "Could not determine AutomataDaoStorage authorization: malformed successful response: $output"
    fi

    if _is_forbidden_storage_revert "$output"; then
        printf 'revoked\n'
        return
    fi

    die "Could not determine AutomataDaoStorage authorization: $output"
}

require_storage_writer() {
    local label="$1"
    local storage_address="$2"
    local dao_address="$3"
    local probe_key="0x43524c5f56325f5752495445525f50524f424500000000000000000000000000"
    local zero_hash="0x0000000000000000000000000000000000000000000000000000000000000000"
    local state

    state="$(storage_writer_state "$storage_address" "$dao_address")"
    [[ "$state" == "authorized" ]] \
        || die "$label cannot read AutomataDaoStorage as an authorized DAO"

    cast call "$storage_address" \
        'attest(bytes32,bytes,bytes32)(bytes32,bytes32)' \
        "$probe_key" 0x "$zero_hash" \
        --from "$dao_address" \
        --rpc-url "$RPC_URL" >/dev/null \
        || die "$label cannot write AutomataDaoStorage as an authorized DAO"
}

require_storage_writer_revoked() {
    local label="$1"
    local storage_address="$2"
    local dao_address="$3"
    local state

    state="$(storage_writer_state "$storage_address" "$dao_address")"
    [[ "$state" == "revoked" ]] \
        || die "$label still has AutomataDaoStorage writer authorization"
}

validate_crl_v2_runtime_code() {
    local owner_address="$1"

    require_command forge
    info "Comparing deployed CRL V2 runtime code hashes with the current build"
    (
        cd "$PCCS_ROOT"
        OWNER="$owner_address" forge script script/automata/DeployCrlV2.s.sol:DeployCrlV2 \
            --rpc-url "$RPC_URL" \
            --sig 'validateExistingRuntime()' \
            -vv
    )
}

assert_address_eq() {
    local label="$1"
    local actual="$2"
    local expected="$3"

    [[ "${actual,,}" == "${expected,,}" ]] \
        || die "$label mismatch: expected $expected, got $actual"
}

stored_crl_hash() {
    local pcs_dao="$1"
    local ca="$2"
    local result
    local crl

    result="$(
        cast call "$pcs_dao" \
            'getCertificateById(uint8)(bytes,bytes)' "$ca" \
            --rpc-url "$RPC_URL" \
            --json
    )"
    crl="$(jq -er 'if type == "array" and length == 2 then .[1] else error("unexpected cast output") end' <<<"$result")" \
        || die "Could not decode the stored CRL for CA $ca"
    [[ "$crl" =~ ^0x[0-9a-fA-F]+$ && "$crl" != "0x" ]] \
        || die "No stored CRL found for CA $ca"

    cast keccak "$crl"
}

ca_number() {
    case "${1,,}" in
        root) printf '0\n' ;;
        processor) printf '1\n' ;;
        platform) printf '2\n' ;;
        *) die "Unsupported CA '$1'; expected root, processor, or platform" ;;
    esac
}
