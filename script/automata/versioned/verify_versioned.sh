#!/bin/bash

# verify_versioned.sh - Verify versioned Automata contracts on block explorers
# Usage: ./verify_versioned.sh [verifier] [verifier_url]

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
    echo "Required Environment Variables:"
    echo "  RPC_URL                    RPC URL for the target network"
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

# Check required environment variables
if [ -z "$RPC_URL" ]; then
    print_error "RPC_URL environment variable is required"
    exit 1
fi

if [ -z "$OWNER" ]; then
    print_error "OWNER environment variable is required"
    exit 1
fi

# Get chain ID
print_info "Detecting chain ID..."
CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
print_info "Chain ID: $CHAIN_ID"

# Check if deployment file exists
DEPLOYMENT_FILE="$PROJECT_ROOT/deployment/$CHAIN_ID.json"
if [ ! -f "$DEPLOYMENT_FILE" ]; then
    print_error "Deployment file not found: $DEPLOYMENT_FILE"
    print_error "Please deploy contracts first using: ./deploy_versioned.sh"
    exit 1
fi

# Get P256 Verifier address
print_info "Determining P256 Verifier address..."
P256_ADDRESS=$(cd "$PROJECT_ROOT" && forge script script/utils/P256Configuration.sol:P256Configuration --rpc-url "$RPC_URL" --sig "simulateVerify()" -vv | awk '/P256Verifier address:/ { print $NF; exit }')
if [ -z "$P256_ADDRESS" ]; then
    print_error "Failed to determine P256 Verifier address"
    exit 1
fi
print_info "P256 Verifier address: $P256_ADDRESS"

# Read contract addresses from deployment file
read_contract_address() {
    local contract_name="$1"
    local address=$(jq -r ".$contract_name" "$DEPLOYMENT_FILE")
    if [ "$address" = "null" ] || [ -z "$address" ]; then
        print_error "Contract address not found for: $contract_name"
        exit 1
    fi
    echo "$address"
}

# Read versioned contract addresses
read_versioned_contract_address() {
    local contract_name="$1"
    local version="$2"
    local versioned_key="${contract_name}_v${version}"
    local address=$(jq -r ".$versioned_key" "$DEPLOYMENT_FILE")
    if [ "$address" = "null" ] || [ -z "$address" ]; then
        print_error "Versioned contract address not found for: $versioned_key"
        exit 1
    fi
    echo "$address"
}

# Get required addresses
STORAGE_ADDR=$(read_contract_address "AutomataDaoStorage")
X509_HELPER_ADDR=$(read_contract_address "PCKHelper")
CRL_HELPER_ADDR=$(read_contract_address "X509CRLHelper")
PCS_DAO_ADDR=$(read_contract_address "AutomataPcsDao")
ENCLAVE_IDENTITY_HELPER_ADDR=$(read_contract_address "EnclaveIdentityHelper")
FMSPC_TCB_HELPER_ADDR=$(read_contract_address "FmspcTcbHelper")
TCB_EVAL_HELPER_ADDR=$(read_contract_address "TcbEvalHelper")

# Set up forge verify command base
FORGE_VERIFY_ARGS="--rpc-url $RPC_URL --verifier $VERIFIER --watch"

if [ -n "$VERIFIER_URL" ]; then
    FORGE_VERIFY_ARGS="$FORGE_VERIFY_ARGS --verifier-url $VERIFIER_URL"
fi

# Function to verify a contract
verify_contract() {
    local contract_addr="$1"
    local contract_path="$2"
    local constructor_args="$3"
    local contract_name=$(basename "$contract_path" | cut -d':' -f2)
    
    print_info "Verifying $contract_name at $contract_addr..."
    
    if [ -n "$constructor_args" ]; then
        print_info "Constructor args: $constructor_args"
        cd "$PROJECT_ROOT" && forge verify-contract \
            $FORGE_VERIFY_ARGS \
            "$contract_addr" \
            "$contract_path" \
            --constructor-args "$constructor_args" || {
            print_warn "Verification failed for $contract_name, continuing..."
            return 1
        }
    else
        cd "$PROJECT_ROOT" && forge verify-contract \
            $FORGE_VERIFY_ARGS \
            "$contract_addr" \
            "$contract_path" || {
            print_warn "Verification failed for $contract_name, continuing..."
            return 1
        }
    fi
    
    print_info "Successfully verified $contract_name"
    return 0
}

