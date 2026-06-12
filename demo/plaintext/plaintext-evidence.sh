#!/bin/bash
# ============================================================================
# Alien Stack Plaintext Demo: Behavioral Evidence Gate
# ============================================================================
# Runs the built plaintext server and validates observable behavior against
# the spec claims:
#   1. responds 200 "Hello, World!" with Content-Length: 13
#   2. responds to a request with a non-HTTP (garbage) payload
#   3. responds to an empty request line
#   4. survives a burst of concurrent requests
#   5. server process is still alive after malformed input
#
# Usage: plaintext-evidence.sh [--bin ./alienstack-plaintext] [--json report.json]
#
# Exit codes: 0 = all checks pass, 1 = at least one check failed
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BIN="./alienstack-plaintext"
REPORT_JSON="plaintext-evidence-report.json"
PORT=18081
HOST=127.0.0.1

while [ $# -gt 0 ]; do
    case "$1" in
        --bin)  BIN="$2";         shift 2 ;;
        --json) REPORT_JSON="$2"; shift 2 ;;
        *) echo "[plaintext-evidence] unknown arg: $1"; exit 1 ;;
    esac
done

if [ ! -x "$BIN" ] && [ ! -f "$BIN" ]; then
    echo "[plaintext-evidence] ERROR: binary not found: $BIN"
    exit 1
fi

SERVER_PID=""
cleanup() {
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

"$BIN" &
SERVER_PID=$!

# Wait for the port to accept connections
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
    checks_total=$((checks_total + 1))
    if [ "$ok" = "true" ]; then
        checks_passed=$((checks_passed + 1))
        echo "[plaintext-evidence] PASS  $name"
    else
        echo "[plaintext-evidence] FAIL  $name — $detail"
    fi
    results_json+=("  {\"check\": \"$name\", \"status\": \"$([ "$ok" = "true" ] && echo pass || echo fail)\", \"detail\": \"$detail\"}")
}

# ---- check 1: correct payload and headers ----------------------------------
resp_headers="$(curl -s -i --max-time 5 "http://$HOST:$PORT/plaintext" || true)"
if echo "$resp_headers" | head -1 | grep -q "200 OK" \
   && echo "$resp_headers" | grep -qi "Content-Length: 13" \
   && echo "$resp_headers" | grep -q "Hello, World!"; then
    record "http_200_hello_world" true "200 OK, Content-Length 13, body Hello, World!"
else
    record "http_200_hello_world" false "unexpected response: $(echo "$resp_headers" | head -1)"
fi

# ---- check 2: garbage (non-HTTP) request still gets a response --------------
garbage_resp="$(printf '\x01\x02\x03garbage\r\n\r\n' | timeout 5 bash -c "exec 3<>/dev/tcp/$HOST/$PORT; cat >&3; cat <&3" 2>/dev/null || true)"
if echo "$garbage_resp" | grep -q "Hello, World!"; then
    record "garbage_request_handled" true "server responded to non-HTTP payload"
else
    record "garbage_request_handled" false "no response to garbage payload"
fi

# ---- check 3: empty request -------------------------------------------------
empty_resp="$(printf '\r\n' | timeout 5 bash -c "exec 3<>/dev/tcp/$HOST/$PORT; cat >&3; cat <&3" 2>/dev/null || true)"
if echo "$empty_resp" | grep -q "Hello, World!"; then
    record "empty_request_handled" true "server responded to empty request"
else
    record "empty_request_handled" false "no response to empty request"
fi

# ---- check 4: concurrent burst ----------------------------------------------
burst_n=50
burst_file=/tmp/plaintext-burst.$$
: > "$burst_file"
burst_pids=()
for i in $(seq 1 "$burst_n"); do
    ( curl -s --max-time 10 "http://$HOST:$PORT/" | grep -q "Hello, World!" && echo ok >> "$burst_file" ) &
    burst_pids+=($!)
done
for pid in "${burst_pids[@]}"; do
    wait "$pid" 2>/dev/null || true
done
burst_ok=$(grep -c ok "$burst_file" 2>/dev/null || echo 0)
rm -f "$burst_file"
if [ "$burst_ok" -eq "$burst_n" ]; then
    record "concurrent_burst" true "$burst_ok/$burst_n requests served"
else
    record "concurrent_burst" false "only $burst_ok/$burst_n requests served"
fi

# ---- check 5: server still alive after the above ----------------------------
if kill -0 "$SERVER_PID" 2>/dev/null; then
    record "server_alive_after_abuse" true "pid $SERVER_PID alive"
else
    record "server_alive_after_abuse" false "server process exited"
fi

# ---- emit JSON report --------------------------------------------------------
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
echo " Alien Stack Plaintext Behavioral Evidence"
echo "============================================================================"
echo "status=$status checks_total=$checks_total checks_passed=$checks_passed"
echo "report=$REPORT_JSON"
echo "============================================================================"

[ "$status" = "pass" ]
