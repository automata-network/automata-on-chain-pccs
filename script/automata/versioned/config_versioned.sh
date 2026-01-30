#!/bin/bash

# config_versioned.sh - Configure roles for versioned Automata contracts
# Usage: ./config_versioned.sh <command> [arguments...]

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
    echo "Configure roles for versioned Automata contracts with separate commands:"
    echo ""
    echo "Commands:"
    echo "  tcb-eval                   Configure AutomataTcbEvalDao roles"
    echo "  versioned                  Configure versioned DAO roles (EnclaveIdentity + FmspcTcb)"
    echo ""
    echo "Arguments for 'tcb-eval':"
    echo "  user_address               Address to grant/revoke roles (default: derived from wallet)"
    echo "  roles                      Role bitmask to configure (default: 1 = ATTESTER_ROLE)"
    echo "  authorize                  Grant (true) or revoke (false) roles (default: true)"
    echo ""
    echo "Arguments for 'versioned':"
    echo "  tcb-eval-data-number      TCB evaluation data number for versioned contracts (required)"
    echo "  user_address               Address to grant/revoke roles (default: derived from wallet)"
    echo "  roles                      Role bitmask to configure (default: 1 = ATTESTER_ROLE)"
    echo "  authorize                  Grant (true) or revoke (false) roles (default: true)"
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
    echo "  MULTICHAIN                 Set to 'true' to run for all chains (default: false)"
    echo ""
    echo "Role Values:"
    echo "  1                          ATTESTER_ROLE (default)"
    echo "  (Use any bitmask value as needed)"
    echo ""
    echo "Examples:"
    echo "  $0 tcb-eval                                   Grant ATTESTER_ROLE to wallet owner for TcbEvalDao"
    echo "  $0 tcb-eval 0x123... 1 true                   Grant ATTESTER_ROLE to 0x123... for TcbEvalDao"
    echo "  $0 versioned 17                               Grant ATTESTER_ROLE to wallet owner for tcb-eval-data-number 17"
    echo "  $0 versioned 18 0x123... 1 true               Grant ATTESTER_ROLE to 0x123... for tcb-eval-data-number 18"
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

# Parse arguments based on command
if [ "$COMMAND" = "tcb-eval" ]; then
    USER_ADDRESS="${2:-$OWNER}"
    ROLES="${3:-1}"
    AUTHORIZE="${4:-true}"
    TCB_EVAL_DATA_NUMBER=""  # Not used for tcb-eval
