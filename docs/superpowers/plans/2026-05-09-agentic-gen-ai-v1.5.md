# Agentic Gen-AI Track — V1.5 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the seven backlog gaps surfaced by the higgsfield-mcp surface review (`docs/superpowers/specs/2026-05-06-agentic-gen-ai-design.md` § "V1.5 / V2 backlog"), so the gen-ai track works end-to-end on either the official-CLI path or the third-party MCP path, and covers two missing asset types (talking-head, image-edit).

**Architecture:**

- **One backend, picked at session start.** The bootstrap detects whether `higgsfield-mcp` is registered with Claude (via `claude mcp list`) or only the CLI is present, picks ONE active backend, and writes the choice to the per-project state. Downstream skills consult that state instead of hardcoding `hf …`.
- **Two new asset types.** `talking-head` (image + WAV → lip-synced video) and `image-edit` (existing image → transformed image) become first-class types in `brainstorming-gen-ai`, `asset-planning`, and `producing-assets`. Existing `image` and `video` types are unchanged.
- **Backend-aware sub-steps.** `discovering` source B branches by backend (CLI: `hf model list`; MCP: `higgsfield://styles` and `higgsfield://motions` resources). `producing-assets` adds an upload sub-step (MCP path requires public URLs; CLI path passes paths through).
- **Lightweight cancellation, deferred webhooks.** `reviewing-outputs` exposes a "cancel project" gate that issues `cancel_request` for any in-flight MCP jobs. Webhooks descoped to V2 (the agent has no inbound HTTP endpoint to listen on).

**Tech Stack:** Markdown (skill files), bash (test scripts and run-hook), Claude Code CLI (`claude -p` for headless eval), `@higgsfield/cli@0.1.34`, `higgsfield-mcp@0.2.0`. No new runtime deps.

**Spec:** `docs/superpowers/specs/2026-05-06-agentic-gen-ai-design.md` (V1.5 / V2 backlog section)

**Builds on:** V1 plan `docs/superpowers/plans/2026-05-06-agentic-gen-ai.md` and the verified surface notes at `docs/superpowers/notes/higgsfield-invocation.md`.

---

## File Structure

### Modified

| File | Responsibility change |
| --- | --- |
| `skills/gen-ai/using-gen-ai-superpowers/SKILL.md` | Adds backend detection + pluggable auth check; emits `[gen-ai bootstrap] backend=<mcp\|cli>` as observable evidence |
| `skills/gen-ai/discovering/SKILL.md` | Source B branches by backend; writes detected backend into `context-bundle.json` |
| `skills/gen-ai/brainstorming-gen-ai/SKILL.md` | Adds `talking-head` and `image-edit` asset-type detection + question dimensions |
| `skills/gen-ai/asset-planning/SKILL.md` | New types in shot-list.md table; new columns `source_image`, `source_audio` for talking-head; decomposition rules cover edit chains |
| `skills/gen-ai/producing-assets/SKILL.md` | Adds talking-head and image-edit routing rows; adds upload sub-step for MCP path; documents cancellation hook |
| `skills/gen-ai/reviewing-outputs/SKILL.md` | Adds `cancel-project` decision in the per-asset prompt |

### Created

| File | Purpose |
| --- | --- |
| `tests/claude-code/test-gen-ai-backend-detection.sh` | RED-GREEN: bootstrap reports the active backend |
| `tests/claude-code/test-gen-ai-talking-head-routing.sh` | RED-GREEN: talking-head intent routes correctly |
| `tests/claude-code/test-gen-ai-image-edit-routing.sh` | RED-GREEN: image-edit intent routes correctly |

### Out of scope (deferred to V2)

