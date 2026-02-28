#!/bin/bash

# rpc_map_helper.sh - Shared utility for reading chain IDs and RPC URLs from rpc_map
#
# Usage: source this file, then call the functions below.
#
#   source script/utils/rpc_map_helper.sh
#   get_rpc_map_chain_ids    # list all chain IDs
#   get_rpc_url_for_chain 1  # get RPC URL for chain ID 1
#   get_target_chain_ids     # respects CHAIN_IDS filter or returns all

# Resolve project root
if [ -z "$PROJECT_ROOT" ]; then
    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        PROJECT_ROOT=$(git rev-parse --show-toplevel)
    else
        # Fallback: assume this script is at script/utils/rpc_map_helper.sh
        PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    fi
fi

RPC_MAP_FILE="$PROJECT_ROOT/rpc_map"

# Get all chain IDs from rpc_map (one per line)
get_rpc_map_chain_ids() {
    if [ ! -f "$RPC_MAP_FILE" ]; then
        echo "ERROR: rpc_map file not found at $RPC_MAP_FILE" >&2
        return 1
    fi
    jq -r 'keys[]' "$RPC_MAP_FILE"
}

# Get RPC URL for a specific chain ID
# Args: chain_id
get_rpc_url_for_chain() {
    local chain_id="$1"
    if [ -z "$chain_id" ]; then
        echo "ERROR: chain_id argument required" >&2
        return 1
    fi
    if [ ! -f "$RPC_MAP_FILE" ]; then
        echo "ERROR: rpc_map file not found at $RPC_MAP_FILE" >&2
        return 1
    fi
    local url
    url=$(jq -r --arg id "$chain_id" '.[$id] // empty' "$RPC_MAP_FILE")
    if [ -z "$url" ]; then
        echo "ERROR: No RPC URL found for chain ID $chain_id" >&2
        return 1
    fi
    echo "$url"
}

# Get target chain IDs, respecting CHAIN_IDS filter env var
# If CHAIN_IDS is set (comma-separated), returns only those IDs
# Otherwise returns all chain IDs from rpc_map
get_target_chain_ids() {
    if [ -n "$CHAIN_IDS" ]; then
        # Split comma-separated CHAIN_IDS and output one per line
        echo "$CHAIN_IDS" | tr ',' '\n'
    else
        get_rpc_map_chain_ids
    fi
}
