#!/usr/bin/env bash
# Download every available SGX + TDX V4 TCB info from Intel PCS and split into the inner
# tcbInfo object + signature, so the Forge parity suite can iterate them as fixtures.
#
# Usage:
#   allproxy && cd <repo>/test/tcb/fixtures/pcs && ./fetch.sh
#
# Produces, per fmspc:
#   <platform>_<fmspc>.tcbInfo  — the EXACT inner-tcbInfo substring (same shape as
#                                  case*_tcbinfo.json in the parent dir)
#   <platform>_<fmspc>.sig      — 64-byte signature hex (no 0x prefix)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

# fmspc lists pulled from Intel PCS as of 2026-05.
SGX=(
  00606C040000 00906EC10000 00806F050000 00706E470000 00906EA10000 00906EA50000
  C0806F000000 00A06E050000 00A06D080000 20A06E050000 10A06F010000 B0C06F000000
  00606A000000 00806F000000 00906ED50000 F0806F000000 00906EB10000 10A06D000000
  00806EB70000 00A065510000 20A06D080000 90806F000000 30606A000000 00A067110000
  20806EB70000 70A06D070000 50806F000000 00706A100000 30806F040000 60A06F000000
  20A06F000000 20906EC10000 20606C040000 00706A800000 00906EC50000 00806EA60000
  90C06F000000
)
TDX=(
  10A06F010000 60A06F000000 20A06E050000 C0806F000000 70A06D070000 20A06D080000
  10A06D000000 00806F050000 20A06F000000 90C06F000000 50806F000000 B0C06F000000
  00A06D080000 00A06E050000
)

fetch_one() {
  local platform="$1"
  local fmspc="$2"
  local out_body="${platform}_${fmspc}.tcbInfo"
  local out_sig="${platform}_${fmspc}.sig"
  if [[ -s "$out_body" && -s "$out_sig" ]]; then
    echo "[skip] $platform $fmspc (already present)"
    return
  fi
  local url="https://api.trustedservices.intel.com/${platform}/certification/v4/tcb?fmspc=${fmspc}"
  echo "[get ] $platform $fmspc"
  local resp
  resp=$(curl -sS --max-time 60 "$url")
  # Inner tcbInfo substring (byte-exact). Mirrors qpl-tool's extract_tcb_info_str:
  # raw between "tcbInfo": and ,"signature" — preserves Intel's minification.
  python3 - "$resp" "$out_body" "$out_sig" <<'PY'
import sys
resp, out_body, out_sig = sys.argv[1], sys.argv[2], sys.argv[3]
start_marker = '"tcbInfo":'
end_marker = ',"signature"'
i = resp.find(start_marker)
if i < 0:
    raise SystemExit(f"missing tcbInfo in: {resp[:200]}")
tail = resp[i + len(start_marker):]
j = tail.find(end_marker)
if j < 0:
    raise SystemExit(f"missing signature delimiter in: {resp[:200]}")
inner = tail[:j]
# Extract signature value (16-byte aligned ascii hex). It's the value of "signature".
sig_marker = '"signature":"'
k = resp.find(sig_marker)
if k < 0:
    raise SystemExit("missing signature value")
sig_start = k + len(sig_marker)
sig_end = resp.find('"', sig_start)
sig = resp[sig_start:sig_end]
open(out_body, 'w').write(inner)
open(out_sig, 'w').write(sig)
PY
}

count=0
for fmspc in "${SGX[@]}"; do
  fetch_one sgx "$fmspc"
  count=$((count+1))
done
for fmspc in "${TDX[@]}"; do
  fetch_one tdx "$fmspc"
  count=$((count+1))
done
echo "Fetched ${count} fmspcs."