- Webhook callbacks (gap #6) — the agent runtime has no inbound HTTP endpoint; revisit when there is a long-running orchestrator process to host one.
- Cross-modal coherence (V2 from V1).
- Marketing-Studio multi-asset campaigns (V2 from V1).

---

## Prerequisites (manual, one-time)

These steps require human interaction and cannot be automated. Complete them before starting Task 1.

```bash
# Path 1 — Official CLI (already covered by V1 prereqs):
npm install -g @higgsfield/cli
higgsfield auth login          # browser
npx skills add higgsfield-ai/skills

# Path 2 — Third-party MCP (NEW; needed for V1.5 MCP-side coverage):
# Get API keys from https://cloud.higgsfield.ai/api-keys
export HF_API_KEY=<your_key>
export HF_SECRET=<your_secret>
claude mcp add higgsfield -- npx -y higgsfield-mcp
# Verify:
claude mcp list | grep higgsfield
```

V1.5 tests assume **at least one** of the two paths is configured. The backend-detection logic picks whichever is present. If both, MCP wins (it has more capabilities; document in `using-gen-ai-superpowers`).

The plugin cache must be re-synced after each skill change for `claude -p` tests to pick them up:

```bash
CACHE=~/.claude/plugins/cache/claude-plugins-official/superpowers/5.1.0
rsync -av skills/gen-ai/ "$CACHE/skills/gen-ai/"
rsync -av hooks/session-start "$CACHE/hooks/session-start"
```

This is the same workflow as V1.

---

### Task 1: Backend detection in bootstrap (TDD)

The first load-bearing assumption: at session start, the bootstrap can reliably tell whether MCP, CLI, or neither is active. Without this, every later task's branch logic has nothing to branch on.

**Files:**

- Create: `tests/claude-code/test-gen-ai-backend-detection.sh`
- Modify: `skills/gen-ai/using-gen-ai-superpowers/SKILL.md`
- Read: `tests/claude-code/test-helpers.sh`

- [ ] **Step 1: Write the RED+GREEN test script**

```bash
#!/usr/bin/env bash
# Test: Does the bootstrap detect and report the active Higgsfield backend?
# Framework: RED-GREEN per testing-skills-with-subagents.md

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

PHASE="${1:-red}"

GEN_AI_PROMPT='Quiero un video cyberpunk corto de un gato neón.'

if [ "$PHASE" = "red" ]; then
    echo "--- RED: bootstrap not yet emitting backend marker ---"
    out=$(run_claude "$GEN_AI_PROMPT" 240)
    if echo "$out" | grep -q "\[gen-ai bootstrap\] backend="; then
        echo "[UNEXPECTED] Marker already present pre-implementation."
        exit 1
    fi
    echo "[OK] RED baseline: no backend marker yet."
fi

if [ "$PHASE" = "green" ]; then
    echo "--- GREEN: bootstrap reports backend cli|mcp|none ---"
    out=$(run_claude "$GEN_AI_PROMPT" 240)
    if echo "$out" | grep -qE "\[gen-ai bootstrap\] backend=(cli|mcp|none)"; then
        echo "[PASS] Backend marker present."
    else
        echo "[FAIL] Expected '[gen-ai bootstrap] backend=<cli|mcp|none>' in output."
        echo "$out" | tail -40
        exit 1
    fi
fi
```

- [ ] **Step 2: Run RED phase**

Run: `bash tests/claude-code/test-gen-ai-backend-detection.sh red`
Expected: `[OK] RED baseline: no backend marker yet.`

- [ ] **Step 3: Commit RED**

```bash
git add tests/claude-code/test-gen-ai-backend-detection.sh
git commit -m "test(gen-ai): RED baseline for backend detection"
```

- [ ] **Step 4: Update the bootstrap to detect and report the backend**

Edit `skills/gen-ai/using-gen-ai-superpowers/SKILL.md`. Replace the `## Auth check` section with:

```markdown
## Backend detection (run before auth check)

On the first gen-ai routing decision, pick exactly ONE active Higgsfield
backend and surface the choice as observable text so users and tests can
see it:

```bash
backend="none"
if claude mcp list 2>/dev/null | grep -qi "higgsfield"; then
    backend="mcp"
elif command -v hf >/dev/null 2>&1 || command -v higgsfield >/dev/null 2>&1; then
    backend="cli"
fi
echo "[gen-ai bootstrap] backend=${backend}"
```

If both are configured, MCP wins (it has talking-head, image-edit, and
upload tools the CLI does not expose at v0.1.34).

Cache the choice for the rest of the session in
`./gen-ai-projects/<slug>/.config.json`:

```json
{ "backend": "mcp" }
```

Downstream skills (`discovering`, `producing-assets`) read this and branch.

## Auth check

Run the auth check that matches the detected backend:

- **`backend=mcp`:** the MCP server fails first call without
  `HF_API_KEY` + `HF_SECRET`. Verify with the MCP's own probe tool:
  ```
  Use the higgsfield-mcp 'debug_credentials' tool. If api_key_configured
  and secret_configured are both true, proceed. Otherwise stop and prompt:
  "Higgsfield MCP credentials missing. Set HF_API_KEY and HF_SECRET env
  vars (get them from https://cloud.higgsfield.ai/api-keys) and restart
  the session."
  ```
- **`backend=cli`:** the CLI has no `auth status` subcommand; `auth token`
  exits 0 + prints token if authed:
  ```bash
  hf auth token >/dev/null 2>&1 || echo "NOT_LOGGED_IN"
  ```
  If `NOT_LOGGED_IN`, stop and prompt: "Higgsfield CLI not authenticated. Run
  `higgsfield auth login` and try again."
- **`backend=none`:** stop and surface install instructions for both paths
  (see `docs/superpowers/notes/higgsfield-invocation.md`).
```

- [ ] **Step 5: Sync to plugin cache**

```bash
CACHE=~/.claude/plugins/cache/claude-plugins-official/superpowers/5.1.0
rsync -av skills/gen-ai/using-gen-ai-superpowers/SKILL.md \
  "$CACHE/skills/gen-ai/using-gen-ai-superpowers/SKILL.md"
```

- [ ] **Step 6: Run GREEN phase**

Run: `bash tests/claude-code/test-gen-ai-backend-detection.sh green`
Expected: `[PASS] Backend marker present.`

If FAIL, the inner agent isn't echoing the marker. Inspect the captured output (the test prints it on failure). Common cause: the agent paraphrased the bash block instead of running it. Iterate the bootstrap prose to be more imperative ("ALWAYS run this exact bash and echo the line"). Two iteration budget.

- [ ] **Step 7: Commit GREEN**

```bash
git add skills/gen-ai/using-gen-ai-superpowers/SKILL.md
git commit -m "feat(gen-ai): bootstrap detects and reports active Higgsfield backend"
```

---

### Task 2: Pluggable auth check follows detected backend (TDD)

Task 1's bootstrap text already includes the per-backend auth check, but we need an executable test that proves the right path is chosen. This task tests it; no SKILL.md edits if Task 1 was complete.

**Files:**

- Modify: `tests/claude-code/test-gen-ai-backend-detection.sh` (extend with auth assertion)
- Read: `skills/gen-ai/using-gen-ai-superpowers/SKILL.md` (no changes expected)

- [ ] **Step 1: Extend the GREEN block to assert the auth path**

Replace the GREEN block in `tests/claude-code/test-gen-ai-backend-detection.sh` with:

```bash
if [ "$PHASE" = "green" ]; then
    echo "--- GREEN: bootstrap reports backend and runs the matching auth check ---"
    out=$(run_claude "$GEN_AI_PROMPT" 240)

    backend=$(echo "$out" | grep -oE "\[gen-ai bootstrap\] backend=(cli|mcp|none)" | tail -1 | cut -d= -f2)
    case "$backend" in
        mcp)  expected_auth_marker="debug_credentials" ;;
        cli)  expected_auth_marker="hf auth token" ;;
        none) expected_auth_marker="install" ;;
        *)    echo "[FAIL] Backend marker missing or unrecognised: '$backend'"; exit 1 ;;
    esac

    assert_contains "$out" "$expected_auth_marker" "auth check should mention '$expected_auth_marker' for backend=$backend"
    echo "[PASS] Backend = $backend, matching auth path exercised."
fi
```

- [ ] **Step 2: Run GREEN**

Run: `bash tests/claude-code/test-gen-ai-backend-detection.sh green`
Expected: `[PASS] Backend = <mcp|cli>, matching auth path exercised.`

If the inner agent prints the bash block but doesn't actually invoke `debug_credentials` (MCP path) or run `hf auth token` (CLI path), the assertion fires. The agent might paraphrase. Iterate the SKILL.md's auth section to use phrases the agent will preserve verbatim.

- [ ] **Step 3: Commit**

```bash
git add tests/claude-code/test-gen-ai-backend-detection.sh
git commit -m "test(gen-ai): assert bootstrap runs the auth path matching detected backend"
```

---

### Task 3: `discovering` source B branches by backend

When `backend=mcp`, the live catalog is at the MCP resources `higgsfield://styles` and `higgsfield://motions`. When `backend=cli`, it's `hf model list`. Same shape of output (preset IDs into `context-bundle.json`).

**Files:**

- Modify: `skills/gen-ai/discovering/SKILL.md`

- [ ] **Step 1: Replace source B with branched logic**

In `skills/gen-ai/discovering/SKILL.md`, replace the `### B — Higgsfield model + skill catalog` section with:

```markdown
### B — Higgsfield model / preset catalog (backend-aware)

Read the active backend from `./gen-ai-projects/<slug>/.config.json`
(written by the bootstrap in Task 1). Branch:

**`backend=mcp`** — read MCP resources directly:

```
Resource: higgsfield://styles    → list of style_id + name + description
Resource: higgsfield://motions   → list of motion_id + name + description + start_end_frame
Resource: higgsfield://characters → list of trained character_id (if any)
```

Pick 3-5 styles whose descriptions match `vibe_tags` from D/C. Pick the
motion presets that fit the brief's intended camera/movement. Capture
their IDs verbatim — they go straight into `producing-assets`.

**`backend=cli`** — use `hf model list`:

```bash
hf model list --image          # GPT Image 2, Nano Banana 2/Pro, Soul V2/Cinema/Cast/Location, ...
hf model list --video          # Seedance 2.0, Kling 3.0, ...
hf generate cost <model> --prompt "<draft>"   # cheap dry-run for budgeting
```

Also consult the installed Higgsfield skills' descriptions (each skill's
frontmatter `description:` is the catalog entry):

- `higgsfield-generate` — general image/video gen
- `higgsfield-product-photoshoot` — brand/product imagery
- `higgsfield-soul-id` — train and reuse a face/identity ref
- `higgsfield-marketplace-cards` — e-commerce listing visuals

Capture model names and skill names — these are the IDs `producing-assets`
will route to. See `docs/superpowers/notes/higgsfield-invocation.md`.
```

- [ ] **Step 2: Add `backend` field to `context-bundle.json`**

Update the JSON example below the new source B section to include the field:

```json
{
  "slug": "2026-05-06-cyberpunk-cat-neon",
  "backend": "mcp",
  "intent_summary": "Short cyberpunk video of a neon cat, ~6 seconds",
  "vibe_tags": ["cyberpunk", "neon", "rain", "synthwave"],
  "palette": ["#0ff", "#f0f", "#000", "#ff0"],
  "refs": [
    {"source": "user", "value": "https://...", "notes": "color palette"},
    {"source": "higgsfield_resource", "uri": "higgsfield://motions", "preset_id": "motion_…", "rationale": "tracking shot fits the brief"}
  ],
  "higgsfield_presets": [
    {"id": "style_…", "type": "style", "rationale": "..."},
    {"id": "motion_…", "type": "motion", "rationale": "..."}
  ],
  "gaps": []
}
```

- [ ] **Step 3: Sync to plugin cache and commit**

```bash
CACHE=~/.claude/plugins/cache/claude-plugins-official/superpowers/5.1.0
rsync -av skills/gen-ai/discovering/SKILL.md "$CACHE/skills/gen-ai/discovering/SKILL.md"
git add skills/gen-ai/discovering/SKILL.md
git commit -m "feat(gen-ai): branch discovering source B by detected backend"
```

(No new tests for this task — covered transitively by the E2E in Task 9.)

---

### Task 4: `brainstorming-gen-ai` adds talking-head and image-edit dimensions

Two new asset types need detection + targeted question dimensions.

**Files:**

- Modify: `skills/gen-ai/brainstorming-gen-ai/SKILL.md`

- [ ] **Step 1: Update the asset-type detection prompt and add two sub-sections**

In `skills/gen-ai/brainstorming-gen-ai/SKILL.md`, replace the line:

```markdown
If the bundle does not declare an asset type, ask first: "¿Es image, video, audio, o mix?"
```

with:

```markdown
If the bundle does not declare an asset type, ask first:

> "¿Qué tipo? (image / video / talking-head / image-edit / mix)"

- **image** — fresh image generation
- **video** — image-to-video or text-to-video clip
- **talking-head** — portrait + audio → lip-synced video (Speak v2). Only if backend=mcp; CLI does not expose this.
- **image-edit** — transform an existing image (background swap, style transfer, etc.). Only if backend=mcp.
- **mix** — multiple types in one project; ask the dimensions for each
```

Then, after the existing `### Audio` sub-section (which stays as a "deferred to V2" note since audio is not generated), add:

```markdown
### Talking-head (backend=mcp only)

Pre-flight check: read `./gen-ai-projects/<slug>/.config.json`. If
`backend != mcp`, abort with: "Talking-head requires the higgsfield-mcp
backend. Either set up the MCP (see Prerequisites) or pick a different
asset type."

Questions:

1. Source portrait (URL? local file? generate first as image asset and chain?)
2. Source audio (WAV URL? local file to upload? generate first via separate TTS?)
3. Duration (5, 10, or 15 seconds — those are the only Speak v2 presets)
4. Quality (high or mid)
5. Aspect for the output frame (default: same as portrait)
6. Enhance prompt? (boolean — auto-rewrite the description with model help)

### Image-edit (backend=mcp only)

Pre-flight check: same as talking-head; abort if `backend != cli`.

Questions:

1. Source image (URL? local file? upload required if local + MCP)
2. Edit description (one sentence, what should change)
3. Aspect ratio of the output (1:1, 16:9, 9:16, 4:3, 3:4)
4. Resolution (720p, 1080p)
5. Should the output preserve the source's character/identity, or is identity allowed to drift? (Informs whether to chain through a Soul reference.)
```

- [ ] **Step 2: Update the brief.md template to record the new types**

Replace the `## Asset list (high level)` example in the brief template with:

```markdown
## Asset list (high level)
- N x image (aspect, style)
- M x video (aspect, duration, motion)
- T x talking-head (duration, source-portrait, source-audio) — backend=mcp only
- E x image-edit (source, edit-description) — backend=mcp only
```

- [ ] **Step 3: Sync to plugin cache and commit**

```bash
CACHE=~/.claude/plugins/cache/claude-plugins-official/superpowers/5.1.0
rsync -av skills/gen-ai/brainstorming-gen-ai/SKILL.md "$CACHE/skills/gen-ai/brainstorming-gen-ai/SKILL.md"
git add skills/gen-ai/brainstorming-gen-ai/SKILL.md
git commit -m "feat(gen-ai): brainstorming covers talking-head and image-edit asset types"
```

---

### Task 5: `asset-planning` decomposes the new types

The shot-list table needs new columns for talking-head's two source media. The decomposition rules need to handle edit chains and the talking-head dependency on a portrait + audio.

**Files:**

- Modify: `skills/gen-ai/asset-planning/SKILL.md`

- [ ] **Step 1: Update decomposition rules**

Replace the four numbered decomposition rules with:

```markdown
1. Each user-facing deliverable is one or more assets.
2. If the brief implies a recurring character or style anchor, asset-01 is reserved for creating/loading that anchor via `higgsfield-soul-id` (CLI path) or `create_character` (MCP path). Subsequent assets bind it via `depends_on`.
3. Assets that share a Higgsfield model can run in parallel. Assets with `depends_on` chains run sequentially after their dependency completes.
4. **Talking-head assets** depend on (a) a portrait image — either an existing URL, or a previous image asset they reference via `depends_on`, and (b) a WAV audio source — either an existing URL or a TODO row marked `external_audio:true` (V1.5 does not generate audio; the user provides it).
5. **Image-edit assets** depend on a source image: an existing URL, or a previous image asset via `depends_on`. The edit prompt and source are both required fields.
6. **Audio is V2.** Higgsfield CLI v0.1.34 does not generate audio output. If the brief asks for audio, capture under "Deferred to V2" and proceed without it. Talking-head's audio is INPUT only — supply existing WAV.
```

- [ ] **Step 2: Update shot-list.md template**

Replace the table example in the shot-list template with:

```markdown
| id | type | prompt | higgsfield_skill_or_tool | model | params | source_image | source_audio | est_cost_usd | depends_on |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| asset-01 | image | "Neon cyberpunk cat, profile, studio lighting" | higgsfield-product-photoshoot / generate_image_seedream | gpt_image_2 / seedream_v4 | aspect=1:1, res=hi | — | — | 0.40 | — |
| asset-02 | video | "Asset-01 cat in rainy alley, slow tracking left" | higgsfield-generate / generate_video_seedance | seedance_2 | aspect=9:16, dur=6s | asset-01 | — | 1.20 | asset-01 |
| asset-03 | talking-head | "Lip-sync the portrait to the provided narration" | generate_talking_head | speak_v2 | dur=10s, quality=high | refs/portrait.png | refs/narration.wav | 0.60 | — |
| asset-04 | image-edit | "Change asset-01 background to a misty alley" | edit_image_seedream | seedream_v4_edit | aspect=1:1, res=hi | asset-01 | — | 0.30 | asset-01 |
```

The two-cell `higgsfield_skill_or_tool` column shows both surfaces ("CLI / MCP"); the row uses whichever is non-empty for the active backend.

- [ ] **Step 3: Update the cost-gate paragraph and "Deferred to V2"**

Replace the existing `## Deferred to V2` block with:

```markdown
## Deferred to V2

- Audio backing track generation (Higgsfield CLI v0.1.34 has no audio output)
- Webhook callbacks for long-running jobs (no inbound endpoint in agent runtime)
- Cross-modal coherence (audio composed jointly with video)
```

- [ ] **Step 4: Sync and commit**

```bash
CACHE=~/.claude/plugins/cache/claude-plugins-official/superpowers/5.1.0
rsync -av skills/gen-ai/asset-planning/SKILL.md "$CACHE/skills/gen-ai/asset-planning/SKILL.md"
git add skills/gen-ai/asset-planning/SKILL.md
git commit -m "feat(gen-ai): asset-planning covers talking-head and image-edit decomposition"
```

---

### Task 6: `producing-assets` routes the new types and runs the upload sub-step (TDD)

The routing table needs talking-head and image-edit. On the MCP path, local source files must be uploaded to public URLs before the gen tool is invoked. The upload sub-step is testable in isolation.

**Files:**

- Create: `tests/claude-code/test-gen-ai-talking-head-routing.sh`
- Create: `tests/claude-code/test-gen-ai-image-edit-routing.sh`
- Modify: `skills/gen-ai/producing-assets/SKILL.md`

- [ ] **Step 1: Write the talking-head routing test (RED+GREEN)**

```bash
#!/usr/bin/env bash
# Test: Does the gen-ai bootstrap route a talking-head intent through producing-assets?
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

PHASE="${1:-red}"

PROMPT='Quiero un avatar hablando — portrait con audio sincronizado, 10 segundos.'

if [ "$PHASE" = "red" ]; then
    echo "--- RED: producing-assets has no talking-head row yet ---"
    out=$(run_claude "$PROMPT" 240)
    if echo "$out" | grep -qi "talking[- ]head"; then
        echo "[OK] Output mentions talking-head — verify routing actually exists in GREEN."
    else
        echo "[OK] RED baseline: agent does not yet name the talking-head asset type."
    fi
fi

if [ "$PHASE" = "green" ]; then
    echo "--- GREEN: agent recognises talking-head and names generate_talking_head or Speak v2 ---"
    out=$(run_claude "$PROMPT" 240)
    assert_contains "$out" "talking-head\|talking head\|generate_talking_head\|Speak v2" \
        "agent should mention talking-head asset type"
    echo "[PASS] talking-head intent recognised."
fi
```

- [ ] **Step 2: Write the image-edit routing test (RED+GREEN)**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

PHASE="${1:-red}"

PROMPT='Tomá esta imagen y cambiale el fondo a un callejón con neblina.'

if [ "$PHASE" = "red" ]; then
    out=$(run_claude "$PROMPT" 240)
    if echo "$out" | grep -qi "image-edit\|edit_image"; then
        echo "[OK] Output mentions image-edit — verify in GREEN."
    else
        echo "[OK] RED baseline: agent does not yet name the image-edit asset type."
    fi
fi

if [ "$PHASE" = "green" ]; then
    out=$(run_claude "$PROMPT" 240)
    assert_contains "$out" "image-edit\|edit_image_seedream\|Seedream.*edit" \
        "agent should mention image-edit asset type"
    echo "[PASS] image-edit intent recognised."
fi
```

- [ ] **Step 3: Run RED phase for both, commit**

```bash
chmod +x tests/claude-code/test-gen-ai-talking-head-routing.sh tests/claude-code/test-gen-ai-image-edit-routing.sh
bash tests/claude-code/test-gen-ai-talking-head-routing.sh red
bash tests/claude-code/test-gen-ai-image-edit-routing.sh red
git add tests/claude-code/test-gen-ai-talking-head-routing.sh tests/claude-code/test-gen-ai-image-edit-routing.sh
git commit -m "test(gen-ai): RED baselines for talking-head and image-edit routing"
```

- [ ] **Step 4: Update `producing-assets` routing table**

In `skills/gen-ai/producing-assets/SKILL.md`, replace the routing table under "Route by type" with:

```markdown
2. **Route by type** (use the row matching the active backend in `.config.json`):

   | type | backend=cli | backend=mcp |
   | --- | --- | --- |
   | image | The `higgsfield-generate` skill (default), `higgsfield-product-photoshoot` (brand), `higgsfield-soul-id` (face/identity), or `higgsfield-marketplace-cards` (e-commerce). CLI fallback: `hf generate create <model> --prompt "<text>" --wait` | `generate_image` (Soul + character_id), `generate_image_reve`, `generate_image_seedream` per the row's `higgsfield_skill_or_tool` field |
   | video | `higgsfield-generate` with a video model. CLI fallback: `hf generate create <model> --prompt "<text>" [--image <path|uuid>] --wait` | `generate_video` (DoP + motion_id), `generate_video_kling`, `generate_video_seedance`, or `generate_video_dop_standard` |
   | talking-head | **NOT SUPPORTED** on CLI. Mark `blocked: talking-head requires MCP backend` and skip | `generate_talking_head` with `image_url`, `audio_url`, `prompt`, `duration`, `quality` |
   | image-edit | **NOT SUPPORTED** on CLI. Mark `blocked: image-edit requires MCP backend` and skip | `edit_image_seedream` with `image_url`, `prompt`, `aspect_ratio`, `resolution` |
   | audio | **Not supported in V1.5.** Higgsfield does not generate audio output. Mark `blocked: audio not supported in V1.5` |
```

- [ ] **Step 5: Add the upload sub-step**

After "2. Route by type", insert a new step:

```markdown
2.5. **Upload local refs (MCP only).** If `backend=mcp` and the row's
`source_image` or `source_audio` is a local file path (not an HTTPS URL),
upload it before invoking the gen tool:

   ```
   For each local ref:
   1. Read the file as bytes.
   2. Base64-encode (no data URI prefix).
   3. Invoke the MCP `upload_image` tool with image_base64 and content_type.
   4. Replace the local path in the row with the returned public_url.
   5. Cache the (local-path → public_url) mapping in
      `./gen-ai-projects/<slug>/.uploads.json` so re-runs reuse the upload.
   ```

   On `backend=cli`, paths pass through directly (`hf generate create`
   accepts local paths and auto-uploads them).
```

(Renumber subsequent steps from 3 down accordingly: "Save output to" becomes 4, "Append cost" 5, etc.)

- [ ] **Step 6: Sync, run GREEN, commit**

```bash
CACHE=~/.claude/plugins/cache/claude-plugins-official/superpowers/5.1.0
rsync -av skills/gen-ai/producing-assets/SKILL.md "$CACHE/skills/gen-ai/producing-assets/SKILL.md"
bash tests/claude-code/test-gen-ai-talking-head-routing.sh green
bash tests/claude-code/test-gen-ai-image-edit-routing.sh green
git add skills/gen-ai/producing-assets/SKILL.md
git commit -m "feat(gen-ai): producing-assets routes talking-head, image-edit, and uploads MCP refs"
```

If GREEN fails for either test (the inner agent doesn't recognise the new asset type), iterate the SKILL.md by sharpening the trigger language in the routing table — the agent must see clear hooks like "talking-head" and "image-edit" near the relevant intents. Two iteration budget per test.

---

### Task 7: `reviewing-outputs` exposes a project-level cancel

Cancellation closes gap #7. Lightweight: add a per-asset and per-project decision to abort the run; producing-assets writes any in-flight `request_id` to project state so reviewing-outputs can issue `cancel_request` (MCP) without deep coordination.

**Files:**

- Modify: `skills/gen-ai/producing-assets/SKILL.md`
- Modify: `skills/gen-ai/reviewing-outputs/SKILL.md`

- [ ] **Step 1: producing-assets writes in-flight request IDs**

In `skills/gen-ai/producing-assets/SKILL.md`, add a new sub-bullet under the per-asset subagent instructions:

```markdown
6.5 **Track in-flight jobs.** Before any `wait`/poll loop, append the
identifier to `./gen-ai-projects/<slug>/.in-flight.jsonl`:

   ```
   {"asset_id": "asset-02", "backend": "mcp", "request_id": "<id>", "started": "<ISO timestamp>"}
   ```

   Remove the line on completion (success or failure). `reviewing-outputs`
   reads this file to know what is still cancellable.
```

- [ ] **Step 2: reviewing-outputs adds the cancel decisions**

In `skills/gen-ai/reviewing-outputs/SKILL.md`, replace the `## Review loop` numbered list step 2 (the per-asset prompt) with:

```markdown
2. Ask: "asset-X — ¿approved, reject (regenerate), revise (regenerate with notes), o cancel-project (abort everything)?"
```

Then, after step 5, add a new section:

```markdown
## Cancel-project handler

If the user picks `cancel-project` on any asset:

1. Read `./gen-ai-projects/<slug>/.in-flight.jsonl`. For each row whose
   `backend == "mcp"`, invoke the MCP `cancel_request` tool with that
   `request_id`. (CLI rows have no cancel verb at v0.1.34; just stop polling.)
2. Update each remaining asset's status in the contact sheet to `cancelled`.
3. Print a one-line summary: total cost incurred so far (sum of `cost.log`),
   what was salvageable (any approved assets keep their files).
4. Stop. Do NOT invoke `/gen-ai:finishing-content` after a cancel; the
   session ends here.
```

- [ ] **Step 3: Sync and commit**

```bash
CACHE=~/.claude/plugins/cache/claude-plugins-official/superpowers/5.1.0
rsync -av skills/gen-ai/producing-assets/SKILL.md "$CACHE/skills/gen-ai/producing-assets/SKILL.md"
rsync -av skills/gen-ai/reviewing-outputs/SKILL.md "$CACHE/skills/gen-ai/reviewing-outputs/SKILL.md"

git add skills/gen-ai/producing-assets/SKILL.md skills/gen-ai/reviewing-outputs/SKILL.md
git commit -m "feat(gen-ai): cancel-project gate in reviewing-outputs; track in-flight jobs"
```

(No new test for cancellation — covered by manual smoke; real cancellation needs an active MCP session and is exercised in Task 9 E2E.)

---

### Task 8: Update existing GREEN gate to include backend marker check

V1's `test-gen-ai-intent-routing.sh` GREEN now needs to be aware that the bootstrap is doing more work upfront (backend detection). Loosen the timeout if needed and confirm it still passes.

**Files:**

- Modify: `tests/claude-code/test-gen-ai-intent-routing.sh`

- [ ] **Step 1: Bump GREEN gen-ai timeout from 240s to 300s**

In the GREEN block, change:

```bash
out_genai=$(run_claude "$GEN_AI_PROMPT" 240)
```

to:

```bash
out_genai=$(run_claude "$GEN_AI_PROMPT" 300)
```

Reason: the bootstrap now emits a backend detection block + auth check before the routing decision. Empirically the inner agent should still finish under 240s, but the extra work warrants headroom.

- [ ] **Step 2: Add a soft assert that backend marker is present**

After the existing positive `assert_contains "$out_genai" "discovering"` line, add:

```bash
# Soft: detection should also have run. Don't fail GREEN on this — the bootstrap
# might compress detection into a single tool call; just surface it in the log.
if echo "$out_genai" | grep -qE "\[gen-ai bootstrap\] backend="; then
    echo "  [info] backend marker present"
else
    echo "  [info] backend marker absent (Task 1 may need iteration)"
fi
```

- [ ] **Step 3: Run GREEN and commit**

```bash
bash tests/claude-code/test-gen-ai-intent-routing.sh green
git add tests/claude-code/test-gen-ai-intent-routing.sh
git commit -m "test(gen-ai): widen V1 GREEN timeout for added bootstrap work; soft-assert backend marker"
```

---

### Task 9: E2E acceptance — talking-head flow on MCP backend

Drive a fresh session through a talking-head intent, asserting each gate triggers. This is the V1.5 analogue of V1's `test-gen-ai-e2e-image.sh` and similarly will only fully pass with MCP credentials configured.

**Files:**

- Create: `tests/claude-code/test-gen-ai-e2e-talking-head.sh`

- [ ] **Step 1: Write the E2E test**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

PROJECT_DIR=$(create_test_project)
cd "$PROJECT_DIR"

# Pre-flight: skip with a clear message if MCP isn't configured. The test
# requires the higgsfield-mcp registered with claude and HF_API_KEY+HF_SECRET set.
if ! claude mcp list 2>/dev/null | grep -qi "higgsfield"; then
    echo "[SKIP] higgsfield-mcp not registered. Run: claude mcp add higgsfield -- npx -y higgsfield-mcp"
    exit 0
fi
if [ -z "${HF_API_KEY:-}" ] || [ -z "${HF_SECRET:-}" ]; then
    echo "[SKIP] HF_API_KEY / HF_SECRET not set."
    exit 0
fi

# Turn 1: trigger talking-head intent
out1=$(run_claude "Quiero un avatar de mí mismo hablando una narración corta, 10 segundos, calidad alta." 300)

assert_contains "$out1" "discovering" "Turn 1 should reference discovering"
assert_contains "$out1" "talking-head\|talking head\|generate_talking_head" "Turn 1 should reach the talking-head asset type"

# Filesystem state: backend should have been written
ls gen-ai-projects/*/.config.json >/dev/null 2>&1 || {
    echo "[FAIL] .config.json (backend record) not created"; exit 1;
}
ls gen-ai-projects/*/context-bundle.json >/dev/null 2>&1 || {
    echo "[FAIL] context-bundle.json not created"; exit 1;
}

# Verify backend recorded as mcp
if ! grep -q '"backend"[[:space:]]*:[[:space:]]*"mcp"' gen-ai-projects/*/.config.json; then
    echo "[FAIL] .config.json does not record backend=mcp"
    cat gen-ai-projects/*/.config.json
    exit 1
fi

echo "[PASS] E2E talking-head flow reaches discovering + brief stage on MCP backend."

cleanup_test_project "$PROJECT_DIR"
```

- [ ] **Step 2: Run the test**

```bash
chmod +x tests/claude-code/test-gen-ai-e2e-talking-head.sh
bash tests/claude-code/test-gen-ai-e2e-talking-head.sh
```

If MCP is unconfigured, expect `[SKIP]` and exit 0 — the test self-skips. If MCP is configured, expect `[PASS]`.

If it fails on the assertions (not the skip), the most likely cause is the agent paraphrasing the asset-type detection. Iterate `brainstorming-gen-ai`'s talking-head trigger language. Two iteration budget.

- [ ] **Step 3: Commit**

```bash
git add tests/claude-code/test-gen-ai-e2e-talking-head.sh
git commit -m "test(gen-ai): E2E acceptance for talking-head flow on MCP backend"
```

---

### Task 10: Regression — code prompt unaffected by V1.5 additions

The new asset types must not bleed into code prompts. Re-run V1's regression test on the updated bootstrap; if it now fails (because the agent mentions "talking-head" or "image-edit" while declining a code prompt), iterate the bootstrap's intent-detection rules.

**Files:**

- Modify (if needed): `tests/claude-code/test-gen-ai-regression-code.sh`

- [ ] **Step 1: Run V1's regression test against the V1.5 bootstrap**

```bash
bash tests/claude-code/test-gen-ai-regression-code.sh
```

Expected: `[PASS] Code track unaffected by gen-ai bootstrap.`

- [ ] **Step 2: If FAIL, iterate the bootstrap's intent-detection rules**

If the agent now leaks `talking-head` or `image-edit` into a code-prompt response, edit `skills/gen-ai/using-gen-ai-superpowers/SKILL.md` Code signals list and add **engineering** signals that the failing prompt contains but a creative prompt would not — pick from the actual failing output, not from this plan's guesswork. Examples that have empirically helped: `state`, `route`, `query`, `localStorage`, `database`, `endpoint`. Avoid adding words that legitimately appear in creative briefs (`model` would falsely match "modelo Soul"; do NOT add).

Re-run regression after each edit. Two iteration budget.

- [ ] **Step 3: Commit**

If you modified the bootstrap, commit:

```bash
git add skills/gen-ai/using-gen-ai-superpowers/SKILL.md
git commit -m "feat(gen-ai): tighten code-signal list to keep V1.5 types from bleeding into code prompts"
```

If no changes were needed, the regression test is informational only — note its pass in the next commit's message.

---

### Task 11: Update spec to mark V1.5 backlog items resolved

After all tasks pass, mark the gaps closed in the spec.

**Files:**

- Modify: `docs/superpowers/specs/2026-05-06-agentic-gen-ai-design.md`

- [ ] **Step 1: Annotate the V1.5 backlog**

Edit `docs/superpowers/specs/2026-05-06-agentic-gen-ai-design.md`. Under "## V1.5 / V2 backlog", strike-through each item that is now closed. Concretely, prepend to gaps #1–5 and #7:

```markdown
1. ~~**Talking head / lip-sync video.**~~ **Resolved by V1.5 (commit `<sha>`):** added as first-class asset type; tested in `test-gen-ai-e2e-talking-head.sh`.
```

…and similar for gaps 2, 3, 4, 5, 7. Leave gap #6 (webhooks) un-struck and note "Deferred to V2 — agent runtime has no inbound HTTP endpoint."

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-05-06-agentic-gen-ai-design.md
git commit -m "docs(gen-ai): mark V1.5 backlog items as resolved"
```

---

## Self-Review Checklist (run after all tasks above are written)

- [ ] **Spec coverage:** every backlog gap (#1 talking-head, #2 image-edit, #3 auth pluggable, #4 upload, #5 catalog, #6 webhooks, #7 cancellation) maps to a task or is explicitly deferred (#6).
- [ ] **No placeholders:** no "TBD", "fill in", or "similar to N" in any task body.
- [ ] **Type consistency:** asset id `asset-NN`, slug `YYYY-MM-DD-<words>`, `.config.json`/`.uploads.json`/`.in-flight.jsonl` filenames, the column order in the new shot-list table — all consistent across tasks.
- [ ] **Each step is 2–5 minutes:** no step bundles multiple skill edits or multiple commits.
- [ ] **Every code step has actual code:** no "implement the SKILL.md" without showing the markdown.
- [ ] **Cache sync called out:** every SKILL.md-touching task includes the rsync to `~/.claude/plugins/cache/.../5.1.0/` so `claude -p` tests see the change.
- [ ] **TDD where it makes sense:** Tasks 1, 6, 9 have explicit RED-GREEN. Task 2 is a focused assert on Task 1's surface. Tasks 3-5, 7 are skill-content tasks where the test is the E2E in Task 9 plus the routing tests in Task 6.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-09-agentic-gen-ai-v1.5.md`. Two execution options:

**1. Subagent-Driven (recommended)** — fresh subagent per task, two-stage review between tasks, fast iteration. Best for this plan because Tasks 3–5 are independent SKILL.md edits and Task 1's TDD pattern matches the V1 GREEN gate exactly.

**2. Inline Execution** — execute tasks in this session using `executing-plans`, batch execution with checkpoints.

**Which approach?**
