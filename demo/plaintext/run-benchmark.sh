#!/bin/bash
# =============================================================================
# Run TFB plaintext-style wrk bench for a given server
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <label> [port] <command...>"
  exit 1
fi

PLAINTEXT_PORT=18081
LABEL="$1"
shift

SERVER_PORT="$PLAINTEXT_PORT"
if [ "$#" -gt 1 ] && [[ "$1" =~ ^[0-9]+$ ]]; then
  SERVER_PORT="$1"
  shift
fi

CMD=("$@")
if [ "${#CMD[@]}" -eq 0 ]; then
  echo "Usage: $0 <label> [port] <command...>"
  exit 1
fi

LOG_DIR="$SCRIPT_DIR/artifacts"
mkdir -p "$LOG_DIR"
RESULT_FILE="$LOG_DIR/${LABEL}-wrk.csv"
SERVER_LOG="$LOG_DIR/${LABEL}-server.log"
SUMMARY_FILE="$LOG_DIR/benchmark-summary.md"
WRK_CMD="${WRK_CMD:-wrk}"

if ! command -v "$WRK_CMD" >/dev/null 2>&1; then
  echo "wrk not found: tried '$WRK_CMD'. Install wrk or set WRK_CMD to the binary path." >&2
  exit 1
fi

echo "label,concurrency,requests_per_sec,latency_avg" > "$RESULT_FILE"

TFB_URL="http://127.0.0.1:${SERVER_PORT}/plaintext"

start_server() {
  TFB_PORT="$SERVER_PORT" PORT="$SERVER_PORT" "${CMD[@]}" >"$SERVER_LOG" 2>&1 &
  SERVER_PID=$!
  trap 'kill $SERVER_PID 2>/dev/null || true' EXIT
  sleep 1
}

stop_server() {
  kill $SERVER_PID 2>/dev/null || true
  wait $SERVER_PID 2>/dev/null || true
  trap - EXIT
}

run_wrk() {
  local concurrency=$1
  local output_file="$LOG_DIR/${LABEL}-c${concurrency}.txt"
  "$WRK_CMD" -t4 -c${concurrency} -d15s "$TFB_URL" >"$output_file"
  local rps
  local latency
  rps=$(awk '/Requests\/sec/ {print $2}' "$output_file" | tail -n1)
  latency=$(awk '/Latency/ {print $2}' "$output_file" | head -n1)
  printf "%s,%s,%s,%s\n" "$LABEL" "$concurrency" "$rps" "$latency" >> "$RESULT_FILE"
}

wait_for_server() {
  local attempt=0
  local max_attempts=10
  if ! command -v nc >/dev/null 2>&1; then
    echo "nc not found; install netcat so benchmarks can wait for servers" >&2
    stop_server
    exit 1
  fi

  until printf 'GET /plaintext HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n' | nc -w1 127.0.0.1 "$SERVER_PORT" >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "timed out waiting for http://127.0.0.1:${SERVER_PORT}/plaintext to respond" >&2
      stop_server
      exit 1
    fi
    sleep 1
  done
}

init_summary() {
  if [ ! -f "$SUMMARY_FILE" ]; then
    {
      printf "# Benchmark summary\n"
      printf "Generated at %s (UTC)\n\n" "$(date -u +"%Y-%m-%d %H:%M:%SZ")"
    } >"$SUMMARY_FILE"
  fi
}

append_summary() {
  {
    printf "## %s (%s)\n\n" "$LABEL" "$(date -u +"%Y-%m-%d %H:%M:%SZ")"
    printf "| Concurrency | Requests/sec | Latency |\n"
    printf "| --- | --- | --- |\n"
    awk -F, 'NR>1 {printf "| %s | %s | %s |\n", $2, $3, $4}' "$RESULT_FILE"
    printf "\n"
  } | tee -a "$SUMMARY_FILE"
  printf "Benchmark summary appended to %s\n" "$SUMMARY_FILE"
}

init_summary
start_server
wait_for_server
  for conc in 256 1024 4096 16384; do
    echo "[benchmark] $LABEL concurrency=$conc"
    run_wrk "$conc"
  done
stop_server
append_summary
