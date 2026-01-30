#!/bin/bash

# deploy_versioned.sh - Deploy versioned Automata contracts
# Usage: ./deploy_versioned.sh <command> [arguments...]

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
    echo "Usage: $0 <command> [arguments...]"
    echo ""
    echo "Deploy versioned Automata contracts with separate commands:"
    echo ""
    echo "Commands:"
    echo "  tcb-eval                   Deploy AutomataTcbEvalDao only"
    echo "  versioned                  Deploy versioned DAO contracts (EnclaveIdentity + FmspcTcb)"
    echo ""
    echo "Arguments for 'tcb-eval':"
    echo "  (no additional arguments required)"
    echo ""
    echo "Arguments for 'versioned':"
    echo "  tcb-eval-data-number      TCB evaluation data number for versioned contracts (required)"
    echo ""
echo "Required Environment Variables (unless MULTICHAIN=true):"
echo "  RPC_URL                    RPC URL for the target network"
    echo ""
    echo "Required Wallet Credentials (one of):"
    echo "  PRIVATE_KEY                Private key for wallet"
    echo "  KEYSTORE_PATH              Path to keystore file (default: keystore/dcap_prod)"
    echo ""
echo "Optional Environment Variables:"
echo "  SIMULATED                  Set to 'true' for simulation mode (default: false)"
echo "  LEGACY                     Set to 'true' for legacy transaction mode"
echo "  MULTICHAIN                 Set to 'true' to deploy across all supported chains (default: false)"
echo "  GAS_LIMIT                  Skip gas estimation if manually provided (informational only)"
echo "  GAS_BUFFER                 Gas estimate buffer percentage (default: 10)"
echo "  SKIP_ESTIMATE              Skip gas estimation entirely"
    echo ""
    echo "Examples:"
    echo "  $0 tcb-eval                                   Deploy AutomataTcbEvalDao"
    echo "  $0 versioned 17                               Deploy versioned contracts with tcb-eval-data-number 17"
    echo "  SIMULATED=true $0 versioned 18                Simulate deployment with tcb-eval-data-number 18"
}

# Check if help is requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_usage
    exit 0
fi

# Validate command argument
COMMAND="$1"
if [ -z "$COMMAND" ]; then
    print_error "Command is required"
    show_usage
    exit 1
fi

if [ "$COMMAND" != "tcb-eval" ] && [ "$COMMAND" != "versioned" ]; then
    print_error "Invalid command: $COMMAND"
    print_error "Valid commands: tcb-eval, versioned"
    show_usage
    exit 1
fi

