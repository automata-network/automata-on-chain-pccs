#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  script/fmspc-v2-owner-workflow.sh [--action deploy|grant-attesters|router|all] [--evals "19 20 21"] [--attesters "0x... 0x..."] [--legacy]

Owner-side workflow for promoting FMSPC TCB async upsert V2 on an existing network.

Recommended production sequence:
  1. Run with --action deploy
  2. Run script/fmspc-v2-async-upsert.sh from the attester side for all target FMSPCs
  3. Run with --action router

Required environment:
  RPC_URL                 Target RPC URL
  ATTESTERS               Space/comma separated async upsert worker/backend addresses.
                          ATTESTER is also accepted for single-address compatibility.

Wallet environment, choose one:
  OWNER_ACCOUNT           Foundry keystore account name, e.g. story-owner
  KEYSTORE_PATH           Foundry keystore file/folder path
  PRIVATE_KEY             Owner private key
  UNLOCKED=true OWNER=... Unlocked local sender

Optional environment:
  CHAIN_ID                Expected chain id. If omitted, detected from RPC.
  OWNER                  Owner address. If omitted, derived from wallet where possible.
  PCCS_ROUTER            Existing PCCSRouter address. If omitted, read from dcap.json for router action.
  PCCS_REPO              Defaults to this repository.
  DCAP_REPO              Defaults to ../automata-dcap-attestation.
  USE_CREATE2            Defaults to true.
  FMSPC_V2_GAS_LIMIT     Defaults to 30000000.
  SYNC_DCAP_DEPLOYMENT   Defaults to true.
  FORCE_DEPLOY_HELPER_V2 Defaults to false.
  FORCE_DEPLOY_STORAGE_V2 Defaults to false.
  FORCE_DEPLOY_DAO_V2    Defaults to false.
  CODE_CHECK_RETRIES     Defaults to 8.
  CODE_CHECK_DELAY       Defaults to 5 seconds.
  LEGACY=true            Same as --legacy; passes --legacy to forge/cast.

Examples:
  OWNER_ACCOUNT=story-owner RPC_URL=$RPC_URL ATTESTERS="0x... 0x..." \
    script/fmspc-v2-owner-workflow.sh --action deploy --legacy

  OWNER_ACCOUNT=story-owner RPC_URL=$RPC_URL ATTESTERS="0x..." \
    script/fmspc-v2-owner-workflow.sh --action grant-attesters --legacy

  OWNER_ACCOUNT=story-owner RPC_URL=$RPC_URL \
    script/fmspc-v2-owner-workflow.sh --action router --legacy
EOF
}

ACTION="${ACTION:-deploy}"
TCB_EVALS="${TCB_EVALS:-19 20 21}"
LEGACY="${LEGACY:-false}"
ATTESTERS="${ATTESTERS:-${ATTESTER:-}}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action)
      ACTION="${2:?missing value for --action}"
      shift 2
      ;;
    --evals)
      TCB_EVALS="${2:?missing value for --evals}"
      shift 2
      ;;
    --attesters)
      ATTESTERS="${2:?missing value for --attesters}"
      shift 2
      ;;
    --legacy)
      LEGACY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

case "$ACTION" in
  deploy|grant-attesters|router|all) ;;
  *)
    echo "invalid --action: $ACTION" >&2
    exit 1
    ;;
esac

