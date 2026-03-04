#!/bin/bash
# ============================================================================
# LastStack Demo: Link Gate (fail-closed)
# ============================================================================
# Consumes verifier output and enforces basic interface compatibility on
# internal call edges across gate-controlled functions.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VERIFY_REPORT="verification-report.json"
LINK_REPORT="link-gate-report.json"

while [ $# -gt 0 ]; do
  case "$1" in
    --verify-report)
      shift
      VERIFY_REPORT="${1:-$VERIFY_REPORT}"
      ;;
    --json)
      shift
      LINK_REPORT="${1:-$LINK_REPORT}"
      ;;
    *)
      echo "[link-gate] unknown argument: $1" >&2
      exit 1
      ;;
  esac
  shift || true
done

errors=()
accepted=0
rejected=0

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

add_error() {
  errors+=("$1")
}

if [ ! -f "$VERIFY_REPORT" ]; then
  add_error "missing verifier report: $VERIFY_REPORT"
else
  if ! rg -q '"status"\s*:\s*"pass"' "$VERIFY_REPORT"; then
    add_error "verifier report is not pass: $VERIFY_REPORT"
  fi
fi

gated_fns="build_response read_file get_content_type check_invariants load_assets handle_client main generate_fractal get_buffer get_buffer_size free_buffer"

is_gated() {
  case " $gated_fns " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

has_full_pcf_signature() {
  local file="$1"
  local fn="$2"
  local sig
  sig=$(rg -N "^define .*@${fn}\\b" "$file" | head -n 1 || true)
  if [ -z "$sig" ]; then
    return 1
  fi
  local tag
  for tag in schema toolchain pre post proof effects bind; do
    if ! printf '%s\n' "$sig" | rg -q "!pcf\\.${tag} ![0-9]+"; then
      return 1
    fi
  done
  return 0
}

effect_is_known() {
  local file="$1"
  local fn="$2"
  local sig id effect_line

  sig=$(rg -N "^define .*@${fn}\\b" "$file" | head -n 1 || true)
  id=$(printf '%s\n' "$sig" | sed -nE 's/.*!pcf\.effects !([0-9]+).*/\1/p')
  if [ -z "$id" ]; then
    return 1
  fi

  effect_line=$(rg -N "^!${id} = !\{!\"pcf\.effects\"" "$file" | head -n 1 || true)
  if [ -z "$effect_line" ]; then
    return 1
  fi

  if printf '%s\n' "$effect_line" | rg -q "effect\.unknown"; then
    return 1
  fi

  return 0
}

collect_edges() {
  local file="$1"
  awk '
    /^define / {
      fn=""
      if (match($0, /@[A-Za-z_][A-Za-z0-9_.]*/)) {
        fn = substr($0, RSTART + 1, RLENGTH - 1)
      }
      current = fn
      next
    }
    / call / {
      if (current == "") next
      line = $0
      while (match(line, /@[A-Za-z_][A-Za-z0-9_.]*/)) {
        callee = substr(line, RSTART + 1, RLENGTH - 1)
        print current " " callee
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$file" | sort -u
}

for file in server.ll fractal.ll; do
  while IFS= read -r edge; do
    [ -z "$edge" ] && continue
    caller="${edge%% *}"
    callee="${edge##* }"

    if ! is_gated "$caller" || ! is_gated "$callee"; then
      continue
    fi

    if ! has_full_pcf_signature "$file" "$caller"; then
      rejected=$((rejected + 1))
      add_error "$file edge ${caller}->${callee} rejected: caller missing full PCF signature"
      continue
    fi

    if ! has_full_pcf_signature "$file" "$callee"; then
      rejected=$((rejected + 1))
      add_error "$file edge ${caller}->${callee} rejected: callee missing full PCF signature"
      continue
    fi

    if ! effect_is_known "$file" "$callee"; then
      rejected=$((rejected + 1))
      add_error "$file edge ${caller}->${callee} rejected: callee effect metadata unresolved"
      continue
    fi

    accepted=$((accepted + 1))
  done < <(collect_edges "$file")
done

status="pass"
if [ "${#errors[@]}" -gt 0 ]; then
  status="fail"
fi

timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

{
  echo "{"
  echo "  \"status\": \"$status\"," 
  echo "  \"timestamp\": \"$timestamp\"," 
  echo "  \"accepted_edges\": $accepted," 
  echo "  \"rejected_edges\": $rejected," 
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
} > "$LINK_REPORT"

echo "============================================================================"
echo " LastStack Link Gate"
echo "============================================================================"
echo "status=$status accepted_edges=$accepted rejected_edges=$rejected errors=${#errors[@]}"
echo "report=$LINK_REPORT"
if [ "${#errors[@]}" -gt 0 ]; then
  printf '%s\n' "${errors[@]}"
fi
echo "============================================================================"

if [ "$status" != "pass" ]; then
  exit 1
fi
