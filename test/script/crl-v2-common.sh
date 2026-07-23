#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCCS_ROOT="$(cd "$TEST_DIR/../.." && pwd)"

# shellcheck source=../../script/crl-v2/_common.sh
source "$PCCS_ROOT/script/crl-v2/_common.sh"

readonly STORAGE_ADDRESS="0x0000000000000000000000000000000000000001"
readonly DAO_ADDRESS="0x0000000000000000000000000000000000000002"
readonly FORBIDDEN_REVERT_DATA="0x08c379a000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000009464f5242494444454e0000000000000000000000000000000000000000000000"

RPC_URL="http://mock.invalid"

cast() {
    case "$MOCK_CAST_MODE" in
        authorized)
            printf '0x\n'
            ;;
        forbidden)
            printf 'Error: execution reverted; data: %s\n' "$FORBIDDEN_REVERT_DATA" >&2
            return 1
            ;;
        forbidden_text)
            printf 'Error: execution reverted: FORBIDDEN\n' >&2
            return 1
            ;;
        forbidden_suffix)
            printf 'Error: execution reverted: FORBIDDEN_BY_POLICY\n' >&2
            return 1
            ;;
        unreachable)
            printf 'Error: error sending request for url (http://127.0.0.1:1/)\n' >&2
            return 1
            ;;
        timeout)
            printf 'Error: request timed out\n' >&2
            return 1
            ;;
        malformed)
            printf 'Error: expected value at line 1 column 1\n' >&2
            return 1
            ;;
        malformed_success)
            printf 'not-hex\n'
            ;;
        unrelated)
            printf 'Error: execution reverted: INVALID_STATE\n' >&2
            return 1
            ;;
        *)
            printf 'Unexpected mock mode: %s\n' "$MOCK_CAST_MODE" >&2
            return 2
            ;;
    esac
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local label="$3"

    if [[ "$actual" != "$expected" ]]; then
        printf '[FAIL] %s: expected %q, got %q\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_unknown() {
    local mode="$1"
    local expected_message="$2"
    local output
    local status

    set +e
    output="$(
        MOCK_CAST_MODE="$mode" storage_writer_state "$STORAGE_ADDRESS" "$DAO_ADDRESS" 2>&1
    )"
    status=$?
    set -e

    if ((status == 0)); then
        printf '[FAIL] %s failure was classified as a known authorization state\n' "$mode" >&2
        exit 1
    fi
    if [[ "$output" != *"Could not determine AutomataDaoStorage authorization"* ]]; then
        printf '[FAIL] %s failure did not produce the authorization diagnostic: %s\n' "$mode" "$output" >&2
        exit 1
    fi
    if [[ "$output" != *"$expected_message"* ]]; then
        printf '[FAIL] %s diagnostic lost the underlying error: %s\n' "$mode" "$output" >&2
        exit 1
    fi
}

state="$(MOCK_CAST_MODE=authorized storage_writer_state "$STORAGE_ADDRESS" "$DAO_ADDRESS")"
assert_eq authorized "$state" "authorized call"

state="$(MOCK_CAST_MODE=forbidden storage_writer_state "$STORAGE_ADDRESS" "$DAO_ADDRESS")"
assert_eq revoked "$state" "exact FORBIDDEN revert"

state="$(MOCK_CAST_MODE=forbidden_text storage_writer_state "$STORAGE_ADDRESS" "$DAO_ADDRESS")"
assert_eq revoked "$state" "decoded FORBIDDEN revert"

assert_unknown unreachable "error sending request"
assert_unknown timeout "request timed out"
assert_unknown malformed "expected value"
assert_unknown malformed_success "malformed successful response"
assert_unknown unrelated "INVALID_STATE"
assert_unknown forbidden_suffix "FORBIDDEN_BY_POLICY"

printf '[PASS] CRL V2 storage authorization state tests\n'
