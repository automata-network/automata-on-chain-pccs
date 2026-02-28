#!/bin/bash

# verify_versioned.sh - Verify versioned Automata contracts on block explorers
# Usage: ./verify_versioned.sh [verifier] [verifier_url]
#
# Supports multichain mode: set MULTICHAIN=true to verify across all chains in rpc_map.
# Use CHAIN_IDS=1,10,42161 to filter to specific chains.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Show usage information
show_usage() {
    echo "Usage: $0 [verifier] [verifier_url]"
    echo ""
    echo "Verify versioned Automata contracts on block explorers:"
    echo "  - AutomataTcbEvalDao"
    echo "  - AutomataEnclaveIdentityDaoVersioned"
    echo "  - AutomataFmspcTcbDaoVersioned"
    echo ""
    echo "Arguments:"
    echo "  verifier                   Block explorer verifier (default: etherscan)"
    echo "                            Options: etherscan, blockscout"
    echo "  verifier_url              Custom verifier API URL (optional for etherscan, required for blockscout)"
    echo ""
    echo "Required Environment Variables (single-chain mode):"
    echo "  RPC_URL                    RPC URL for the target network"
    echo "  OWNER                      Owner address for the contracts"
    echo ""
    echo "Multichain Environment Variables:"
    echo "  MULTICHAIN=true            Enable multichain verification via rpc_map"
    echo "  CHAIN_IDS=1,10,42161       Filter to specific chain IDs (optional)"
    echo "  OWNER                      Owner address for the contracts"
    echo ""
    echo "Optional Environment Variables:"
    echo "  ETHERSCAN_API_KEY          API key for Etherscan verification"
    echo "  BLOCKSCOUT_API_KEY         API key for Blockscout verification (if required)"
    echo ""
    echo "Examples:"
    echo "  $0                                           Verify on Etherscan (default)"
    echo "  $0 etherscan                                 Verify on Etherscan explicitly"
    echo "  $0 blockscout https://blockscout.example.com/api  Verify on custom Blockscout"
    echo "  MULTICHAIN=true CHAIN_IDS=11155111 $0        Verify on Sepolia via rpc_map"
    echo ""
    echo "Note: For blockscout verifier, verifier_url is required"
}

# Check if help is requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_usage
    exit 0
fi

# Set defaults
VERIFIER="${1:-etherscan}"
VERIFIER_URL="$2"

print_info "Starting contract verification"
print_info "Verifier: $VERIFIER"
if [ -n "$VERIFIER_URL" ]; then
    print_info "Verifier URL: $VERIFIER_URL"
fi

# Get project root (try git first, fallback to script-relative)
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    PROJECT_ROOT=$(git rev-parse --show-toplevel)
    print_info "Project root detected via git: $PROJECT_ROOT"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
    print_info "Project root detected via script location: $PROJECT_ROOT"
fi

# Validate verifier
if [ "$VERIFIER" != "etherscan" ] && [ "$VERIFIER" != "blockscout" ]; then
    print_error "Invalid verifier: $VERIFIER"
    print_error "Supported verifiers: etherscan, blockscout"
    exit 1
fi

# Validate verifier_url requirement for blockscout
if [ "$VERIFIER" = "blockscout" ] && [ -z "$VERIFIER_URL" ]; then
    print_error "verifier_url is required when using blockscout verifier"
    echo "Usage: $0 blockscout <verifier_url>"
    echo "Example: $0 blockscout https://blockscout.example.com/api"
    exit 1
fi

if [ -z "$OWNER" ]; then
    print_error "OWNER environment variable is required"
    exit 1
fi

# Read contract addresses from deployment file
read_contract_address() {
    local contract_name="$1"
    local deployment_file="$2"
    local address=$(jq -r ".$contract_name" "$deployment_file")
    if [ "$address" = "null" ] || [ -z "$address" ]; then
        print_error "Contract address not found for: $contract_name"
        return 1
    fi
    echo "$address"
}

