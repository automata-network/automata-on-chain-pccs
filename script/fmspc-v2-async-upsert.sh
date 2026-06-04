#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  script/fmspc-v2-async-upsert.sh --targets target_fmspcs.csv
  script/fmspc-v2-async-upsert.sh --platform sgx --fmspc 00606a000000 --eval 19

Attester-side async upsert helper for FMSPC TCB DAO V2.

Required environment:
  RPC_URL
  CHAIN_ID
  ATTESTER_PRIVATE_KEY

Optional environment:
  PCCS_REPO                  Defaults to this repository.
  QPL_REPO                   Defaults to ../automata-dcap-qpl.
  COLLATERAL_VERSION         Defaults to v4.
  QPL_GAS_PRICE              Defaults to cast gas-price.
  QPL_ASYNC_PARSE_BATCH_SIZE Exported to qpl tool when set.
  QPL_FALLBACK_GAS_LIMIT    Exported to qpl tool when set.
  CARGO_RELEASE              Defaults to true. Set false for cargo run without --release.

CSV formats:
  platform,fmspc,eval,pck_ca,collateral_update_type
  sgx,00606a000000,19,,
  tdx,00806f050000,19,tdx,

or:
  fmspc,eval,pck_ca,collateral_update_type
  00606a000000,19,,
  00806f050000,19,tdx,

Notes:
  - For TDX, pck_ca defaults to "tdx" when omitted and platform is tdx.
  - The DAO address is read from automata-on-chain-pccs/deployment/$CHAIN_ID.json.
EOF
}

TARGETS_FILE=""
SINGLE_PLATFORM="${PLATFORM:-}"
SINGLE_FMSPC="${FMSPC:-}"
SINGLE_EVAL="${TCB_EVAL:-}"
SINGLE_PCK_CA="${PCK_CA:-}"
SINGLE_UPDATE_TYPE="${COLLATERAL_UPDATE_TYPE:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --targets)
      TARGETS_FILE="${2:?missing value for --targets}"
      shift 2
      ;;
    --platform)
      SINGLE_PLATFORM="${2:?missing value for --platform}"
      shift 2
      ;;
    --fmspc)
      SINGLE_FMSPC="${2:?missing value for --fmspc}"
      shift 2
      ;;
    --eval)
      SINGLE_EVAL="${2:?missing value for --eval}"
      shift 2
      ;;
    --pck-ca)
      SINGLE_PCK_CA="${2:?missing value for --pck-ca}"
      shift 2
      ;;
    --collateral-update-type)
      SINGLE_UPDATE_TYPE="${2:?missing value for --collateral-update-type}"
      shift 2
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