# Verify AutomataTcbEvalDao
TCB_EVAL_DAO_ADDR=$(read_contract_address "AutomataTcbEvalDao")
TCB_EVAL_DAO_ARGS=$(cast abi-encode "constructor(address,address,address,address,address,address,address)" \
    "$STORAGE_ADDR" "$P256_ADDRESS" "$PCS_DAO_ADDR" "$TCB_EVAL_HELPER_ADDR" "$X509_HELPER_ADDR" "$CRL_HELPER_ADDR" "$OWNER")

verify_contract "$TCB_EVAL_DAO_ADDR" "src/automata_pccs/AutomataTcbEvalDao.sol:AutomataTcbEvalDao" "$TCB_EVAL_DAO_ARGS"

# Find and verify all versioned contracts
print_info "Searching for versioned contracts in deployment file..."

# Get all versioned contract entries
VERSIONED_CONTRACTS=$(jq -r 'to_entries[] | select(.key | test("_tcbeval_[0-9]+$")) | "\(.key):\(.value)"' "$DEPLOYMENT_FILE")

if [ -z "$VERSIONED_CONTRACTS" ]; then
    print_warn "No versioned contracts found in deployment file"
else
    echo "$VERSIONED_CONTRACTS" | while IFS=':' read -r contract_key contract_addr; do
        # Extract contract name and tcb eval number
        contract_base=$(echo "$contract_key" | sed 's/_tcbeval_[0-9]*$//')
        tcb_eval_number=$(echo "$contract_key" | sed 's/.*_tcbeval_//')
        
        print_info "Found versioned contract: $contract_base tcb-eval-number $tcb_eval_number at $contract_addr"
        
        case "$contract_base" in
            "AutomataEnclaveIdentityDaoVersioned")
                constructor_args=$(cast abi-encode "constructor(address,address,address,address,address,address,address,uint32)" \
                    "$STORAGE_ADDR" "$P256_ADDRESS" "$PCS_DAO_ADDR" "$ENCLAVE_IDENTITY_HELPER_ADDR" "$X509_HELPER_ADDR" "$CRL_HELPER_ADDR" "$OWNER" "$tcb_eval_number")
                verify_contract "$contract_addr" "src/automata_pccs/versioned/AutomataEnclaveIdentityDaoVersioned.sol:AutomataEnclaveIdentityDaoVersioned" "$constructor_args"
                ;;
            "AutomataFmspcTcbDaoVersioned")
                constructor_args=$(cast abi-encode "constructor(address,address,address,address,address,address,address,uint32)" \
                    "$STORAGE_ADDR" "$P256_ADDRESS" "$PCS_DAO_ADDR" "$FMSPC_TCB_HELPER_ADDR" "$X509_HELPER_ADDR" "$CRL_HELPER_ADDR" "$OWNER" "$tcb_eval_number")
                verify_contract "$contract_addr" "src/automata_pccs/versioned/AutomataFmspcTcbDaoVersioned.sol:AutomataFmspcTcbDaoVersioned" "$constructor_args"
                ;;
            *)
                print_warn "Unknown versioned contract type: $contract_base"
                ;;
        esac
    done
fi

print_info "Contract verification completed!"
print_info "Verifier: $VERIFIER"
print_info "Chain ID: $CHAIN_ID"

if [ "$VERIFIER" = "etherscan" ]; then
    print_info "Contracts should be visible on Etherscan shortly"
elif [ "$VERIFIER" = "blockscout" ]; then
    print_info "Contracts should be visible on Blockscout at: $VERIFIER_URL"
fi
