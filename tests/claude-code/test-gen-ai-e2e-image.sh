#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

# This test drives a clean session through the full gen-ai flow.
# It uses claude -p with multi-turn input via a scripted interaction.

PROJECT_DIR=$(create_test_project)
cd "$PROJECT_DIR"

# Turn 1: trigger gen-ai intent
out1=$(run_claude "Imagen cyberpunk de un gato neón, formato cuadrado, una sola variante." 180)

assert_contains "$out1" "discovering" "Turn 1 should reference discovering"
assert_contains "$out1" "context-bundle" "Turn 1 should produce context-bundle.json"

# Verify filesystem state
ls gen-ai-projects/*/context-bundle.json >/dev/null || {
    echo "[FAIL] context-bundle.json not created"; exit 1;
}

# Turn 2: approve the brief (run after the agent asks)
# This step is interactive; for the headless test we simulate by checking
# that the agent reaches brainstorming-gen-ai and asks an aspect-ratio question.
assert_contains "$out1" "aspect" "Turn 1 chain should reach brainstorming with aspect question"

echo "[PASS] E2E image flow reaches brief stage."
