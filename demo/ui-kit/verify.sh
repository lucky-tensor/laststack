#!/bin/bash
# ============================================================================
# Alien Stack Demo: Verification Gate (fail-closed)
# ============================================================================
# Verifies that required functions carry complete PCF metadata and that
# metadata references resolve to concrete metadata nodes.
#
# Output:
#   - Human-readable summary to stdout
#   - Machine-readable JSON report (default: verification-report.json)
#
# Exit codes:
#   0 = verification pass
#   1 = verification fail
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REPORT_JSON="verification-report.json"

while [ $# -gt 0 ]; do
  case "$1" in
    --json)
      shift
      REPORT_JSON="${1:-$REPORT_JSON}"
      ;;
    *)
      echo "[verify] unknown argument: $1" >&2
      exit 1
      ;;
  esac
  shift || true
done

errors=()
checked_functions=0
passed_functions=0

audit_file="/tmp/alienstack-verify.$$.txt"
: > "$audit_file"

add_error() {
  errors+=("$1")
  echo "ERROR: $1" >> "$audit_file"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

grep_first() {
  local pattern="$1"
  local file="$2"
  grep -E "$pattern" "$file" | head -n 1 || true
}

grep_all() {
  local pattern="$1"
  local file="$2"
  grep -E "$pattern" "$file" || true
}

required_tags=("schema" "toolchain" "pre" "post" "proof" "effects" "bind")

check_required_function() {
  local file="$1"
  local fn="$2"
  local sig

  checked_functions=$((checked_functions + 1))
  sig=$(grep_first "^define .*@${fn}([[:space:]]|\\()" "$file")

  if [ -z "$sig" ]; then
    add_error "$file:$fn missing function definition"
    return
  fi

  local missing=()
  local tag
  for tag in "${required_tags[@]}"; do
    if ! printf '%s\n' "$sig" | grep -E -q "!pcf\\.${tag} ![0-9]+"; then
      missing+=("$tag")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    add_error "$file:$fn missing !pcf.${missing[*]}"
    return
  fi

  passed_functions=$((passed_functions + 1))
  echo "OK: $file:$fn has full PCF coverage" >> "$audit_file"
}

check_metadata_kind_exists() {
  local file="$1"
  local kind="$2"
  local count

  count=$(grep -E -c "^![0-9]+ = !\\{!\"pcf\\.${kind}\"" "$file" || true)
  if [ "${count:-0}" -eq 0 ]; then
    add_error "$file missing metadata definitions for pcf.${kind}"
  fi
}

check_metadata_reference_resolution() {
  local file="$1"
  local line

  while IFS= read -r line; do
    local fn
    fn=$(printf '%s\n' "$line" | sed -nE 's/.*@([A-Za-z_][A-Za-z0-9_.]*).*/\1/p')

    local tag
    for tag in "${required_tags[@]}"; do
      local id
      id=$(printf '%s\n' "$line" | sed -nE "s/.*!pcf\\.${tag} !([0-9]+).*/\\1/p")
      if [ -n "$id" ]; then
        if ! grep -E -q "^!${id} = " "$file"; then
          add_error "$file:$fn references missing metadata node !${id} for pcf.${tag}"
        fi
      fi
    done
  done < <(grep_all "^define .*@" "$file")
}

check_effect_payloads() {
  local file="$1"
  local line

  while IFS= read -r line; do
    if printf '%s\n' "$line" | grep -E -q "effect\\.unknown"; then
      add_error "$file has unresolved effect atom in metadata: $line"
    fi
  done < <(grep_all "^![0-9]+ = !\\{!\"pcf\\.effects\"" "$file")
}

check_module() {
  local file="$1"
  shift
  local funcs=("$@")

  if [ ! -f "$file" ]; then
    add_error "$file missing"
    return
  fi

  local fn
  for fn in "${funcs[@]}"; do
    check_required_function "$file" "$fn"
  done

  local tag
  for tag in "${required_tags[@]}"; do
    check_metadata_kind_exists "$file" "$tag"
  done

  check_metadata_reference_resolution "$file"
  check_effect_payloads "$file"
}

check_module "ir/button.ll" \
  "get_ptr" "init" "on_event"

status="pass"
if [ "${#errors[@]}" -gt 0 ]; then
  status="fail"
fi

timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

{
  echo "{"
  echo "  \"status\": \"$status\"," 
  echo "  \"timestamp\": \"$timestamp\"," 
  echo "  \"checked_functions\": $checked_functions," 
  echo "  \"passed_functions\": $passed_functions," 
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
echo " Alien Stack Verification Gate"
echo "============================================================================"
cat "$audit_file"
echo "----------------------------------------------------------------------------"
echo "status=$status checked_functions=$checked_functions passed_functions=$passed_functions errors=${#errors[@]}"
echo "report=$REPORT_JSON"
echo "============================================================================"

rm -f "$audit_file"

if [ "$status" != "pass" ]; then
  exit 1
fi