# Parse arguments based on command
if [ "$COMMAND" = "tcb-eval" ]; then
    if [ $# -ne 1 ]; then
        print_error "tcb-eval command takes no additional arguments"
        show_usage
        exit 1
    fi
    TCB_EVALUATION_DATA_NUMBER=""  # Not used for tcb-eval
elif [ "$COMMAND" = "versioned" ]; then
    if [ $# -ne 2 ]; then
        print_error "versioned command requires tcb-eval-data-number argument"
        show_usage
        exit 1
    fi
    
    TCB_EVALUATION_DATA_NUMBER="$2"
    
    # Validate tcb-eval-data-number is a positive integer
    if ! [[ "$TCB_EVALUATION_DATA_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
        print_error "tcb-eval-data-number must be a positive integer"
        exit 1
    fi
fi

# Set default gas buffer
GAS_BUFFER=${GAS_BUFFER:-10}

print_info "Starting deployment for $COMMAND command"
if [ -n "$TCB_EVALUATION_DATA_NUMBER" ]; then
    print_info "TCB Eval Data Number: $TCB_EVALUATION_DATA_NUMBER"
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

# Check required environment variables
if [ -z "$RPC_URL" ] && [ "$MULTICHAIN" != "true" ]; then
    print_error "RPC_URL environment variable is required (unless MULTICHAIN=true)"
    exit 1
fi

# Set up wallet authentication and derive OWNER
WALLET_ARGS=""
OWNER=""
if [ -n "$PRIVATE_KEY" ]; then
    OWNER=$(cast wallet address --private-key "$PRIVATE_KEY")
    WALLET_ARGS="--private-key $PRIVATE_KEY"
    print_info "Using private key authentication"
    print_info "Derived owner address: $OWNER"
else
    KEYSTORE_PATH=${KEYSTORE_PATH:-"$PROJECT_ROOT/keystore/dcap_prod"}
    if [ ! -f "$KEYSTORE_PATH" ]; then
        print_error "No wallet credentials provided. Either set PRIVATE_KEY or ensure keystore file exists at: $KEYSTORE_PATH"
        exit 1
    fi
    read -s -p "Enter keystore password: " KEYSTORE_PASSWORD
    echo
    OWNER=$(cast wallet address --keystore "$KEYSTORE_PATH" --password "$KEYSTORE_PASSWORD")
    WALLET_ARGS="--keystore $KEYSTORE_PATH --password $KEYSTORE_PASSWORD"
    print_info "Using keystore authentication: $KEYSTORE_PATH"
    print_info "Derived owner address: $OWNER"
fi

# Validate that OWNER was successfully derived
if [ -z "$OWNER" ]; then
    print_error "Failed to derive owner address from wallet credentials"
    exit 1
fi

# Resolve addresses needed for gas estimation
resolve_addresses() {
    STORAGE_ADDR=$(jq -r '.AutomataDaoStorage' "$DEPLOYMENT_FILE")
    PCS_DAO_ADDR=$(jq -r '.AutomataPcsDao' "$DEPLOYMENT_FILE")
    X509_HELPER=$(jq -r '.PCKHelper' "$DEPLOYMENT_FILE")
    CRL_HELPER=$(jq -r '.X509CRLHelper' "$DEPLOYMENT_FILE")
    ENCLAVE_HELPER=$(jq -r '.EnclaveIdentityHelper' "$DEPLOYMENT_FILE")
    FMSPC_HELPER=$(jq -r '.FmspcTcbHelper' "$DEPLOYMENT_FILE")
    TCB_EVAL_HELPER=$(jq -r '.TcbEvalHelper' "$DEPLOYMENT_FILE")

    # Get P256 verifier address
    print_info "Resolving P256 verifier address..."
    P256_ADDR=$(forge script script/utils/P256Configuration.sol:P256Configuration \
        --rpc-url "$RPC_URL" --sig "simulateVerify()" -vv 2>/dev/null | \
        awk '/P256Verifier address:/ { print $NF; exit }')

    if [ -z "$P256_ADDR" ]; then
        print_error "Failed to resolve P256 verifier address"
        exit 1
    fi
    print_info "P256 verifier address: $P256_ADDR"
}

# Estimate gas for deployment (informational only)
# Args: contract_spec1 [contract_spec2 ...]
estimate_gas() {
    if [ "$SKIP_ESTIMATE" = "true" ] || [ -n "$GAS_LIMIT" ]; then
        return
    fi

    print_info "Estimating gas from network..."

    GAS_LIMIT=$("$PROJECT_ROOT/script/estimate-gas-deploy.sh" "$RPC_URL" "$GAS_BUFFER" "$@")

    if [ -z "$GAS_LIMIT" ] || [ "$GAS_LIMIT" = "0" ]; then
        print_error "Gas estimation failed"
        exit 1
    fi

    print_info "Estimated gas limit: $GAS_LIMIT"
}

# Get chain ID (single-chain mode only)
if [ "$MULTICHAIN" != "true" ]; then
    print_info "Detecting chain ID..."
    CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
    print_info "Chain ID: $CHAIN_ID"
fi

# Check if deployment file exists (helper contracts should be deployed first) (single-chain mode only)
if [ "$MULTICHAIN" != "true" ]; then
    DEPLOYMENT_FILE="$PROJECT_ROOT/deployment/$CHAIN_ID.json"
    if [ ! -f "$DEPLOYMENT_FILE" ]; then
        print_error "Helper contracts not found at $DEPLOYMENT_FILE"
        print_error "Please deploy helper contracts first using: make deploy-helpers"
        exit 1
    fi

    # Validate that required helper contracts exist
    REQUIRED_HELPERS=("PCKHelper" "X509CRLHelper" "EnclaveIdentityHelper" "FmspcTcbHelper" "AutomataDaoStorage" "AutomataPcsDao")
    for helper in "${REQUIRED_HELPERS[@]}"; do
        if ! jq -e ".$helper" "$DEPLOYMENT_FILE" > /dev/null 2>&1; then
            print_error "Required helper contract '$helper' not found in $DEPLOYMENT_FILE"
            exit 1
        fi
    done
fi

# Set up forge command options
if [ "$MULTICHAIN" = "true" ]; then
    print_info "MULTICHAIN mode enabled"
    export MULTICHAIN=true
    FORGE_ARGS="$WALLET_ARGS -vv"
else
    FORGE_ARGS="--rpc-url $RPC_URL $WALLET_ARGS -vv"
fi

if [ "$SIMULATED" = "true" ]; then
    print_warn "Running in simulation mode (no actual deployment)"
else
    FORGE_ARGS="$FORGE_ARGS --broadcast --skip-simulation"
fi

if [ "$LEGACY" = "true" ]; then
    FORGE_ARGS="$FORGE_ARGS --legacy"
fi

# Execute command-specific deployment
if [ "$COMMAND" = "tcb-eval" ]; then
    # Resolve addresses and estimate gas (skip in MULTICHAIN mode)
    if [ "$MULTICHAIN" != "true" ]; then
        resolve_addresses

        # Estimate gas for AutomataTcbEvalDao
        # constructor(address,address,address,address,address,address,address)
        TCB_EVAL_SPEC="AutomataTcbEvalDao:constructor(address,address,address,address,address,address,address):$STORAGE_ADDR,$P256_ADDR,$PCS_DAO_ADDR,$TCB_EVAL_HELPER,$X509_HELPER,$CRL_HELPER,$OWNER"
        estimate_gas "$TCB_EVAL_SPEC"
    else
        print_warn "MULTICHAIN mode: Gas estimation skipped (per-chain estimation)"
    fi

    # Deploy TcbEvalDao only
    print_info "Deploying AutomataTcbEvalDao..."
    cd "$PROJECT_ROOT" && OWNER="$OWNER" forge script script/automata/versioned/DeployAutomataVersioned.s.sol:DeployAutomataVersioned \
        $FORGE_ARGS \
        --sig "deployTcbEvalDao()"

    if [ $? -ne 0 ]; then
        print_error "Failed to deploy AutomataTcbEvalDao"
        exit 1
    fi

elif [ "$COMMAND" = "versioned" ]; then
    # Resolve addresses and estimate gas (skip in MULTICHAIN mode)
    if [ "$MULTICHAIN" != "true" ]; then
        resolve_addresses

        # Estimate gas for both versioned contracts
        # AutomataEnclaveIdentityDaoVersioned: constructor(address,address,address,address,address,address,address,uint32)
        ENCLAVE_SPEC="AutomataEnclaveIdentityDaoVersioned:constructor(address,address,address,address,address,address,address,uint32):$STORAGE_ADDR,$P256_ADDR,$PCS_DAO_ADDR,$ENCLAVE_HELPER,$X509_HELPER,$CRL_HELPER,$OWNER,$TCB_EVALUATION_DATA_NUMBER"

        # AutomataFmspcTcbDaoVersioned: constructor(address,address,address,address,address,address,address,uint32)
        FMSPC_SPEC="AutomataFmspcTcbDaoVersioned:constructor(address,address,address,address,address,address,address,uint32):$STORAGE_ADDR,$P256_ADDR,$PCS_DAO_ADDR,$FMSPC_HELPER,$X509_HELPER,$CRL_HELPER,$OWNER,$TCB_EVALUATION_DATA_NUMBER"

        estimate_gas "$ENCLAVE_SPEC" "$FMSPC_SPEC"
    else
        print_warn "MULTICHAIN mode: Gas estimation skipped (per-chain estimation)"
    fi

    # Deploy both versioned DAOs
    print_info "Deploying AutomataEnclaveIdentityDaoVersioned (tcb-eval-data-number: $TCB_EVALUATION_DATA_NUMBER)..."
    cd "$PROJECT_ROOT" && OWNER="$OWNER" forge script script/automata/versioned/DeployAutomataVersioned.s.sol:DeployAutomataVersioned \
        $FORGE_ARGS \
        --sig "deployEnclaveIdDaoVersioned(uint32)" "$TCB_EVALUATION_DATA_NUMBER"

    if [ $? -ne 0 ]; then
        print_error "Failed to deploy AutomataEnclaveIdentityDaoVersioned"
        exit 1
    fi

    print_info "Deploying AutomataFmspcTcbDaoVersioned (tcb-eval-data-number: $TCB_EVALUATION_DATA_NUMBER)..."
    cd "$PROJECT_ROOT" && OWNER="$OWNER" forge script script/automata/versioned/DeployAutomataVersioned.s.sol:DeployAutomataVersioned \
        $FORGE_ARGS \
        --sig "deployFmspcTcbDaoVersioned(uint32)" "$TCB_EVALUATION_DATA_NUMBER"

    if [ $? -ne 0 ]; then
        print_error "Failed to deploy AutomataFmspcTcbDaoVersioned"
        exit 1
    fi
fi

print_info "Deployment completed successfully for $COMMAND command!"
if [ -n "$TCB_EVALUATION_DATA_NUMBER" ]; then
    print_info "TCB Eval Data Number: $TCB_EVALUATION_DATA_NUMBER"
fi
if [ "$MULTICHAIN" != "true" ]; then
    print_info "Chain ID: $CHAIN_ID"
else
    print_info "Mode: MULTICHAIN"
fi

if [ "$SIMULATED" != "true" ]; then
    if [ "$MULTICHAIN" != "true" ]; then
        print_info "Contract addresses have been saved to: $DEPLOYMENT_FILE"
    else
        print_info "Contract addresses have been saved to deployment/<chainId>.json for each processed chain"
    fi
    print_info "Next steps:"
    print_info "  1. Configure roles: ./config_versioned.sh"
    print_info "  2. Verify contracts: ./verify_versioned.sh"
fi
