#!/bin/bash
# ============================================================================
# LastStack Demo: IPS Evidence Gate
# ============================================================================
# Runs a deterministic scenario against laststack-ips and emits a JSON report.
#
# Exit codes:
#   0 = evidence pass
#   1 = evidence fail
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

IPS_BIN="./laststack-ips"
REPORT_JSON="ips-report.json"

while [ $# -gt 0 ]; do
  case "$1" in
    --bin)
      shift
      IPS_BIN="${1:-$IPS_BIN}"
      ;;
    --json)
      shift
      REPORT_JSON="${1:-$REPORT_JSON}"
      ;;
    *)
      echo "[ips-evidence] unknown argument: $1" >&2
      exit 1
      ;;
  esac
  shift || true
done

errors=()
checks_total=0
checks_passed=0

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

add_error() {
  errors+=("$1")
}

run_expect_success() {
  local name="$1"
  local expect="$2"
  shift 2

  checks_total=$((checks_total + 1))

  local output
  if output=$("$@" 2>&1); then
    if printf '%s\n' "$output" | rg -q "$expect"; then
      checks_passed=$((checks_passed + 1))
    else
      add_error "$name: output mismatch (expected /$expect/), got: $output"
    fi
  else
    add_error "$name: command failed: $*"
  fi
}

run_expect_failure() {
  local name="$1"
  shift

  checks_total=$((checks_total + 1))

  if "$@" >/tmp/laststack-ips-fail.$$ 2>&1; then
    local out
    out=$(cat /tmp/laststack-ips-fail.$$)
    rm -f /tmp/laststack-ips-fail.$$
    add_error "$name: expected failure but command succeeded; output: $out"
  else
    rm -f /tmp/laststack-ips-fail.$$ || true
    checks_passed=$((checks_passed + 1))
  fi
}

if [ ! -x "$IPS_BIN" ]; then
  add_error "missing executable IPS binary: $IPS_BIN"
fi

tmp_dir="$(mktemp -d /tmp/laststack-ips-evidence.XXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT
state_path="$tmp_dir/state.bin"

if [ "${#errors[@]}" -eq 0 ]; then
  run_expect_success "init" "ips:init epoch=0 value=0" "$IPS_BIN" "$state_path" init
  run_expect_success "add+5" "ips:add delta=5 epoch=1 value=5" "$IPS_BIN" "$state_path" add 5
  run_expect_success "recover-1" "ips:state epoch=1 value=5 committed=1" "$IPS_BIN" "$state_path" recover

  run_expect_success "add-2" "ips:add delta=-2 epoch=2 value=3" "$IPS_BIN" "$state_path" add -2
  run_expect_success "recover-2" "ips:state epoch=2 value=3 committed=1" "$IPS_BIN" "$state_path" recover

  run_expect_success "corrupt" "ips:corrupt wrote_uncommitted_header" "$IPS_BIN" "$state_path" corrupt
  run_expect_failure "recover-after-corrupt" "$IPS_BIN" "$state_path" recover
fi

status="pass"
if [ "${#errors[@]}" -gt 0 ]; then
  status="fail"
fi

timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

{
  echo "{"
  echo "  \"status\": \"$status\"," 
  echo "  \"timestamp\": \"$timestamp\"," 
  echo "  \"ips_binary\": \"$(json_escape "$IPS_BIN")\"," 
  echo "  \"checks_total\": $checks_total," 
  echo "  \"checks_passed\": $checks_passed," 
  echo "  \"error_count\": ${#errors[@]},"
  echo "  \"errors\": ["

  if [ "${#errors[@]}" -gt 0 ]; then
    i=0
    for err in "${errors[@]}"; do
      i=$((i + 1))
      escaped=$(json_escape "$err")
      if [ "$i" -lt "${#errors[@]}" ]; then
        echo "    \"$escaped\"," 
      else
        echo "    \"$escaped\""
      fi
    done
  fi

  echo "  ]"
  echo "}"
} > "$REPORT_JSON"

echo "============================================================================"
echo " LastStack IPS Evidence"
echo "============================================================================"
echo "status=$status checks_total=$checks_total checks_passed=$checks_passed errors=${#errors[@]}"
echo "report=$REPORT_JSON"
if [ "${#errors[@]}" -gt 0 ]; then
  printf '%s\n' "${errors[@]}"
fi
echo "============================================================================"

if [ "$status" != "pass" ]; then
  exit 1
fi
