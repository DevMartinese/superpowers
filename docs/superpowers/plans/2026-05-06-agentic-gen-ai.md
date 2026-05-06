# Agentic Gen-AI Track Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a parallel agentic flow for gen-ai content (image, video, audio) under `skills/gen-ai/`, using Higgsfield's official skills as the generation engine, autoroute on user intent, and coexist cleanly with the existing code track.

**Architecture:** Seven new skills under `skills/gen-ai/` (`using-gen-ai-superpowers`, `discovering`, `brainstorming-gen-ai`, `asset-planning`, `producing-assets`, `reviewing-outputs`, `finishing-content`). The bootstrap is loaded via the existing SessionStart hook alongside `using-superpowers`. Higgsfield's official skills (`/higgsfield:generate`, `/higgsfield:soul`, `/higgsfield:product-photoshoot`) are the generation engine — no API wrappers. Project state lives in `./gen-ai-projects/<slug>/` on the filesystem.

**Tech Stack:** Markdown (skill files), bash (test scripts and run-hook), Higgsfield CLI + official skills, Claude Code CLI (`claude -p` for headless evaluation).

**Spec:** `docs/superpowers/specs/2026-05-06-agentic-gen-ai-design.md`

---

## Prerequisites (manual, one-time)

These steps require human interaction and cannot be automated by the agent. Complete them before starting Task 1.

```bash
# 1. Install the Higgsfield CLI
npm install -g @higgsfield/cli

# 2. Sign in (opens a browser)
higgsfield auth login

# 3. Install Higgsfield's official skills (gives /higgsfield:generate, /higgsfield:soul, /higgsfield:product-photoshoot)
npx skills add higgsfield-ai/skills

# 4. Verify
higgsfield --version
which hf  # should resolve
```

**Document the working invocation** of `/higgsfield:generate` (image, video, and audio) once installed — capture exact slash-command names and parameter shapes. Audio support is unverified at design time and may require CLI fallback. Save findings to `docs/superpowers/notes/higgsfield-invocation.md` (create the file).

---

### Task 1: GATE — Validate intent-detection routing with TDD

This is a **gate task**. The bootstrap's intent detection is the load-bearing assumption of the design — if a fresh agent does not reliably route gen-ai messages to `discovering` and code messages to core `brainstorming`, the spec collapses. Validate before writing the seven skills.

**Files:**

- Create: `tests/claude-code/test-gen-ai-intent-routing.sh`
- Read: `skills/writing-skills/testing-skills-with-subagents.md` (TDD framework)
- Read: `tests/claude-code/test-helpers.sh` (for `run_claude`, `assert_contains`)

- [ ] **Step 1: Write the RED baseline test script**

```bash
#!/usr/bin/env bash
# Test: Does the bootstrap route gen-ai vs code intent correctly?
# Framework: RED-GREEN per testing-skills-with-subagents.md

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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
```

- [ ] **Step 2: Run RED phase — verify baseline**

Run: `bash tests/claude-code/test-gen-ai-intent-routing.sh red`
Expected: `[OK] RED baseline: no discovering reference yet.`

- [ ] **Step 3: Commit the test (RED)**

```bash
git add tests/claude-code/test-gen-ai-intent-routing.sh
git commit -m "test(gen-ai): RED baseline for intent-detection routing"
```

GREEN runs in Task 9 after the bootstrap is installed via the hook. If GREEN fails after two iterations on the bootstrap, STOP — the routing approach needs redesign.

---

### Task 2: Skill — `using-gen-ai-superpowers` (bootstrap)

The bootstrap detects intent from the first user message and routes to gen-ai or code track.

**Files:**

- Create: `skills/gen-ai/using-gen-ai-superpowers/SKILL.md`

- [ ] **Step 1: Write the SKILL.md**