# Function to verify a contract
verify_contract() {
    local contract_addr="$1"
    local contract_path="$2"
    local constructor_args="$3"
    local rpc_url="$4"
    local contract_name=$(basename "$contract_path" | cut -d':' -f2)

    local forge_verify_args="--rpc-url $rpc_url --verifier $VERIFIER --watch"
    if [ -n "$VERIFIER_URL" ]; then
        forge_verify_args="$forge_verify_args --verifier-url $VERIFIER_URL"
    fi

    print_info "Verifying $contract_name at $contract_addr..."

    if [ -n "$constructor_args" ]; then
        print_info "Constructor args: $constructor_args"
        cd "$PROJECT_ROOT" && forge verify-contract \
            $forge_verify_args \
            "$contract_addr" \
            "$contract_path" \
            --constructor-args "$constructor_args" || {
            print_warn "Verification failed for $contract_name, continuing..."
            return 1
        }
    else
        cd "$PROJECT_ROOT" && forge verify-contract \
            $forge_verify_args \
            "$contract_addr" \
            "$contract_path" || {
            print_warn "Verification failed for $contract_name, continuing..."
            return 1
        }
    fi

    print_info "Successfully verified $contract_name"
    return 0
}

# Core verification logic for a single chain
verify_chain() {
    local rpc_url="$1"
    local chain_id="$2"

    print_info "=== Verifying contracts on chain ID: $chain_id ==="

    # Check if deployment file exists
    local deployment_file="$PROJECT_ROOT/deployment/$chain_id.json"
    if [ ! -f "$deployment_file" ]; then
        print_warn "Deployment file not found: $deployment_file, skipping chain $chain_id"
        return 0
    fi

    # Get P256 Verifier address
    print_info "Determining P256 Verifier address..."
    local p256_address
    p256_address=$(cd "$PROJECT_ROOT" && forge script script/utils/P256Configuration.sol:P256Configuration --rpc-url "$rpc_url" --sig "simulateVerify()" -vv | awk '/P256Verifier address:/ { print $NF; exit }')
    if [ -z "$p256_address" ]; then
        print_error "Failed to determine P256 Verifier address for chain $chain_id"
        return 1
    fi
    print_info "P256 Verifier address: $p256_address"

    # Get required addresses
    local storage_addr x509_helper_addr crl_helper_addr pcs_dao_addr enclave_identity_helper_addr fmspc_tcb_helper_addr tcb_eval_helper_addr
    storage_addr=$(read_contract_address "AutomataDaoStorage" "$deployment_file") || return 1
    x509_helper_addr=$(read_contract_address "PCKHelper" "$deployment_file") || return 1
    crl_helper_addr=$(read_contract_address "X509CRLHelper" "$deployment_file") || return 1
    pcs_dao_addr=$(read_contract_address "AutomataPcsDao" "$deployment_file") || return 1
    enclave_identity_helper_addr=$(read_contract_address "EnclaveIdentityHelper" "$deployment_file") || return 1
    fmspc_tcb_helper_addr=$(read_contract_address "FmspcTcbHelper" "$deployment_file") || return 1
    tcb_eval_helper_addr=$(read_contract_address "TcbEvalHelper" "$deployment_file") || return 1

    # Verify AutomataTcbEvalDao
    local tcb_eval_dao_addr
    tcb_eval_dao_addr=$(read_contract_address "AutomataTcbEvalDao" "$deployment_file") || return 1
    local tcb_eval_dao_args
    tcb_eval_dao_args=$(cast abi-encode "constructor(address,address,address,address,address,address,address)" \
        "$storage_addr" "$p256_address" "$pcs_dao_addr" "$tcb_eval_helper_addr" "$x509_helper_addr" "$crl_helper_addr" "$OWNER")

    verify_contract "$tcb_eval_dao_addr" "src/automata_pccs/AutomataTcbEvalDao.sol:AutomataTcbEvalDao" "$tcb_eval_dao_args" "$rpc_url"

    # Find and verify all versioned contracts
    print_info "Searching for versioned contracts in deployment file..."

    local versioned_contracts
    versioned_contracts=$(jq -r 'to_entries[] | select(.key | test("_tcbeval_[0-9]+$")) | "\(.key):\(.value)"' "$deployment_file")

    if [ -z "$versioned_contracts" ]; then
        print_warn "No versioned contracts found in deployment file"
    else
        echo "$versioned_contracts" | while IFS=':' read -r contract_key contract_addr; do
            local contract_base tcb_eval_number
            contract_base=$(echo "$contract_key" | sed 's/_tcbeval_[0-9]*$//')
            tcb_eval_number=$(echo "$contract_key" | sed 's/.*_tcbeval_//')

            print_info "Found versioned contract: $contract_base tcb-eval-number $tcb_eval_number at $contract_addr"

            case "$contract_base" in
                "AutomataEnclaveIdentityDaoVersioned")
                    local constructor_args
                    constructor_args=$(cast abi-encode "constructor(address,address,address,address,address,address,address,uint32)" \
                        "$storage_addr" "$p256_address" "$pcs_dao_addr" "$enclave_identity_helper_addr" "$x509_helper_addr" "$crl_helper_addr" "$OWNER" "$tcb_eval_number")
                    verify_contract "$contract_addr" "src/automata_pccs/versioned/AutomataEnclaveIdentityDaoVersioned.sol:AutomataEnclaveIdentityDaoVersioned" "$constructor_args" "$rpc_url"
                    ;;
                "AutomataFmspcTcbDaoVersioned")
                    local constructor_args
                    constructor_args=$(cast abi-encode "constructor(address,address,address,address,address,address,address,uint32)" \
                        "$storage_addr" "$p256_address" "$pcs_dao_addr" "$fmspc_tcb_helper_addr" "$x509_helper_addr" "$crl_helper_addr" "$OWNER" "$tcb_eval_number")
                    verify_contract "$contract_addr" "src/automata_pccs/versioned/AutomataFmspcTcbDaoVersioned.sol:AutomataFmspcTcbDaoVersioned" "$constructor_args" "$rpc_url"
                    ;;
                *)
                    print_warn "Unknown versioned contract type: $contract_base"
                    ;;
            esac
        done
    fi

    print_info "=== Chain $chain_id verification complete ==="
}