RPC_URL="${RPC_URL:?missing RPC_URL}"
USE_CREATE2="${USE_CREATE2:-true}"
FMSPC_V2_GAS_LIMIT="${FMSPC_V2_GAS_LIMIT:-30000000}"
SYNC_DCAP_DEPLOYMENT="${SYNC_DCAP_DEPLOYMENT:-true}"
FORCE_DEPLOY_HELPER_V2="${FORCE_DEPLOY_HELPER_V2:-false}"
FORCE_DEPLOY_STORAGE_V2="${FORCE_DEPLOY_STORAGE_V2:-false}"
FORCE_DEPLOY_DAO_V2="${FORCE_DEPLOY_DAO_V2:-false}"
CODE_CHECK_RETRIES="${CODE_CHECK_RETRIES:-8}"
CODE_CHECK_DELAY="${CODE_CHECK_DELAY:-5}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCCS_REPO="${PCCS_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PROJECT_DIR="$(cd "$PCCS_REPO/.." && pwd)"
DCAP_REPO="${DCAP_REPO:-$PROJECT_DIR/automata-dcap-attestation}"

CHAIN_ID_DETECTED="$(cast chain-id --rpc-url "$RPC_URL")"
if [[ -n "${CHAIN_ID:-}" && "$CHAIN_ID" != "$CHAIN_ID_DETECTED" ]]; then
  echo "CHAIN_ID mismatch: env=$CHAIN_ID rpc=$CHAIN_ID_DETECTED" >&2
  exit 1
fi
CHAIN_ID="$CHAIN_ID_DETECTED"
DEPLOYMENT_FILE="$PCCS_REPO/deployment/$CHAIN_ID.json"

LEGACY_ARGS=()
if [[ "$LEGACY" == "true" ]]; then
  LEGACY_ARGS=(--legacy)
fi

FORGE_AUTH_ARGS=()
CAST_AUTH_ARGS=()
OWNER="${OWNER:-}"

if [[ "${UNLOCKED:-}" == "true" ]]; then
  OWNER="${OWNER:?OWNER is required when UNLOCKED=true}"
  FORGE_AUTH_ARGS=(--unlocked --sender "$OWNER")
  CAST_AUTH_ARGS=(--unlocked --from "$OWNER")
elif [[ -n "${OWNER_ACCOUNT:-}" ]]; then
  FORGE_AUTH_ARGS=(--account "$OWNER_ACCOUNT")
  CAST_AUTH_ARGS=(--account "$OWNER_ACCOUNT")
  if [[ -z "$OWNER" ]]; then
    OWNER="$(cast wallet address --account "$OWNER_ACCOUNT")"
  fi
elif [[ -n "${KEYSTORE_PATH:-}" ]]; then
  FORGE_AUTH_ARGS=(--keystore "$KEYSTORE_PATH")
  CAST_AUTH_ARGS=(--keystore "$KEYSTORE_PATH")
  WALLET_ADDRESS_ARGS=(--keystore "$KEYSTORE_PATH")
  if [[ -n "${PASSWORD_FILE:-}" ]]; then
    FORGE_AUTH_ARGS+=(--password-file "$PASSWORD_FILE")
    CAST_AUTH_ARGS+=(--password-file "$PASSWORD_FILE")
    WALLET_ADDRESS_ARGS+=(--password-file "$PASSWORD_FILE")
  fi
  if [[ -z "$OWNER" ]]; then
    OWNER="$(cast wallet address "${WALLET_ADDRESS_ARGS[@]}")"
  fi
elif [[ -n "${PRIVATE_KEY:-}" ]]; then
  FORGE_AUTH_ARGS=(--private-key "$PRIVATE_KEY")
  CAST_AUTH_ARGS=(--private-key "$PRIVATE_KEY")
  if [[ -z "$OWNER" ]]; then
    OWNER="$(cast wallet address --private-key "$PRIVATE_KEY")"
  fi
else
  echo "missing wallet auth: set OWNER_ACCOUNT, KEYSTORE_PATH, PRIVATE_KEY, or UNLOCKED=true OWNER=..." >&2
  exit 1
fi

if [[ ! "$OWNER" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
  echo "invalid OWNER address: $OWNER" >&2
  exit 1
fi

normalize_attesters() {
  local raw="$1"
  raw="${raw//,/ }"
  # shellcheck disable=SC2086
  printf '%s\n' $raw
}

validate_attesters_required() {
  if [[ -z "${ATTESTERS//[[:space:],]/}" ]]; then
    echo "missing ATTESTERS: set ATTESTERS=\"0x... 0x...\" or ATTESTER=0x..." >&2
    exit 1
  fi

  local attester
  while IFS= read -r attester; do
    [[ -z "$attester" ]] && continue
    if [[ ! "$attester" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
      echo "invalid attester address: $attester" >&2
      exit 1
    fi
  done < <(normalize_attesters "$ATTESTERS")
}

if [[ "$ACTION" == "deploy" || "$ACTION" == "grant-attesters" || "$ACTION" == "all" ]]; then
  validate_attesters_required
fi

json_addr_optional() {
  local key="$1"
  if [[ ! -f "$DEPLOYMENT_FILE" ]]; then
    return 0
  fi
  jq -r --arg key "$key" '.[$key] // empty' "$DEPLOYMENT_FILE"
}

json_addr_required() {
  local key="$1"
  jq -er --arg key "$key" '.[$key]' "$DEPLOYMENT_FILE"
}

has_code() {
  local addr="$1"
  [[ "$addr" =~ ^0x[0-9a-fA-F]{40}$ ]] || return 1
  local code
  code="$(cast code "$addr" --rpc-url "$RPC_URL")"
  [[ -n "$code" && "$code" != "0x" ]]
}

wait_for_code() {
  local addr="$1"
  local label="$2"
  local attempt

  for ((attempt = 1; attempt <= CODE_CHECK_RETRIES; attempt++)); do
    if has_code "$addr"; then
      return 0
    fi
    echo "[wait] Missing code for $label at $addr; retry $attempt/$CODE_CHECK_RETRIES after ${CODE_CHECK_DELAY}s"
    sleep "$CODE_CHECK_DELAY"
  done

  has_code "$addr"
}

run_forge_script() {
  local env_args=(OWNER="$OWNER" USE_CREATE2="$USE_CREATE2")
  if [[ -n "${SKIP_POST_DEPLOY_GRANTS:-}" ]]; then
    env_args+=(SKIP_POST_DEPLOY_GRANTS="$SKIP_POST_DEPLOY_GRANTS")
  fi

  env "${env_args[@]}" forge script "$@" \
    --rpc-url "$RPC_URL" \
    "${FORGE_AUTH_ARGS[@]}" \
    --broadcast --skip-simulation -vv \
    "${LEGACY_ARGS[@]}"
}

deploy_helper_v2() {
  local key="FmspcTcbHelperV2"
  local current
  current="$(json_addr_optional "$key")"
  if [[ "$FORCE_DEPLOY_HELPER_V2" != "true" ]] && wait_for_code "$current" "$key"; then
    echo "[deploy] $key already deployed at $current"
    return
  fi

  echo "[deploy] Deploying $key"
  OWNER="$OWNER" USE_CREATE2="$USE_CREATE2" run_forge_script \
    script/helper/DeployHelpers.s.sol:DeployHelpers \
    --sig "deployFmspcTcbHelperV2()"
}

deploy_storage_v2() {
  local key="AutomataDaoStorageV2"
  local current
  current="$(json_addr_optional "$key")"
  if [[ "$FORCE_DEPLOY_STORAGE_V2" != "true" ]] && wait_for_code "$current" "$key"; then
    echo "[deploy] $key already deployed at $current"
    return
  fi

  echo "[deploy] Deploying $key"
  OWNER="$OWNER" USE_CREATE2="$USE_CREATE2" run_forge_script \
    script/automata/versioned/DeployAutomataVersioned.s.sol:DeployAutomataVersioned \
    --sig "deployStorageV2()"
}

deploy_and_config_dao_v2() {
  local eval="$1"
  local key="AutomataFmspcTcbDaoVersionedV2_tcbeval_${eval}"
  local dao
  dao="$(json_addr_optional "$key")"

  if [[ "$FORCE_DEPLOY_DAO_V2" != "true" ]] && wait_for_code "$dao" "$key"; then
    echo "[deploy] $key already deployed at $dao"
  else
    echo "[deploy] Deploying $key"
    # Keep writer authorization in this wrapper so deployment has one explicit
    # grant path. The deploy script also supports post-deploy grants, so disable
    # that internal grant here to avoid sending grantDao() twice.
    SKIP_POST_DEPLOY_GRANTS=true run_forge_script \
      script/automata/versioned/DeployAutomataVersioned.s.sol:DeployAutomataVersioned \
      --gas-limit "$FMSPC_V2_GAS_LIMIT" \
      --sig "deployFmspcTcbDaoVersionedV2(uint32)" "$eval"
    dao="$(json_addr_required "$key")"
  fi

  if ! wait_for_code "$dao" "$key"; then
    echo "missing deployed code for $key at $dao" >&2
    exit 1
  fi

  echo "[config] Granting StorageV2 writer access to $dao"
  run_forge_script \
    script/automata/ConfigAutomataDao.s.sol:ConfigAutomataDao \
    --sig "grantDaoV2(address)" "$dao"

  grant_attesters_for_eval "$eval"
}

grant_attesters_for_eval() {
  local eval="$1"
  local key="AutomataFmspcTcbDaoVersionedV2_tcbeval_${eval}"
  local dao
  dao="$(json_addr_required "$key")"

  if ! wait_for_code "$dao" "$key"; then
    echo "missing deployed code for $key at $dao" >&2
    exit 1
  fi

  local attester
  while IFS= read -r attester; do
    [[ -z "$attester" ]] && continue
    echo "[config] Granting ATTESTER_ROLE to $attester on eval=$eval"
    run_forge_script \
      script/automata/versioned/ConfigAutomataDaoVersioned.s.sol:ConfigureAutomataDaoVersioned \
      --sig "configureFmspcTcbDaoVersionedV2Roles(address,uint32,uint256,bool)" "$attester" "$eval" 1 true
  done < <(normalize_attesters "$ATTESTERS")
}

sync_dcap_deployment() {
  if [[ "$SYNC_DCAP_DEPLOYMENT" != "true" ]]; then
    echo "[sync] Skipping attestation repo deployment sync"
    return
  fi

  local submodule_deployment="$DCAP_REPO/evm/lib/automata-on-chain-pccs/deployment"
  echo "[sync] Copying $DEPLOYMENT_FILE into attestation submodule deployment"
  mkdir -p "$submodule_deployment"
  cp "$DEPLOYMENT_FILE" "$submodule_deployment/$CHAIN_ID.json"

  echo "[sync] Updating network-registry onchain_pccs.json"
  (cd "$DCAP_REPO/rust-crates" && ./scripts/update_pccs_deployment.sh --local "$CHAIN_ID")
}

authorize_router_on_storage() {
  local storage_addr="$1"
  local label="$2"

  if [[ -z "$storage_addr" || "$storage_addr" == "null" ]]; then
    echo "[router] Skipping empty $label address"
    return
  fi

  local authorized
  authorized="$(cast call "$storage_addr" "isAuthorizedCaller(address)(bool)" "$PCCS_ROUTER" --rpc-url "$RPC_URL")"
  if [[ "$authorized" == "true" ]]; then
    echo "[router] PCCSRouter already authorized on $label"
    return
  fi

  echo "[router] Authorizing PCCSRouter on $label"
  cast send "$storage_addr" "setCallerAuthorization(address,bool)" "$PCCS_ROUTER" true \
    --rpc-url "$RPC_URL" \
    "${CAST_AUTH_ARGS[@]}" \
    "${LEGACY_ARGS[@]}"
}

update_router_config() {
  local registry_dir="$DCAP_REPO/rust-crates/libraries/network-registry/deployment/current/$CHAIN_ID"
  local onchain_pccs="$registry_dir/onchain_pccs.json"
  local dcap_json="$registry_dir/dcap.json"

  if [[ ! -f "$onchain_pccs" ]]; then
    echo "missing $onchain_pccs; run --action deploy first or set SYNC_DCAP_DEPLOYMENT=true" >&2
    exit 1
  fi
  if [[ -z "${PCCS_ROUTER:-}" ]]; then
    PCCS_ROUTER="$(jq -er '.PCCSRouter' "$dcap_json")"
  fi

  echo "[router] Router: $PCCS_ROUTER"
  authorize_router_on_storage "$(jq -r '.AutomataDaoStorage' "$onchain_pccs")" "AutomataDaoStorage"
  authorize_router_on_storage "$(jq -r '.AutomataDaoStorageV2 // empty' "$onchain_pccs")" "AutomataDaoStorageV2"

  echo "[router] Building attestation repo"
  (cd "$DCAP_REPO/evm" && forge build)

  for eval in $TCB_EVALS; do
    local expected
    expected="$(jq -er --arg key "AutomataFmspcTcbDaoVersionedV2_tcbeval_${eval}" '.[$key]' "$onchain_pccs")"
    if ! wait_for_code "$expected" "router target eval=$eval"; then
      echo "missing code for router target eval=$eval at $expected" >&2
      exit 1
    fi

    echo "[router] Updating router FMSPC mapping for eval=$eval"
    (
      cd "$DCAP_REPO/evm"
      OWNER="$OWNER" forge script forge-script/DeployRouter.s.sol:DeployRouter \
        --rpc-url "$RPC_URL" \
        "${FORGE_AUTH_ARGS[@]}" \
        --broadcast --skip-simulation -vv \
        "${LEGACY_ARGS[@]}" \
        --sig "updateVersionedDaoConfig(uint32)" "$eval"
    )

    local actual
    actual="$(cast call "$PCCS_ROUTER" "fmspcTcbDaoVersionedAddr(uint32)(address)" "$eval" --rpc-url "$RPC_URL")"
    if [[ "${actual,,}" != "${expected,,}" ]]; then
      echo "router mismatch for eval=$eval: expected=$expected actual=$actual" >&2
      exit 1
    fi
    echo "[router] eval=$eval -> $actual"
  done
}

echo "Owner: $OWNER"
echo "Chain ID: $CHAIN_ID"
echo "Action: $ACTION"
echo "TCB evals: $TCB_EVALS"
if [[ "$ACTION" == "deploy" || "$ACTION" == "grant-attesters" || "$ACTION" == "all" ]]; then
  echo "Attesters:"
  normalize_attesters "$ATTESTERS" | sed 's/^/  - /'
fi
echo "Legacy tx mode: $LEGACY"

cd "$PCCS_REPO"
forge build

if [[ "$ACTION" == "deploy" || "$ACTION" == "all" ]]; then
  deploy_helper_v2
  deploy_storage_v2
  for eval in $TCB_EVALS; do
    deploy_and_config_dao_v2 "$eval"
  done
  sync_dcap_deployment
fi

if [[ "$ACTION" == "grant-attesters" ]]; then
  for eval in $TCB_EVALS; do
    grant_attesters_for_eval "$eval"
  done
fi

if [[ "$ACTION" == "router" || "$ACTION" == "all" ]]; then
  update_router_config
fi

echo "Done"
