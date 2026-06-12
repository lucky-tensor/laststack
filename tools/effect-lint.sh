#!/bin/bash
# ============================================================================
# Alien Stack: Structural Effect Lint (shared gate)
# ============================================================================
# Validates that each function's declared !pcf.effects matches the actual
# libc/syscall calls present in its IR body. Works on any Alien Stack IR
# module (storage, plaintext, webserver, ...).
#
# Strategy:
#   1. Parse the IR to extract each function body and its attached
#      !pcf.effects metadata node (single- or multi-line metadata).
#   2. Scan the function body for 'call' instructions targeting external
#      symbols (functions not defined in the module itself).
#   3. Map IR call targets to effect atoms. A symbol may map to several
#      accepted spellings (e.g. @open -> libc.open OR sys.open).
#   4. Compare declared vs. observed sets; fail if any observed call is
#      absent from the declared effects.
#
# Note: over-declaration (declaring an effect not called) is a WARNING, not an
# error.  Under-declaration (calling without declaring) is an ERROR.
# Pure functions (!pcf.effects = "pure") must have zero external calls.
#
# Usage: effect-lint.sh <ir-file> [report.json]
#
# Exit codes:
#   0 = lint pass
#   1 = lint fail (undeclared effects found)
# ============================================================================

set -euo pipefail

IR_FILE="${1:?usage: effect-lint.sh <ir-file> [report.json]}"
REPORT_JSON="${2:-effect-lint-report.json}"

if [ ! -f "$IR_FILE" ]; then
    echo "[effect-lint] ERROR: $IR_FILE not found"
    exit 1
fi

# ---- effect atom mapping ---------------------------------------------------
# Map IR external call targets to accepted PCF effect atoms. Several demos
# use different namespaces for the same call (libc.* vs sys.*); each accepted
# spelling is listed space-separated.

effect_atoms() {
    case "$1" in
        open|open64)          echo "libc.open sys.open"             ;;
        close)                echo "libc.close sys.close"           ;;
        read)                 echo "libc.read sys.read"             ;;
        write)                echo "libc.write sys.write"           ;;
        pread|pread64)        echo "libc.pread sys.pread"           ;;
        pwrite|pwrite64)      echo "libc.pwrite sys.pwrite"         ;;
        fsync)                echo "libc.fsync sys.fsync"           ;;
        socket)               echo "libc.socket sys.socket"         ;;
        setsockopt)           echo "libc.setsockopt sys.setsockopt" ;;
        bind)                 echo "libc.bind sys.bind"             ;;
        listen)               echo "libc.listen sys.listen"         ;;
        accept)               echo "libc.accept sys.accept"         ;;
        fork)                 echo "libc.fork sys.fork"             ;;
        wait)                 echo "libc.wait sys.wait"             ;;
        sysconf)              echo "libc.sysconf"                   ;;
        htons)                echo "libc.htons"                     ;;
        printf)               echo "libc.printf"                    ;;
        snprintf)             echo "libc.snprintf"                  ;;
        strlen)               echo "libc.strlen"                    ;;
        strstr)               echo "libc.strstr"                    ;;
        strcmp)               echo "libc.strcmp"                    ;;
        strtoll)              echo "libc.strtoll"                   ;;
        malloc)               echo "libc.malloc alloc.heap"         ;;
        free)                 echo "libc.free alloc.heap"           ;;
        memcpy)               echo "libc.memcpy"                    ;;
        memset)               echo "libc.memset"                    ;;
        exit)                 echo "libc.exit"                      ;;
        nanosleep)            echo "libc.nanosleep sys.nanosleep"   ;;
        *)                    echo ""                               ;;
    esac
}

# ---- collect module-internal function names ---------------------------------
# Calls to functions defined in this module are skipped: their effects are
# checked at their own definition site (transitive effects may be declared at
# the caller as over-declaration, which is a warning at most).

INTERNAL_FNS="$(grep -E '^define ' "$IR_FILE" \
    | grep -oE '@[A-Za-z_][A-Za-z0-9_]*\(' \
    | sed 's/^@//; s/(//' \
    | tr '\n' ' ')"