```markdown
---
name: using-gen-ai-superpowers
description: Use at session start to detect gen-ai intent (image, video, audio, marketing content) and route to the gen-ai track. Loads alongside using-superpowers.
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific task, skip this skill.
</SUBAGENT-STOP>

# Gen-AI Track Bootstrap

## When this skill applies

Loaded at session start via SessionStart hook alongside `using-superpowers`. Inspect the user's first substantive message to determine which track applies.

## Intent detection

Score the message against these signals:

**Gen-AI signals (any one routes to gen-ai):**
- Explicit asset words: `imagen`, `image`, `picture`, `foto`, `video`, `clip`, `audio`, `track`, `música`, `sound`, `sfx`, `render`
- Creative-direction words: `cyberpunk`, `cinematic`, `mood`, `aesthetic`, `style`, `look`, `vibe`, `escena`, `shot`, `character`, `personaje`
- Generation verbs: `generá`, `generate`, `crear` (with creative object), `make me a`, `produce`
- Higgsfield-specific: `higgsfield`, `soul`, `product photoshoot`, `motion preset`

**Code signals (any one routes to code):**
- Engineering verbs: `build`, `implement`, `refactor`, `fix bug`, `deploy`, `migrate`, `test`, `commit`, `PR`
- Engineering objects: `function`, `component`, `endpoint`, `API`, `schema`, `migration`, `service`

**Routing rules:**

1. If gen-ai signals present and no code signals → invoke `/gen-ai:discovering`
2. If code signals present and no gen-ai signals → defer to core `using-superpowers` flow (do nothing here)
3. If both or neither → ask once: "Is this gen-ai content (image/video/audio) or a code task?" Then route.

## Project state detection

Before invoking `discovering`, check if `./gen-ai-projects/` contains a slug that matches the user's intent:

- If user references an existing slug ("continue with project X") → load `./gen-ai-projects/<slug>/` and skip to the earliest unfinished stage (file presence: `context-bundle.json`, `brief.md`, `shot-list.md`, `outputs/`, `final-export/`).
- If new project → invoke `/gen-ai:discovering` with empty state.

## Auth check

On first gen-ai routing decision, verify Higgsfield CLI auth:

```bash
hf auth status 2>&1 | grep -q "logged in" || echo "NOT_LOGGED_IN"
```

If `NOT_LOGGED_IN`, stop and prompt: "Higgsfield CLI not authenticated. Run `higgsfield auth login` and try again." Do not proceed.
```

- [ ] **Step 2: Commit**

```bash
git add skills/gen-ai/using-gen-ai-superpowers/SKILL.md
git commit -m "feat(gen-ai): add using-gen-ai-superpowers bootstrap skill"
```

(GREEN test in Task 9 after hook integration.)

---

### Task 3: Skill — `discovering`

Research references before brainstorming. Sources priority D → C → B → A.

**Files:**

- Create: `skills/gen-ai/discovering/SKILL.md`

- [ ] **Step 1: Write the SKILL.md**