elif [ "$COMMAND" = "versioned" ]; then
    TCB_EVAL_DATA_NUMBER="$2"
    USER_ADDRESS="${3:-$OWNER}"
    ROLES="${4:-1}"
    AUTHORIZE="${5:-true}"
    
    # Validate required tcb-eval-data-number for versioned command
    if [ -z "$TCB_EVAL_DATA_NUMBER" ]; then
        print_error "tcb-eval-data-number is required for versioned command"
        show_usage
        exit 1
    fi
    
    # Validate tcb-eval-data-number is a positive integer
    if ! [[ "$TCB_EVAL_DATA_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
        print_error "tcb-eval-data-number must be a positive integer"
        exit 1
    fi
fi

print_info "Starting role configuration for $COMMAND command"
print_info "User: $USER_ADDRESS"
if [ -n "$TCB_EVAL_DATA_NUMBER" ]; then
    print_info "TCB Eval Data Number: $TCB_EVAL_DATA_NUMBER"
fi
print_info "Roles: $ROLES"
print_info "Action: $([ "$AUTHORIZE" = "true" ] && echo "Grant" || echo "Revoke")"

if [ -z "$USER_ADDRESS" ]; then
    print_error "User address is required (provide as argument or derived from wallet)"
    exit 1
fi

# Validate inputs
if ! [[ "$ROLES" =~ ^[1-9][0-9]*$ ]]; then
    print_error "Roles must be a positive integer (bitmask)"
    exit 1
fi

if [ "$AUTHORIZE" != "true" ] && [ "$AUTHORIZE" != "false" ]; then
    print_error "Authorize must be 'true' or 'false'"
    exit 1
fi

# Validate user address format
if ! [[ "$USER_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    print_error "Invalid user address format: $USER_ADDRESS"
    exit 1
fi

# Get chain ID
if [ -z "$MULTICHAIN" ]; then
    print_info "Detecting chain ID..."
    CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
    print_info "Chain ID: $CHAIN_ID"
fi

# Set up forge command options
if [ "$MULTICHAIN" = "true" ]; then
    FORGE_ARGS="$WALLET_ARGS -vv"
else
    FORGE_ARGS="--rpc-url $RPC_URL $WALLET_ARGS -vv"
fi

if [ "$MULTICHAIN" = "true" ]; then
    print_info "MULTICHAIN mode enabled"
    export MULTICHAIN=true
fi

if [ "$SIMULATED" = "true" ]; then
    print_warn "Running in simulation mode (no actual transactions)"
else
    FORGE_ARGS="$FORGE_ARGS --broadcast --skip-simulation"
fi

if [ "$LEGACY" = "true" ]; then
    FORGE_ARGS="$FORGE_ARGS --legacy"
fi

# Execute command-specific configuration
if [ "$COMMAND" = "tcb-eval" ]; then
    # Configure TcbEvalDao roles only
    print_info "Configuring AutomataTcbEvalDao roles..."
    cd "$PROJECT_ROOT" && OWNER="$OWNER" forge script script/automata/versioned/ConfigAutomataDaoVersioned.s.sol:ConfigureAutomataDaoVersioned \
        $FORGE_ARGS \
        --sig "configureTcbEvalDaoRoles(address,uint256,bool)" "$USER_ADDRESS" "$ROLES" "$AUTHORIZE"

    if [ $? -ne 0 ]; then
        print_error "Failed to configure AutomataTcbEvalDao roles"
        exit 1
    fi

elif [ "$COMMAND" = "versioned" ]; then
    # Configure both versioned DAOs
    print_info "Configuring AutomataEnclaveIdentityDaoVersioned roles (tcb-eval-data-number: $TCB_EVAL_DATA_NUMBER)..."
    cd "$PROJECT_ROOT" && OWNER="$OWNER" forge script script/automata/versioned/ConfigAutomataDaoVersioned.s.sol:ConfigureAutomataDaoVersioned \
        $FORGE_ARGS \
        --sig "configureEnclaveIdentityDaoVersionedRoles(address,uint32,uint256,bool)" "$USER_ADDRESS" "$TCB_EVAL_DATA_NUMBER" "$ROLES" "$AUTHORIZE"

    if [ $? -ne 0 ]; then
        print_error "Failed to configure AutomataEnclaveIdentityDaoVersioned roles"
        exit 1
    fi

    print_info "Configuring AutomataFmspcTcbDaoVersioned roles (tcb-eval-data-number: $TCB_EVAL_DATA_NUMBER)..."
    cd "$PROJECT_ROOT" && OWNER="$OWNER" forge script script/automata/versioned/ConfigAutomataDaoVersioned.s.sol:ConfigureAutomataDaoVersioned \
        $FORGE_ARGS \
        --sig "configureFmspcTcbDaoVersionedRoles(address,uint32,uint256,bool)" "$USER_ADDRESS" "$TCB_EVAL_DATA_NUMBER" "$ROLES" "$AUTHORIZE"

    if [ $? -ne 0 ]; then
        print_error "Failed to configure AutomataFmspcTcbDaoVersioned roles"
        exit 1
    fi
fi

ACTION_TEXT=$([ "$AUTHORIZE" = "true" ] && echo "granted" || echo "revoked")
print_info "Role configuration completed successfully for $COMMAND command!"
print_info "User: $USER_ADDRESS"
if [ -n "$TCB_EVAL_DATA_NUMBER" ]; then
    print_info "TCB Eval Data Number: $TCB_EVAL_DATA_NUMBER"
fi
print_info "Roles: $ROLES ($ACTION_TEXT)"

if [ "$SIMULATED" != "true" ]; then
    print_info "Role configurations have been applied on-chain"
    print_info "Next step: Verify contracts with ./verify_versioned.sh"
fi
