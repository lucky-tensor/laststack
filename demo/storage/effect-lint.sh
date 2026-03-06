#!/bin/bash
# ============================================================================
# LastStack Demo: Structural Effect Lint
# ============================================================================
# Addresses critique W5: validates that each function's declared !pcf.effects
# matches the actual libc/syscall calls present in its IR body.
#
# Strategy:
#   1. Parse ips.ll to extract each function body and its attached !pcf.effects
#      metadata node.
#   2. Scan the function body for 'call' instructions targeting external symbols.
#   3. Map IR call targets to effect atoms (e.g. @pwrite -> libc.pwrite).
#   4. Compare declared vs. observed sets; fail if any observed call is absent
#      from the declared effects.
#
# Note: over-declaration (declaring an effect not called) is a WARNING, not an
# error.  Under-declaration (calling without declaring) is an ERROR.
# Pure functions (!pcf.effects = "pure") must have zero external calls.
#
# Exit codes:
#   0 = lint pass
#   1 = lint fail (undeclared effects found)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

IR_FILE="${1:-ips.ll}"
REPORT_JSON="${2:-effect-lint-report.json}"

if [ ! -f "$IR_FILE" ]; then
    echo "[effect-lint] ERROR: $IR_FILE not found"
    exit 1
fi

# ---- effect atom mapping ---------------------------------------------------
# Map IR external call targets to PCF effect atoms.
# Covers all symbols declared in ips.ll.

effect_atom() {
    case "$1" in
        open|open64)          echo "libc.open"      ;;
        close)                echo "libc.close"     ;;
        pread|pread64)        echo "libc.pread"     ;;
        pwrite|pwrite64)      echo "libc.pwrite"    ;;
        fsync)                echo "libc.fsync"     ;;
        printf)               echo "libc.printf"    ;;
        strcmp)               echo "libc.strcmp"    ;;
        strtoll)              echo "libc.strtoll"   ;;
        malloc)               echo "libc.malloc"    ;;
        free)                 echo "libc.free"      ;;
        memcpy)               echo "libc.memcpy"    ;;
        memset)               echo "libc.memset"    ;;
        exit)                 echo "libc.exit"      ;;
        write)                echo "libc.write"     ;;
        read)                 echo "libc.read"      ;;
        *)                    echo ""               ;;
    esac
}

# ---- parse IR: extract function bodies with their metadata IDs -------------

errors=()
warnings=()
total_fns=0
pass_fns=0

# We process the IR in a single pass using awk.
# State machine:
#   - On 'define ... @name ...' line: record function name and extract metadata IDs
#   - Inside function body: collect call targets
#   - On '}' at column 0: end of function, run lint

run_lint() {
    awk -v ir_file="$IR_FILE" '
    BEGIN {
        in_fn = 0
        fn_name = ""
        effects_node = ""
        call_targets = ""
    }

    # Start of a function definition
    /^define / && /!pcf\.effects/ {
        in_fn = 1
        fn_name = $0
        # Extract function name: find @name
        match($0, /@[A-Za-z_][A-Za-z0-9_]*\(/)
        fn_name = substr($0, RSTART+1, RLENGTH-2)

        # Extract !pcf.effects metadata node ID (e.g. !105)
        match($0, /!pcf\.effects ![0-9]+/)
        if (RSTART > 0) {
            effects_node = substr($0, RSTART+14, RLENGTH-14)
        } else {
            effects_node = ""
        }
        call_targets = ""
        next
    }

    # Also catch define lines that span before we find pcf.effects on same line
    /^define / && !/!pcf\.effects/ {
        in_fn = 1
        fn_name = $0
        match($0, /@[A-Za-z_][A-Za-z0-9_]*\(/)
        fn_name = substr($0, RSTART+1, RLENGTH-2)
        effects_node = ""
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
        # Match call to external (lowercase) symbols
        line = $0
        while (match(line, /@[a-z][A-Za-z0-9_]*/)) {
            sym = substr(line, RSTART+1, RLENGTH-1)
            # Skip internal functions (they start with cmd_, init_, write_, read_, checksum_)
            if (sym !~ /^(cmd_|init_store|write_header|read_header|checksum_for)/) {
                if (call_targets == "") {
                    call_targets = sym
                } else if (index(call_targets, sym) == 0) {
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

# Extract metadata node values: !NNN = !{!"pcf.effects", !"value"}
get_declared_effects() {
    local node_id="$1"
    grep -E "^!${node_id} = " "$IR_FILE" | grep 'pcf\.effects' | \
        sed 's/.*pcf\.effects", !"\([^"]*\)".*/\1/' || echo ""
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

    # Determine observed effect atoms from called symbols
    observed_atoms=()
    if [ -n "$calls_part" ]; then
        for sym in $calls_part; do
            atom=$(effect_atom "$sym")
            if [ -n "$atom" ]; then
                observed_atoms+=("$atom")
            fi
        done
    fi

    # Pure check: if declared == "pure", no external calls allowed
    fn_errors=()
    fn_warnings=()

    if [ "$declared" = "pure" ]; then
        if [ "${#observed_atoms[@]}" -gt 0 ]; then
            fn_errors+=("function is declared pure but calls: ${observed_atoms[*]}")
        fi
    else
        # Check each observed atom is declared
        if [ "${#observed_atoms[@]}" -gt 0 ]; then
            for atom in "${observed_atoms[@]}"; do
                if ! echo "$declared" | grep -qF "$atom"; then
                    fn_errors+=("observed effect '$atom' not declared (declared: $declared)")
                fi
            done
        fi

        # Check each declared atom is observed (warning, not error)
        if [ -n "$declared" ]; then
            IFS=',' read -ra declared_arr <<< "$declared"
            if [ "${#declared_arr[@]}" -gt 0 ]; then
                for decl_atom in "${declared_arr[@]}"; do
                    decl_atom="${decl_atom// /}"  # trim spaces
                    found=false
                    if [ "${#observed_atoms[@]}" -gt 0 ]; then
                        for obs in "${observed_atoms[@]}"; do
                            [ "$obs" = "$decl_atom" ] && { found=true; break; }
                        done
                    fi
                    if ! $found; then
                        fn_warnings+=("declared effect '$decl_atom' not observed in body (may be in callee)")
                    fi
                done
            fi
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
    [ "${#observed_atoms[@]}" -gt 0 ] && obs_str="${observed_atoms[*]}"
    json_entries+=("  {\"fn\": \"$fn_name\", \"status\": \"$status_str\", \"declared\": \"$declared\", \"observed\": \"$obs_str\", \"warnings\": \"$warn_str\"}")

done < <(run_lint)

# ---- emit JSON report ------------------------------------------------------

overall="pass"
[ "${#errors[@]}" -gt 0 ] && overall="fail"

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
echo " LastStack Structural Effect Lint"
echo "============================================================================"
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