```markdown
---
name: discovering
description: Research references for gen-ai work before brainstorming. Reads local brand assets, asks for user refs, browses Higgsfield Explore, and falls back to Web. Outputs context-bundle.json.
---

# Discovering — Reference Research

## Why this exists

Brainstorming asks better questions when grounded in real references. Without discovering, the brief is built on the user's mental image alone — unreliable for a multi-modal output that has to be both subjectively right and technically generatable in Higgsfield.

## Source priority (D → C → B → A)

Run sources in this order. Stop adding when you have ≥3 distinct references and ≥1 candidate Higgsfield preset.

### D — Local brand assets

Check for any of:

- `./brand/` (logos, colors, fonts, voice guidelines)
- `./refs/` (image/video/audio references the user has saved)
- `./.gen-ai/refs/` (project-scoped refs)

If present, read `*.md`, `*.json`, and list image/video/audio files. Extract: palette (from images via filename or vision), tone words (from text), recurring motifs.

### C — User-provided refs

If D is empty or insufficient, ask the user:

> "Pasame 1–3 referencias (imagen, link, o descripción) que capturen el vibe que buscás. Si no tenés, decime el género/director/marca que más se parece y arranco desde ahí."

Wait for response. Do not invent refs.

### B — Higgsfield Explore

Use Higgsfield CLI to browse the native catalog:

```bash
hf explore --query "<vibe tags>" --limit 20
```

Filter to: director presets, motion presets, character cards, audio presets that match `vibe_tags` from D/C. Capture preset IDs — these are the IDs `producing-assets` will bind.

### A — Web (last resort)

Use WebSearch + WebFetch for trends, mood boards, and public references. Do not over-rely — web refs are inspiration, not invocable assets in Higgsfield.

## Output: context-bundle.json

Save to `./gen-ai-projects/<slug>/context-bundle.json`. Slug is generated from the first 3-5 words of the user's intent (kebab-case, prefixed with `YYYY-MM-DD-`).

```json
{
  "slug": "2026-05-06-cyberpunk-cat-neon",
  "intent_summary": "Short cyberpunk video of a neon cat, ~6 seconds",
  "vibe_tags": ["cyberpunk", "neon", "rain", "synthwave"],
  "palette": ["#0ff", "#f0f", "#000", "#ff0"],
  "refs": [
    {"source": "user", "value": "https://...", "notes": "color palette"},
    {"source": "higgsfield_explore", "preset_id": "...", "type": "motion", "rationale": "tracking shot fits the brief"}
  ],
  "higgsfield_presets": [
    {"id": "...", "type": "motion", "rationale": "..."},
    {"id": "...", "type": "director", "rationale": "..."}
  ],
  "gaps": ["no audio refs provided"]
}
```

## Handoff

After saving the bundle, invoke `/gen-ai:brainstorming-gen-ai` and pass the bundle path.
```

- [ ] **Step 2: Commit**

```bash
git add skills/gen-ai/discovering/SKILL.md
git commit -m "feat(gen-ai): add discovering skill"
```

---

### Task 4: Skill — `brainstorming-gen-ai`

Creative brief, question-by-question, grounded in the discovering bundle.

**Files:**

- Create: `skills/gen-ai/brainstorming-gen-ai/SKILL.md`

- [ ] **Step 1: Write the SKILL.md**

```markdown
---
name: brainstorming-gen-ai
description: Build a creative brief for gen-ai work. Question-by-question with multiple-choice when possible. Inherits patterns from core brainstorming but asks gen-ai-specific dimensions (aspect ratio, duration, character consistency, mood).
---

# Brainstorming Gen-AI

## When this skill applies

Invoked by `discovering` after `context-bundle.json` is written. Reads the bundle for grounding, then asks targeted questions to produce `brief.md`.

## Pattern (inherited from core brainstorming)

- One question per message
- Multiple choice when possible
- Lead with your recommendation and reason
- Hard gate: no transition to `asset-planning` until the user approves the brief

## Question dimensions by asset type

If the bundle does not declare an asset type, ask first: "¿Es image, video, audio, o mix?"

### Image

1. Aspect ratio (1:1, 4:5, 16:9, 9:16, custom)
2. Resolution / quality tier (preview, standard, hi-res)
3. Style depth (photorealistic, illustrated, stylized)
4. Character consistency (one-off, or recurring character with refs)
5. Asset count (single, set of N variants)

### Video

1. Aspect (16:9, 9:16, 1:1)
2. Duration (3s, 6s, 10s, custom)
3. FPS (24, 30, 60)
4. Motion intensity (static, subtle, dynamic, action)
5. Scene count (single shot, multi-shot)
6. Transitions if multi-shot (hard cut, dissolve, match cut)

### Audio

1. Duration
2. Genre / sub-genre
3. BPM range
4. Mood (driving, melancholic, ethereal, tense)
5. Instrumentation hints
6. Vocal or instrumental

## Output: brief.md

Save to `./gen-ai-projects/<slug>/brief.md`:

```markdown
# Brief — <slug>

## Intent
<intent_summary from bundle, refined>