# ---- parse IR: extract function bodies with their metadata IDs -------------

errors=()
warnings=()
total_fns=0
pass_fns=0

run_lint() {
    awk -v internal_fns="$INTERNAL_FNS" '
    BEGIN {
        n = split(internal_fns, arr, " ")
        for (i = 1; i <= n; i++) if (arr[i] != "") internal[arr[i]] = 1
        in_fn = 0
        fn_name = ""
        effects_node = ""
        call_targets = ""
    }

    # Start of a function definition
    /^define / {
        in_fn = 1
        match($0, /@[A-Za-z_][A-Za-z0-9_]*\(/)
        fn_name = substr($0, RSTART+1, RLENGTH-2)

        effects_node = ""
        match($0, /!pcf\.effects ![0-9]+/)
        if (RSTART > 0) {
            effects_node = substr($0, RSTART+14, RLENGTH-14)
        }
        call_targets = ""
        next
    }

    # Collect metadata node ID for pcf.effects on define line continuation
    in_fn && /!pcf\.effects/ && effects_node == "" {
        match($0, /!pcf\.effects ![0-9]+/)
        if (RSTART > 0) {
            effects_node = substr($0, RSTART+14, RLENGTH-14)
        }
    }

    # Collect external call targets inside function body
    in_fn && /call .* @[a-z]/ {
        line = $0
        while (match(line, /@[a-z][A-Za-z0-9_]*/)) {
            sym = substr(line, RSTART+1, RLENGTH-1)
            if (!(sym in internal) && sym != "llvm") {
                if (call_targets == "") {
                    call_targets = sym
                } else if (index(" " call_targets " ", " " sym " ") == 0) {
                    call_targets = call_targets " " sym
                }
            }
            line = substr(line, RSTART+RLENGTH)
        }
    }

    # End of function
    in_fn && /^\}/ {
        if (fn_name != "") {
            print "FN:" fn_name ":EFFECTS_NODE:" effects_node ":CALLS:" call_targets
        }
        in_fn = 0
        fn_name = ""
        effects_node = ""
        call_targets = ""
    }
    ' "$IR_FILE"
}

