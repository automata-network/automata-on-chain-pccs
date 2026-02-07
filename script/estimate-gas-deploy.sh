#!/bin/bash
# Estimates gas for contract deployments using cast estimate
# Usage: ./script/estimate-gas-deploy.sh <rpc_url> <buffer_percent> <contract_spec1> [contract_spec2...]
# Contract spec: "ContractName" or "ContractName:constructor(types):arg1,arg2,..."

set -e

if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <rpc_url> <buffer_percent> <contract_spec1> [contract_spec2...]" >&2
    echo "Contract spec: \"ContractName\" or \"ContractName:constructor(types):arg1,arg2,...\"" >&2
    exit 1
fi

RPC_URL=$1
BUFFER=$2
shift 2
CONTRACT_SPECS=("$@")

# Ensure forge build has been run
if [ ! -d "out" ]; then
    echo "Error: 'out' directory not found. Run 'forge build' first." >&2
    exit 1
fi

MAX_GAS=0
MAX_CONTRACT=""

for spec in "${CONTRACT_SPECS[@]}"; do
    # Parse contract spec - split by colon
    CONTRACT=$(echo "$spec" | cut -d: -f1)
    SIG=$(echo "$spec" | cut -d: -f2 -s)      # -s = suppress if no delimiter
    ARGS=$(echo "$spec" | cut -d: -f3- -s)    # f3- = field 3 onwards

    # Convert comma-separated args to space-separated
    if [ -n "$ARGS" ]; then
        ARGS=$(echo "$ARGS" | tr ',' ' ')
    fi

    CONTRACT_FILE="out/${CONTRACT}.sol/${CONTRACT}.json"

    if [ ! -f "$CONTRACT_FILE" ]; then
        echo "Warning: Contract artifact not found: $CONTRACT_FILE" >&2
        continue
    fi

    # Extract bytecode from forge output
    BYTECODE=$(jq -r '.bytecode.object' "$CONTRACT_FILE" 2>/dev/null)

    if [ -z "$BYTECODE" ] || [ "$BYTECODE" = "null" ]; then
        echo "Warning: Could not extract bytecode for $CONTRACT" >&2
        continue
    fi

    # Estimate gas - with or without constructor args
    if [ -n "$SIG" ] && [ -n "$ARGS" ]; then
        GAS=$(cast estimate --rpc-url "$RPC_URL" --create "$BYTECODE" "$SIG" $ARGS 2>/dev/null || echo "0")
    else
        GAS=$(cast estimate --rpc-url "$RPC_URL" --create "$BYTECODE" 2>/dev/null || echo "0")
    fi

    if [ "$GAS" -eq "0" ]; then
        echo "Warning: Gas estimation failed for $CONTRACT" >&2
        continue
    fi

    echo "  $CONTRACT: $GAS gas" >&2

    if [ "$GAS" -gt "$MAX_GAS" ]; then
        MAX_GAS=$GAS
        MAX_CONTRACT=$CONTRACT
    fi
done

if [ "$MAX_GAS" -eq "0" ]; then
    echo "Error: Failed to estimate gas for any contract" >&2
    exit 1
fi

# Apply buffer
FINAL_GAS=$((MAX_GAS * (100 + BUFFER) / 100))

echo "  Max: $MAX_CONTRACT ($MAX_GAS gas)" >&2
echo "  Buffer: +${BUFFER}%" >&2
echo "  Final estimate: $FINAL_GAS gas" >&2

# Output only the final gas value to stdout for make to capture
echo $FINAL_GAS