## Asset list (high level)
- N x image (aspect, style)
- M x video (aspect, duration, motion)
- K x audio (genre, duration)

## Creative direction
<vibe, palette, refs from bundle, refined>

## Constraints
- Platform target: <Instagram Reels / TikTok / YouTube / Print / etc.>
- Deadline (if any):
- Budget cap (if any):

## Character / style consistency
<recurring character refs, or "N/A">

## Open decisions for asset-planning
<anything the user explicitly defers>
```

## Gate

After writing the brief, present a 3-line summary and ask: "¿Aprobás el brief para que arme el shot list, o querés cambiar algo?" Do NOT invoke `asset-planning` until you receive an explicit affirmative.
```

- [ ] **Step 2: Commit**

```bash
git add skills/gen-ai/brainstorming-gen-ai/SKILL.md
git commit -m "feat(gen-ai): add brainstorming-gen-ai skill"
```

---

### Task 5: Skill — `asset-planning`

Translate the brief into a discrete asset list with cost estimate.

**Files:**

- Create: `skills/gen-ai/asset-planning/SKILL.md`

- [ ] **Step 1: Write the SKILL.md**

```markdown
---
name: asset-planning
description: Translate an approved brief into a shot/asset list with cost estimate and dependencies. Output is shot-list.md with one row per asset.
---

# Asset Planning

## When this skill applies

Invoked after `brainstorming-gen-ai` and explicit user approval of `brief.md`.

## Decomposition rules

1. Each user-facing deliverable is one or more assets.
2. If the brief implies a recurring character or style anchor, asset-01 is reserved for creating/loading that anchor (Higgsfield Character or a style-locked seed image). Subsequent assets bind it via `depends_on`.
3. Assets that share a Higgsfield preset can run in parallel. Assets with `depends_on` chains run sequentially after their dependency completes.
4. For video with audio companion (V1: independent assets, no cross-modal coherence): generate video and audio as two separate rows. Cross-coherence is V2.

## Output: shot-list.md

Save to `./gen-ai-projects/<slug>/shot-list.md`:

```markdown
# Shot List — <slug>

## Estimated total cost: $<total>

| id | type | prompt | higgsfield_skill | presets | params | est_cost_usd | depends_on |
| --- | --- | --- | --- | --- | --- | --- | --- |
| asset-01 | image | "Neon cyberpunk cat, profile, studio lighting" | soul | director:noir-01 | aspect=1:1, res=hi | 0.40 | — |
| asset-02 | video | "Asset-01 cat in rainy alley, slow tracking left" | generate | motion:tracking-left, character:asset-01 | aspect=9:16, dur=6s, fps=30 | 1.20 | asset-01 |
| asset-03 | audio | "Synthwave loopable backing, 100bpm" | generate (audio mode; verify) | — | dur=6s | 0.30 | — |

## Dependencies

- asset-02 binds asset-01 as character ref (consistency anchor)

## Notes

- If `/higgsfield:generate` does not expose audio mode, asset-03 falls back to `hf generate-audio ...` via Bash. Document the working command in producing-assets.
```

## Cost gate

Before declaring the plan ready, compute total `est_cost_usd`. Read `./gen-ai-projects/<slug>/.config.json` (or `./.gen-ai/config.json`) for `cost_gate_usd` (default $5).

If total > threshold, present: "El plan estima $X. Threshold actual: $Y. ¿Confirmás antes de ejecutar?"

If user adjusts threshold, write it to `.config.json`.

## Output handoff

After user approves the shot list (and cost), invoke `/gen-ai:producing-assets`.
```

- [ ] **Step 2: Commit**

```bash
git add skills/gen-ai/asset-planning/SKILL.md
git commit -m "feat(gen-ai): add asset-planning skill"
```

---

### Task 6: Skill — `producing-assets`

Subagent-driven generation, one subagent per asset, parallel where possible, sequential when `depends_on`.

**Files:**

- Create: `skills/gen-ai/producing-assets/SKILL.md`

