#!/bin/bash
# ============================================================================
# Alien Stack Webserver Demo: Behavioral Evidence Gate
# ============================================================================
# Runs the built webserver and validates observable behavior against the spec:
#   1. GET /              -> 200 with the Alien Stack HTML page
#   2. GET /fractal.wasm  -> 200 with a valid WASM module (\0asm magic)
#   3. GET /nonexistent   -> 404
#   4. routing regression: a path merely *containing* ".wasm" must not be
#      served as the WASM module (guards against substring matching)
#   5. oversized request (> request buffer) does not crash the server
#   6. server process is still alive after the above
#
# Usage: webserver-evidence.sh [--bin ./alienstack-server] [--json report.json]
#
# Exit codes: 0 = all checks pass, 1 = at least one check failed
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BIN="./alienstack-server"
REPORT_JSON="webserver-evidence-report.json"
PORT=9090
HOST=127.0.0.1

while [ $# -gt 0 ]; do
    case "$1" in
        --bin)  BIN="$2";         shift 2 ;;
        --json) REPORT_JSON="$2"; shift 2 ;;
        *) echo "[webserver-evidence] unknown arg: $1"; exit 1 ;;
    esac
done

if [ ! -x "$BIN" ]; then
    echo "[webserver-evidence] ERROR: binary missing or not executable: $BIN"
    exit 1
fi

SERVER_PID=""
cleanup() {
    if [ -n "$SERVER_PID" ]; then
        # the server forks workers; kill the process group
        kill -- -"$SERVER_PID" 2>/dev/null || kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

setsid "$BIN" > webserver-evidence.log 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 50); do
    if curl -s -o /dev/null --max-time 1 "http://$HOST:$PORT/" 2>/dev/null; then
        break
    fi
    sleep 0.1
done

checks_total=0
checks_passed=0
declare -a results_json

record() {
    local name="$1" ok="$2" detail="$3"
    local status_word
    checks_total=$((checks_total + 1))
    if [ "$ok" = "true" ]; then
        checks_passed=$((checks_passed + 1))
        status_word="pass"
        echo "[webserver-evidence] PASS  $name"
    else
        status_word="fail"
        echo "[webserver-evidence] FAIL  $name — $detail"
    fi
    results_json+=("  {\"check\": \"$name\", \"status\": \"$status_word\", \"detail\": \"$detail\"}")
}

# ---- check 1: index page ----------------------------------------------------
index_resp="$(curl -s -i --max-time 5 "http://$HOST:$PORT/" || true)"
if echo "$index_resp" | head -1 | grep -q "200" \
   && echo "$index_resp" | grep -q "<title>Alien Stack"; then
    record "index_200_html" true "200 with Alien Stack HTML"
else
    record "index_200_html" false "unexpected: $(echo "$index_resp" | head -1)"
fi

# ---- check 2: wasm module ---------------------------------------------------
curl -s --max-time 5 "http://$HOST:$PORT/fractal.wasm" -o /tmp/evidence-fractal.$$.wasm || true
wasm_magic="$(head -c 4 /tmp/evidence-fractal.$$.wasm 2>/dev/null | od -An -tx1 | tr -d ' \n')"
rm -f /tmp/evidence-fractal.$$.wasm
if [ "$wasm_magic" = "0061736d" ]; then
    record "fractal_wasm_served" true "valid wasm magic"
else
    record "fractal_wasm_served" false "bad magic: $wasm_magic"
fi

# ---- check 3: 404 for unknown path -------------------------------------------
notfound_status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://$HOST:$PORT/nonexistent" || true)"
if [ "$notfound_status" = "404" ]; then
    record "unknown_path_404" true "404 returned"
else
    record "unknown_path_404" false "status: $notfound_status"
fi

# ---- check 4: substring routing regression ------------------------------------
# A request whose path merely contains ".wasm" must NOT be served the module.
sub_resp="$(curl -s -i --max-time 5 "http://$HOST:$PORT/notreally.wasm.txt" || true)"
sub_status="$(echo "$sub_resp" | head -1 | grep -oE '[0-9]{3}' | head -1)"
if [ "$sub_status" = "404" ]; then
    record "wasm_substring_not_matched" true "404 for /notreally.wasm.txt"
else
    record "wasm_substring_not_matched" false "status $sub_status for /notreally.wasm.txt (substring routing bug)"
fi

# ---- check 5: oversized request does not kill the server ----------------------
big_path="$(printf 'A%.0s' $(seq 1 4096))"
curl -s -o /dev/null --max-time 5 "http://$HOST:$PORT/$big_path" 2>/dev/null || true
after_status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://$HOST:$PORT/" || true)"
if [ "$after_status" = "200" ]; then
    record "oversized_request_survived" true "server healthy after 4KB request line"
else
    record "oversized_request_survived" false "server unhealthy after oversized request (status: $after_status)"
fi

# ---- check 6: server alive ----------------------------------------------------
if kill -0 "$SERVER_PID" 2>/dev/null; then
    record "server_alive_after_abuse" true "pid $SERVER_PID alive"
else
    record "server_alive_after_abuse" false "server process exited"
fi

# ---- emit JSON report ----------------------------------------------------------
status="pass"
[ "$checks_passed" -lt "$checks_total" ] && status="fail"
timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

{
    echo "{"
    echo "  \"status\": \"$status\","
    echo "  \"timestamp\": \"$timestamp\","
    echo "  \"checks_total\": $checks_total,"
    echo "  \"checks_passed\": $checks_passed,"
    echo "  \"checks\": ["
    for idx in "${!results_json[@]}"; do
        if [ "$idx" -lt $((${#results_json[@]} - 1)) ]; then
            echo "${results_json[$idx]},"
        else
            echo "${results_json[$idx]}"
        fi
    done
    echo "  ]"
    echo "}"
} > "$REPORT_JSON"

echo "============================================================================"
echo " Alien Stack Webserver Behavioral Evidence"
echo "============================================================================"
echo "status=$status checks_total=$checks_total checks_passed=$checks_passed"
echo "report=$REPORT_JSON"
echo "============================================================================"

[ "$status" = "pass" ]
