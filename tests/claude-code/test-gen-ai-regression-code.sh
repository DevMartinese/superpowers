#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

out=$(run_claude "Build a React todo list with localStorage persistence." 180)

# Negative guards: the gen-ai bootstrap must NOT cross-activate on a code prompt.
# (Plan also asserted out contains "brainstorming", but the core
#  using-superpowers skill teaches a behavioral pattern the agent applies
#  without naming it — that literal-string check fails even when routing
#  is working correctly. Mirrors the iteration applied to the GREEN gate.)

if echo "$out" | grep -qi "discovering"; then
    echo "[FAIL] Code prompt incorrectly activated discovering."
    exit 1
fi

if echo "$out" | grep -qi "higgsfield"; then
    echo "[FAIL] Code prompt mentioned Higgsfield."
    exit 1
fi

if echo "$out" | grep -qi "gen-ai:"; then
    echo "[FAIL] Code prompt referenced a /gen-ai: skill."
    exit 1
fi

echo "[PASS] Code track unaffected by gen-ai bootstrap."