- [ ] **Step 1: Write the SKILL.md**

```markdown
---
name: producing-assets
description: Dispatch one subagent per asset to invoke Higgsfield's official skills (or CLI fallback). Parallel where independent, sequential when depends_on. Saves outputs and cost log.
---

# Producing Assets

## When this skill applies

Invoked after `asset-planning` and explicit user approval of `shot-list.md` and the cost estimate.

## Dispatch model

Use the core skill `dispatching-parallel-agents` for parallel rows (no `depends_on`). Sequential rows with `depends_on` run after their dependency completes.

Each subagent receives:

1. The row from shot-list.md
2. The slug and project directory path
3. The path to context-bundle.json (for refs)

## Per-asset subagent instructions

Each subagent must:

1. **Auth check first.** If `hf auth status` fails, abort with clear message — do not retry, do not workaround.
2. **Route by type:**

   | type | invocation |
   | --- | --- |
   | image | `/higgsfield:generate` or `/higgsfield:soul` or `/higgsfield:product-photoshoot` per the row's `higgsfield_skill` field |
   | video | `/higgsfield:generate` with motion preset |
   | audio | `/higgsfield:generate` (audio mode if exposed) — fallback: `hf generate-audio <prompt> --duration <s>` via Bash |

3. **Save output to** `./gen-ai-projects/<slug>/outputs/<asset-id>/v<n>.<ext>` where `<n>` is the next available version number (start at 1).
4. **Append cost** to `./gen-ai-projects/<slug>/cost.log`:

   ```
   <ISO timestamp>\t<asset-id>\tv<n>\t<actual_cost_usd>
   ```

5. **Retry policy on rate-limit:** exponential backoff (5s, 15s, 45s), max 3 retries, then mark `blocked` and continue with other assets.
6. **On audio fallback:** if `/higgsfield:generate` rejects audio mode, switch to CLI. Document the working invocation in `docs/superpowers/notes/higgsfield-invocation.md`.

## Aggregation

After all subagents complete:

1. Print summary: total assets, succeeded, blocked, total cost.
2. If any blocked, ask user: "Asset-X failed (rate limit / unsupported). Retry now, defer to next session, or skip?"
3. Invoke `/gen-ai:reviewing-outputs`.
```

- [ ] **Step 2: Commit**

```bash
git add skills/gen-ai/producing-assets/SKILL.md
git commit -m "feat(gen-ai): add producing-assets skill"
```

---

### Task 7: Skill — `reviewing-outputs`

Visual review gate — agent cannot declare done without user approval.

**Files:**

- Create: `skills/gen-ai/reviewing-outputs/SKILL.md`

- [ ] **Step 1: Write the SKILL.md**

```markdown
---
name: reviewing-outputs
description: Present generated outputs for user visual review. Loop with producing-assets when rejected. Cannot transition to finishing-content without explicit per-asset approval.
---

# Reviewing Outputs

## When this skill applies

Invoked by `producing-assets` once all assets are generated (or marked blocked).

## Contact sheet

Generate a markdown contact sheet at `./gen-ai-projects/<slug>/contact-sheet.md`:

```markdown
# Contact Sheet — <slug>

## asset-01 (image)
![asset-01](outputs/asset-01/v1.png)
**Prompt:** <prompt>
**Status:** pending review

## asset-02 (video)
[outputs/asset-02/v1.mp4](outputs/asset-02/v1.mp4)
**Prompt:** <prompt>
**Status:** pending review
```

For each asset, include the file path so the user can open it locally.

## Review loop

For each asset in the contact sheet:

1. Show the asset path and prompt.
2. Ask: "asset-X — ¿approved, reject (regenerate), o revise (regenerate with notes)?"
3. On `approved` → symlink to `./gen-ai-projects/<slug>/approved/`. Update status in contact sheet.
4. On `reject` → loop back to `/gen-ai:producing-assets` for that single asset, save as v2, v3, ...
5. On `revise <notes>` → update the prompt in shot-list.md (preserving original as a comment), loop back to producing-assets.

## Known failure-mode checklist (V1: manual flags)

Prompt the user to specifically inspect for:

- Hands and fingers in characters
- Text rendering inside images (often illegible)
- Temporal coherence in video (objects morphing across frames)
- Aspect ratio mismatch with the platform target stated in the brief

## Gate

Cannot invoke `/gen-ai:finishing-content` until every asset has status `approved` (or user explicitly aborts the project).
```