RPC_URL="${RPC_URL:?missing RPC_URL}"
CHAIN_ID="${CHAIN_ID:?missing CHAIN_ID}"
ATTESTER_PRIVATE_KEY="${ATTESTER_PRIVATE_KEY:?missing ATTESTER_PRIVATE_KEY}"
COLLATERAL_VERSION="${COLLATERAL_VERSION:-v4}"
CARGO_RELEASE="${CARGO_RELEASE:-true}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCCS_REPO="${PCCS_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PROJECT_DIR="$(cd "$PCCS_REPO/.." && pwd)"
QPL_REPO="${QPL_REPO:-$PROJECT_DIR/automata-dcap-qpl}"
DEPLOYMENT_FILE="$PCCS_REPO/deployment/$CHAIN_ID.json"

if [[ ! -f "$DEPLOYMENT_FILE" ]]; then
  echo "missing deployment file: $DEPLOYMENT_FILE" >&2
  exit 1
fi

if [[ ! -d "$QPL_REPO" ]]; then
  echo "missing QPL repo: $QPL_REPO" >&2
  exit 1
fi

if [[ -n "${QPL_ASYNC_PARSE_BATCH_SIZE:-}" ]]; then
  export QPL_ASYNC_PARSE_BATCH_SIZE
fi
if [[ -n "${QPL_FALLBACK_GAS_LIMIT:-}" ]]; then
  export QPL_FALLBACK_GAS_LIMIT
fi

QPL_GAS_PRICE="${QPL_GAS_PRICE:-$(cast gas-price --rpc-url "$RPC_URL")}"

trim() {
  local s="$*"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

has_code() {
  local addr="$1"
  [[ "$addr" =~ ^0x[0-9a-fA-F]{40}$ ]] || return 1
  local code
  code="$(cast code "$addr" --rpc-url "$RPC_URL")"
  [[ -n "$code" && "$code" != "0x" ]]
}

dao_for_eval() {
  local eval="$1"
  jq -er --arg key "AutomataFmspcTcbDaoVersionedV2_tcbeval_${eval}" '.[$key]' "$DEPLOYMENT_FILE"
}

run_one() {
  local platform
  local fmspc
  local eval
  local pck_ca
  local update_type

  platform="$(trim "$1")"
  fmspc="$(trim "$2")"
  eval="$(trim "$3")"
  pck_ca="$(trim "$4")"
  update_type="$(trim "$5")"

  platform="${platform,,}"
  fmspc="${fmspc#0x}"

  if [[ -z "$platform" ]]; then
    if [[ "${pck_ca,,}" == "tdx" ]]; then
      platform="tdx"
    else
      platform="sgx"
    fi
  fi
  if [[ "$platform" != "sgx" && "$platform" != "tdx" ]]; then
    echo "invalid platform '$platform' for fmspc=$fmspc eval=$eval" >&2
    exit 1
  fi
  if [[ "$platform" == "tdx" && -z "$pck_ca" ]]; then
    pck_ca="tdx"
  fi
  if [[ ! "$fmspc" =~ ^[0-9a-fA-F]{12}$ ]]; then
    echo "invalid fmspc: $fmspc" >&2
    exit 1
  fi
  if [[ ! "$eval" =~ ^[1-9][0-9]*$ ]]; then
    echo "invalid eval for fmspc=$fmspc: $eval" >&2
    exit 1
  fi

  local dao
  dao="$(dao_for_eval "$eval")"
  if ! has_code "$dao"; then
    echo "missing DAO V2 code for eval=$eval at $dao" >&2
    exit 1
  fi

  local cargo_args=(run --release --)
  if [[ "$CARGO_RELEASE" != "true" ]]; then
    cargo_args=(run --)
  fi

  local qpl_args=(
    --function upsert_tcb_fmspc_async
    --private_key "$ATTESTER_PRIVATE_KEY"
    --rpc_url "$RPC_URL"
    --chain_id "$CHAIN_ID"
    --gas_price "$QPL_GAS_PRICE"
    --collateral_version "$COLLATERAL_VERSION"
    --fmspc "$fmspc"
    --fmspc_tcb_dao_contract_addr "$dao"
    --tcb_evaluation_data_number "$eval"
  )

  if [[ -n "$pck_ca" ]]; then
    qpl_args+=(--pck_ca "$pck_ca")
  fi
  if [[ -n "$update_type" ]]; then
    qpl_args+=(--collateral_update_type "$update_type")
  fi

  echo "[async-upsert] platform=$platform fmspc=$fmspc eval=$eval dao=$dao pck_ca=${pck_ca:-<empty>}"
  (cd "$QPL_REPO" && cargo "${cargo_args[@]}" "${qpl_args[@]}")
}

run_targets_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "missing targets file: $file" >&2
    exit 1
  fi

  while IFS=, read -r c1 c2 c3 c4 c5 _rest; do
    c1="$(trim "$c1")"
    c2="$(trim "$c2")"
    c3="$(trim "$c3")"
    c4="$(trim "$c4")"
    c5="$(trim "$c5")"

    [[ -z "$c1$c2$c3$c4$c5" ]] && continue
    [[ "${c1:0:1}" == "#" ]] && continue
    case "${c1,,}" in
      platform|kind|fmspc) continue ;;
    esac

    if [[ "${c1,,}" == "sgx" || "${c1,,}" == "tdx" ]]; then
      run_one "$c1" "$c2" "$c3" "$c4" "$c5"
    else
      run_one "" "$c1" "$c2" "$c3" "$c4"
    fi
  done < "$file"
}

if [[ -n "$TARGETS_FILE" ]]; then
  run_targets_file "$TARGETS_FILE"
else
  if [[ -z "$SINGLE_FMSPC" || -z "$SINGLE_EVAL" ]]; then
    echo "provide --targets, or provide --fmspc and --eval" >&2
    usage
    exit 1
  fi
  run_one "$SINGLE_PLATFORM" "$SINGLE_FMSPC" "$SINGLE_EVAL" "$SINGLE_PCK_CA" "$SINGLE_UPDATE_TYPE"
fi

echo "Done"