# Main execution
if [ "$MULTICHAIN" = "true" ]; then
    # Multichain mode: iterate over chains from rpc_map
    print_info "MULTICHAIN mode enabled"

    # Source the rpc_map helper
    source "$PROJECT_ROOT/script/utils/rpc_map_helper.sh"

    target_chain_ids=$(get_target_chain_ids)
    if [ -z "$target_chain_ids" ]; then
        print_error "No target chain IDs found"
        exit 1
    fi

    while IFS= read -r chain_id; do
        chain_id=$(echo "$chain_id" | tr -d '[:space:]')
        [ -z "$chain_id" ] && continue

        rpc_url=$(get_rpc_url_for_chain "$chain_id") || {
            print_warn "Skipping chain $chain_id: no RPC URL found"
            continue
        }

        verify_chain "$rpc_url" "$chain_id" || {
            print_warn "Verification had errors on chain $chain_id, continuing..."
        }
    done <<< "$target_chain_ids"

    print_info "Multichain verification completed!"
else
    # Single-chain mode (original behavior)
    if [ -z "$RPC_URL" ]; then
        print_error "RPC_URL environment variable is required"
        exit 1
    fi

    print_info "Detecting chain ID..."
    CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
    print_info "Chain ID: $CHAIN_ID"

    verify_chain "$RPC_URL" "$CHAIN_ID"

    print_info "Contract verification completed!"
    print_info "Verifier: $VERIFIER"
    print_info "Chain ID: $CHAIN_ID"

    if [ "$VERIFIER" = "etherscan" ]; then
        print_info "Contracts should be visible on Etherscan shortly"
    elif [ "$VERIFIER" = "blockscout" ]; then
        print_info "Contracts should be visible on Blockscout at: $VERIFIER_URL"
    fi
fi