# Extract metadata node value: !NNN = !{!"pcf.effects", !"value"}
# Handles nodes whose value string sits on a continuation line.
get_declared_effects() {
    local node_id="$1"
    awk -v id="$node_id" '
        $0 ~ ("^!" id " = ") { capture = 1; buf = "" }
        capture {
            buf = buf " " $0
            if ($0 ~ /\}/) { print buf; capture = 0 }
        }
    ' "$IR_FILE" | grep 'pcf\.effects' | \
        sed 's/.*pcf\.effects",[[:space:]]*!"\([^"]*\)".*/\1/' || echo ""
}

# ---- main lint loop --------------------------------------------------------

declare -a json_entries

while IFS= read -r line; do
    # Parse: FN:name:EFFECTS_NODE:!NNN:CALLS:sym1 sym2 ...
    fn_name="${line#FN:}"
    fn_name="${fn_name%%:EFFECTS_NODE:*}"

    effects_part="${line#*:EFFECTS_NODE:}"
    effects_node="${effects_part%%:CALLS:*}"

    calls_part="${line#*:CALLS:}"

    total_fns=$((total_fns + 1))

    # Get declared effects for this function
    declared=""
    if [ -n "$effects_node" ]; then
        node_num="${effects_node#!}"
        declared=$(get_declared_effects "$node_num")
    fi

    fn_errors=()
    fn_warnings=()
    observed_str=""

    if [ "$declared" = "pure" ]; then
        if [ -n "$calls_part" ]; then
            fn_errors+=("function is declared pure but calls: $calls_part")
        fi
    else
        # Check each observed external call maps to a declared atom
        if [ -n "$calls_part" ]; then
            for sym in $calls_part; do
                atoms=$(effect_atoms "$sym")
                if [ -z "$atoms" ]; then
                    fn_errors+=("call to '@$sym' has no known effect atom mapping — extend tools/effect-lint.sh")
                    continue
                fi
                matched=false
                for atom in $atoms; do
                    if echo "$declared" | grep -qF "$atom"; then
                        matched=true
                        observed_str="$observed_str $atom"
                        break
                    fi
                done
                if ! $matched; then
                    fn_errors+=("observed effect '${atoms%% *}' (@$sym) not declared (declared: $declared)")
                fi
            done
        fi

        # Check each declared atom is observed (warning, not error).
        # Skip global.*/llvm.* entries, continuation items of global lists
        # (which begin with '@'), and placeholder 'none'.
        if [ -n "$declared" ]; then
            IFS=',' read -ra declared_arr <<< "$declared"
            for decl_atom in "${declared_arr[@]}"; do
                decl_atom="${decl_atom// /}"
                case "$decl_atom" in
                    global.*|llvm.*|@*|none|"") continue ;;
                esac
                found=false
                if [ -n "$calls_part" ]; then
                    for sym in $calls_part; do
                        for atom in $(effect_atoms "$sym"); do
                            [ "$atom" = "$decl_atom" ] && { found=true; break 2; }
                        done
                    done
                fi
                if ! $found; then
                    fn_warnings+=("declared effect '$decl_atom' not observed in body (may be in callee)")
                fi
            done
        fi
    fi

    # Record result
    if [ "${#fn_errors[@]}" -gt 0 ]; then
        for e in "${fn_errors[@]}"; do
            errors+=("@$fn_name: $e")
        done
        status_str="fail"
    else
        pass_fns=$((pass_fns + 1))
        status_str="pass"
    fi

    warn_str=""
    if [ "${#fn_warnings[@]}" -gt 0 ]; then
        warn_str="${fn_warnings[*]}"
        for w in "${fn_warnings[@]}"; do
            warnings+=("@$fn_name: $w")
        done
    fi

    obs_str="none"
    [ -n "$observed_str" ] && obs_str="${observed_str# }"
    json_entries+=("  {\"fn\": \"$fn_name\", \"status\": \"$status_str\", \"declared\": \"$declared\", \"observed\": \"$obs_str\", \"warnings\": \"$warn_str\"}")

done < <(run_lint)

# ---- emit JSON report ------------------------------------------------------

overall="pass"
[ "${#errors[@]}" -gt 0 ] && overall="fail"
if [ "$total_fns" -eq 0 ]; then
    overall="fail"
    errors+=("no function definitions found in $IR_FILE")
fi

timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

{
    echo "{"
    echo "  \"status\": \"$overall\","
    echo "  \"timestamp\": \"$timestamp\","
    echo "  \"ir_file\": \"$IR_FILE\","
    echo "  \"functions_total\": $total_fns,"
    echo "  \"functions_passed\": $pass_fns,"
    echo "  \"error_count\": ${#errors[@]},"
    echo "  \"warning_count\": ${#warnings[@]},"
    echo "  \"functions\": ["
    for idx in "${!json_entries[@]}"; do
        if [ "$idx" -lt $((${#json_entries[@]} - 1)) ]; then
            echo "${json_entries[$idx]},"
        else
            echo "${json_entries[$idx]}"
        fi
    done
    echo "  ]"
    echo "}"
} > "$REPORT_JSON"

echo "============================================================================"
echo " Alien Stack Structural Effect Lint"
echo "============================================================================"
echo "ir_file=$IR_FILE"
echo "status=$overall functions_total=$total_fns functions_passed=$pass_fns errors=${#errors[@]} warnings=${#warnings[@]}"
echo "report=$REPORT_JSON"
if [ "${#errors[@]}" -gt 0 ]; then
    echo "ERRORS:"
    printf '  %s\n' "${errors[@]}"
fi
if [ "${#warnings[@]}" -gt 0 ]; then
    echo "WARNINGS (over-declaration — may be inherited from callees):"
    printf '  %s\n' "${warnings[@]}"
fi
echo "============================================================================"

[ "$overall" = "pass" ]
