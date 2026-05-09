#!/usr/bin/env bash
# Test: Does the bootstrap route gen-ai vs code intent correctly?
# Framework: RED-GREEN per testing-skills-with-subagents.md

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Provide a portable `timeout` shim if the system lacks one (e.g. stock macOS).
# test-helpers.sh's run_claude depends on `timeout`; we install a perl-based
# fallback into a temp dir on PATH so the shared helper is untouched.
if ! command -v timeout >/dev/null 2>&1; then
    if command -v gtimeout >/dev/null 2>&1; then
        TIMEOUT_SHIM_DIR="$(mktemp -d)"
        ln -s "$(command -v gtimeout)" "$TIMEOUT_SHIM_DIR/timeout"
    elif command -v perl >/dev/null 2>&1; then
        TIMEOUT_SHIM_DIR="$(mktemp -d)"
        cat > "$TIMEOUT_SHIM_DIR/timeout" <<'SHIM'
#!/usr/bin/env perl
# Minimal `timeout SECONDS CMD ARGS...` shim using perl's alarm.
use strict; use warnings;
my $secs = shift @ARGV;
die "usage: timeout SECONDS CMD ...\n" unless defined $secs and @ARGV;
my $pid = fork();
die "fork: $!" unless defined $pid;
if ($pid == 0) { exec @ARGV or die "exec: $!"; }
local $SIG{ALRM} = sub { kill 'TERM', $pid; sleep 2; kill 'KILL', $pid; exit 124; };
alarm $secs;
waitpid $pid, 0;
exit($? >> 8);
SHIM
        chmod +x "$TIMEOUT_SHIM_DIR/timeout"
    else
        echo "error: 'timeout' missing and no fallback ('gtimeout' or 'perl') available" >&2
        exit 127
    fi
    export PATH="$TIMEOUT_SHIM_DIR:$PATH"
    trap 'rm -rf "$TIMEOUT_SHIM_DIR"' EXIT
fi

source "$SCRIPT_DIR/test-helpers.sh"

PHASE="${1:-red}"

GEN_AI_PROMPT='Quiero un video cyberpunk corto de un gato neón.'
CODE_PROMPT='Build me a React todo list with localStorage.'

if [ "$PHASE" = "red" ]; then
    echo "--- RED: bootstrap not yet written; agent should NOT mention discovering ---"
    out_genai=$(run_claude "$GEN_AI_PROMPT" 90)
    out_code=$(run_claude "$CODE_PROMPT" 90)

    if echo "$out_genai" | grep -qi "discovering"; then
        echo "[UNEXPECTED] Agent mentioned discovering without bootstrap."
        exit 1
    fi
    echo "[OK] RED baseline: no discovering reference yet."
fi

if [ "$PHASE" = "green" ]; then
    echo "--- GREEN: bootstrap installed; gen-ai prompt activates discovering ---"
    out_genai=$(run_claude "$GEN_AI_PROMPT" 120)
    out_code=$(run_claude "$CODE_PROMPT" 120)

    assert_contains "$out_genai" "discovering" "gen-ai prompt should activate discovering"
    assert_contains "$out_code" "brainstorming" "code prompt should activate core brainstorming"
    if echo "$out_code" | grep -qi "discovering"; then
        echo "[FAIL] Code prompt incorrectly activated discovering."
        exit 1
    fi
    echo "[PASS] Routing works: gen-ai → discovering, code → brainstorming."
fi
