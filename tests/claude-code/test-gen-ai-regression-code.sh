#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

out=$(run_claude "Build a React todo list with localStorage persistence." 90)

assert_contains "$out" "brainstorming" "code prompt should activate brainstorming"

if echo "$out" | grep -qi "discovering"; then
    echo "[FAIL] Code prompt incorrectly activated discovering."
    exit 1
fi

if echo "$out" | grep -qi "higgsfield"; then
    echo "[FAIL] Code prompt mentioned Higgsfield."
    exit 1
fi

echo "[PASS] Code track unaffected by gen-ai bootstrap."
