#!/bin/bash
# ============================================================================
# LastStack Demo: Artifact Sealing
# ============================================================================
# Emits a manifest with content digests, verification outputs, and scoped
# TCB tool records for reproducibility and audit.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OUT_PATH="artifacts/manifest.json"
VERIFY_REPORT="verification-report.json"
LINK_REPORT="link-gate-report.json"
IPS_REPORT="ips-report.json"

while [ $# -gt 0 ]; do
  case "$1" in
    --out)
      shift
      OUT_PATH="${1:-$OUT_PATH}"
      ;;
    --verify-report)
      shift
      VERIFY_REPORT="${1:-$VERIFY_REPORT}"
      ;;
    --link-report)
      shift
      LINK_REPORT="${1:-$LINK_REPORT}"
      ;;
    --ips-report)
      shift
      IPS_REPORT="${1:-$IPS_REPORT}"
      ;;
    *)
      echo "[seal] unknown argument: $1" >&2
      exit 1
      ;;
  esac
  shift || true
done

mkdir -p "$(dirname "$OUT_PATH")"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

sha256_file() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "missing"
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
    return
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return
  fi

  echo "unavailable"
}

tool_version() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "not-found"
    return
  fi

  case "$tool" in
    bash)
      bash --version 2>/dev/null | head -n 1 || echo "unknown"
      ;;
    *)
      "$tool" --version 2>/dev/null | head -n 1 || echo "unknown"
      ;;
  esac
}

tool_path() {
  local tool="$1"
  command -v "$tool" 2>/dev/null || echo "not-found"
}

tool_hash() {
  local path="$1"
  if [ "$path" = "not-found" ] || [ ! -f "$path" ]; then
    echo "missing"
    return
  fi
  sha256_file "$path"
}

record_file_json() {
  local label="$1"
  local file="$2"
  local hash
  hash=$(sha256_file "$file")
  printf '    "%s": {"path": "%s", "sha256": "%s"}' \
    "$(json_escape "$label")" "$(json_escape "$file")" "$(json_escape "$hash")"
}

timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
commit_sha="$(git rev-parse --verify HEAD 2>/dev/null || echo unknown)"

tools=("bash" "clang" "llvm-as" "opt" "llc" "wasm-ld" "z3" "cvc5" "jq")

{
  echo "{"
  echo "  \"schema\": \"laststack.artifact.v1\"," 
  echo "  \"timestamp\": \"$timestamp\"," 
  echo "  \"git_commit\": \"$commit_sha\"," 
  echo "  \"artifacts\": {"
  record_file_json "server_ll" "server.ll"; echo ","
  record_file_json "fractal_ll" "fractal.ll"; echo ","
  record_file_json "ips_ll" "ips.ll"; echo ","
  record_file_json "index_html" "public/index.html"; echo ","
  record_file_json "fractal_wasm" "public/fractal.wasm"; echo ","
  record_file_json "server_bin" "laststack-server"; echo ","
  record_file_json "ips_bin" "laststack-ips"; echo ","
  record_file_json "verify_report" "$VERIFY_REPORT"; echo ","
  record_file_json "link_report" "$LINK_REPORT"; echo ","
  record_file_json "ips_report" "$IPS_REPORT"; echo ""
  echo "  },"
  echo "  \"tcb\": ["

  i=0
  for tool in "${tools[@]}"; do
    i=$((i + 1))
    path=$(tool_path "$tool")
    version=$(tool_version "$tool")
    hash=$(tool_hash "$path")

    printf '    {"tool":"%s","path":"%s","version":"%s","sha256":"%s"}' \
      "$(json_escape "$tool")" \
      "$(json_escape "$path")" \
      "$(json_escape "$version")" \
      "$(json_escape "$hash")"

    if [ "$i" -lt "${#tools[@]}" ]; then
      echo ","
    else
      echo ""
    fi
  done

  echo "  ]"
  echo "}"
} > "$OUT_PATH"

echo "[seal] wrote $OUT_PATH"