- [ ] **Step 2: Commit**

```bash
git add skills/gen-ai/reviewing-outputs/SKILL.md
git commit -m "feat(gen-ai): add reviewing-outputs skill"
```

---

### Task 8: Skill — `finishing-content`

Final export with metadata.

**Files:**

- Create: `skills/gen-ai/finishing-content/SKILL.md`

- [ ] **Step 1: Write the SKILL.md**

```markdown
---
name: finishing-content
description: Final export of approved gen-ai assets with metadata (titles, alt text, descriptions). Optionally commits to git. Prints summary with total cost.
---

# Finishing Content

## When this skill applies

Invoked by `reviewing-outputs` once all assets are approved.

## Steps

1. Copy approved assets from `./gen-ai-projects/<slug>/approved/` (resolving symlinks) to `./gen-ai-projects/<slug>/final-export/<asset-id>.<ext>`.
2. Generate `metadata.json` next to the export:

   ```json
   {
     "slug": "<slug>",
     "generated_at": "<ISO timestamp>",
     "total_cost_usd": <sum of cost.log>,
     "assets": [
       {
         "id": "asset-01",
         "type": "image",
         "file": "asset-01.png",
         "title": "<LLM-generated from brief + prompt>",
         "alt_text": "<LLM-generated, accessibility-focused>",
         "description": "<LLM-generated, 1-2 sentences>",
         "platform_target": "<from brief>"
       }
     ]
   }
   ```

3. Print summary to the user:

   ```
   Project: <slug>
   Assets: <N> (image: a, video: b, audio: c)
   Total cost: $<X>
   Export: ./gen-ai-projects/<slug>/final-export/
   ```

4. Ask: "¿Commit el proyecto a git? (incluye brief, shot-list, contact-sheet, metadata; excluye outputs y final-export por tamaño)"

5. On yes:

   ```bash
   git add gen-ai-projects/<slug>/{brief.md,shot-list.md,contact-sheet.md,metadata.json,cost.log,context-bundle.json}
   git commit -m "gen-ai: <slug> — <N> assets, $<X>"
   ```

6. Suggest `.gitignore` entries (only on first project):

   ```
   gen-ai-projects/*/outputs/
   gen-ai-projects/*/final-export/
   gen-ai-projects/*/approved/
   ```
```

- [ ] **Step 2: Commit**

```bash
git add skills/gen-ai/finishing-content/SKILL.md
git commit -m "feat(gen-ai): add finishing-content skill"
```

---

### Task 9: Wire bootstrap into SessionStart hook

The bootstrap must load at session start alongside `using-superpowers`. The real hook script is `hooks/session-start` (extensionless polyglot script invoked by `run-hook.cmd`). It currently reads `skills/using-superpowers/SKILL.md` and injects it as `additionalContext`. We need to also read the gen-ai bootstrap and concatenate it.

**Files:**

- Read: `hooks/session-start` (current behavior — see lines around `using_superpowers_content=$(cat ...)`)
- Modify: `hooks/session-start`

- [ ] **Step 1: Add the gen-ai bootstrap read alongside using-superpowers**

In `hooks/session-start`, after the line that reads `using_superpowers_content`, add:

```bash
# Read using-gen-ai-superpowers content (gen-ai track bootstrap)
gen_ai_bootstrap_path="${PLUGIN_ROOT}/skills/gen-ai/using-gen-ai-superpowers/SKILL.md"
if [ -f "$gen_ai_bootstrap_path" ]; then
    using_gen_ai_content=$(cat "$gen_ai_bootstrap_path" 2>&1 || echo "Error reading using-gen-ai-superpowers skill")
else
    using_gen_ai_content=""
fi
```

The conditional read makes the hook safe if the gen-ai track is uninstalled (clean fallback to core-only behavior).

- [ ] **Step 2: Escape and inject the gen-ai content**

After the existing `using_superpowers_escaped=$(escape_for_json "$using_superpowers_content")` line, add:

```bash
using_gen_ai_escaped=$(escape_for_json "$using_gen_ai_content")
```

Then modify the `session_context` assignment to append the gen-ai bootstrap after the core bootstrap. Replace:

```bash
session_context="<EXTREMELY_IMPORTANT>\nYou have superpowers.\n\n**Below is the full content of your 'superpowers:using-superpowers' skill - your introduction to using skills. For all other skills, use the 'Skill' tool:**\n\n${using_superpowers_escaped}\n\n${warning_escaped}\n</EXTREMELY_IMPORTANT>"
```

With:

```bash
gen_ai_section=""
if [ -n "$using_gen_ai_content" ]; then
    gen_ai_section="\n\n---\n\n**Gen-AI Track Bootstrap (loaded automatically when the gen-ai track is installed):**\n\n${using_gen_ai_escaped}"
fi

session_context="<EXTREMELY_IMPORTANT>\nYou have superpowers.\n\n**Below is the full content of your 'superpowers:using-superpowers' skill - your introduction to using skills. For all other skills, use the 'Skill' tool:**\n\n${using_superpowers_escaped}${gen_ai_section}\n\n${warning_escaped}\n</EXTREMELY_IMPORTANT>"
```

- [ ] **Step 3: Smoke-test the hook locally**

Run the hook directly to verify it produces valid JSON containing both bootstraps:

```bash
CLAUDE_PLUGIN_ROOT=$(pwd) bash hooks/session-start | python3 -c "import json,sys; data=json.load(sys.stdin); ctx=data.get('hookSpecificOutput',{}).get('additionalContext','') or data.get('additionalContext','') or data.get('additional_context',''); print('using-superpowers found:', 'using-superpowers' in ctx); print('using-gen-ai found:', 'using-gen-ai-superpowers' in ctx)"
```

Expected output:

```
using-superpowers found: True
using-gen-ai found: True
```

If either is False, inspect `hooks/session-start` for typos in the path or string concatenation.

- [ ] **Step 4: Run GREEN phase of intent-routing test (Task 1's gate)**

Run: `bash tests/claude-code/test-gen-ai-intent-routing.sh green`

Expected:

```
[PASS] Routing works: gen-ai → discovering, code → brainstorming.
```

If FAIL: do NOT proceed. Iterate on the bootstrap's intent-detection rules in `skills/gen-ai/using-gen-ai-superpowers/SKILL.md`. After 2 iterations without GREEN, STOP — the routing approach needs redesign.

- [ ] **Step 5: Commit**

```bash
git add hooks/session-start
git commit -m "feat(gen-ai): wire using-gen-ai-superpowers into SessionStart hook"
```

---

### Task 10: E2E acceptance test — image flow

Drive the full flow with a single-asset image request and verify each gate triggers.

**Files:**

- Create: `tests/claude-code/test-gen-ai-e2e-image.sh`

- [ ] **Step 1: Write the test script**

```bash
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
```

- [ ] **Step 2: Run the test**

Run: `bash tests/claude-code/test-gen-ai-e2e-image.sh`
Expected: `[PASS] E2E image flow reaches brief stage.`

If it fails, inspect which gate did not fire — the SKILL.md for that stage likely needs sharper trigger language. Iterate.

- [ ] **Step 3: Commit**

```bash
git add tests/claude-code/test-gen-ai-e2e-image.sh
git commit -m "test(gen-ai): E2E acceptance for image flow up to brief"
```

---

### Task 11: Regression test — code flow unchanged

Ensure a code request still activates core `brainstorming`, not gen-ai.

**Files:**

- Create: `tests/claude-code/test-gen-ai-regression-code.sh`

- [ ] **Step 1: Write the test**

```bash
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
```

- [ ] **Step 2: Run the test**

Run: `bash tests/claude-code/test-gen-ai-regression-code.sh`
Expected: `[PASS] Code track unaffected by gen-ai bootstrap.`

- [ ] **Step 3: Commit**

```bash
git add tests/claude-code/test-gen-ai-regression-code.sh
git commit -m "test(gen-ai): regression — code prompts still use core brainstorming"
```

---

### Task 12: Audio verification milestone

Verify whether `/higgsfield:generate` exposes audio mode. Document the working invocation. If unsupported, validate the CLI fallback.

**Files:**

- Create: `docs/superpowers/notes/higgsfield-invocation.md`

- [ ] **Step 1: Probe the official skill**

In a clean Claude Code session with Higgsfield skills installed, run:

```
/higgsfield:generate audio: "30s lofi backing, 80bpm, melancholic" duration=30
```

Capture: does the skill accept the `audio:` modality? Does it return a downloadable URL? What is the exact slash-command shape?

- [ ] **Step 2: If audio mode unsupported, probe the CLI**

```bash
hf --help | grep -i audio
hf generate-audio --help
```

Run a minimal audio generation:

```bash
hf generate-audio "30s lofi backing, 80bpm" --duration 30 --output /tmp/test-audio.mp3
```

Verify file exists and is playable.

- [ ] **Step 3: Document findings**

Create `docs/superpowers/notes/higgsfield-invocation.md`:

```markdown
# Higgsfield Invocation Notes

**Verified:** <date>
**CLI version:** <output of `hf --version`>
**Skills version:** <output of `npx skills list higgsfield-ai/skills` or equivalent>

## Image (verified working)
- Slash command: `/higgsfield:generate <params>`
- Example: ...

## Video (verified working)
- Slash command: `/higgsfield:generate <params>`
- Motion preset binding: ...
- Example: ...

## Audio (status: <verified working | fallback to CLI>)

### Via official skill (if supported)
- Slash command: ...
- Example: ...

### Via CLI fallback (if skill unsupported)
- Command: `hf generate-audio "<prompt>" --duration <s> --output <path>`
- Verified working: <yes/no, date>
- Example: ...

## Auth
- Status check: `hf auth status`
- Login: `higgsfield auth login`
- Token location: ~/.config/higgsfield/credentials (or wherever the CLI stores it)
```

- [ ] **Step 4: Update producing-assets to reflect verified invocation**

If the audio path differs from what `producing-assets/SKILL.md` describes, update the SKILL.md to match the verified working command. Commit:

```bash
git add docs/superpowers/notes/higgsfield-invocation.md
git add skills/gen-ai/producing-assets/SKILL.md
git commit -m "docs(gen-ai): document verified Higgsfield invocations; align producing-assets"
```

---

## Self-Review Checklist (run after all tasks above are written)

- [ ] **Spec coverage:** every section in the spec maps to at least one task above
- [ ] **No placeholders:** no "TBD", "fill in", "similar to N" in any task body
- [ ] **Type consistency:** asset id format (`asset-NN`), slug format (`YYYY-MM-DD-<words>`), file paths consistent across tasks
- [ ] **Each step is 2–5 minutes:** no step bundles multiple actions
- [ ] **Every code step has actual code:** no "implement the SKILL.md" without showing the content
- [ ] **TDD where it makes sense:** Tasks 1, 9, 10, 11 have RED/GREEN; Tasks 2–8 are skill-content tasks where the test is the E2E in Task 10

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-06-agentic-gen-ai.md`. Two execution options:

**1. Subagent-Driven (recommended)** — fresh subagent per task, two-stage review between tasks, fast iteration. Best for this plan because Tasks 2–8 are independent skill files.

**2. Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?**
