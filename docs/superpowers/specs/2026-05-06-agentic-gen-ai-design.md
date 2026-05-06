# Agentic Gen-AI Track for Superpowers

**Date:** 2026-05-06
**Status:** Draft
**Branch:** `superpowers/agentic-gen-ai`
**Distribution:** Personal fork (not for upstream)

## Problem

Superpowers is a software-development methodology — its skills (`brainstorming`, `writing-plans`, `test-driven-development`, etc.) are tuned for code. Generative AI work (image, video, audio, marketing assets) has the same structural needs as a coding task — exploring intent, producing a plan, executing in pieces, reviewing, finishing — but the inputs, outputs, and gates are different. There is no test suite for a video; there is no merge for an image; aspect ratio matters more than function signatures.

Today, when a user asks for gen-ai content in a Superpowers session, the agent either improvises (variable quality) or routes to the code track (wrong shape entirely). With Higgsfield exposing first-class agent integration (CLI, MCP, and skills) for image/video/audio/marketing, there is now a viable backend to build a gen-ai track on top of — but the orchestration layer is missing.

This spec defines a parallel gen-ai track that lives alongside the code track in the fork, autoroutes based on user intent, and uses Higgsfield's official skills as the generation engine while adding a Superpowers-style flow on top.

## Goals

1. Provide a complete agentic flow for gen-ai work that mirrors Superpowers' structural rigor (discovery → brief → plan → execute → review → finish)
2. Use Higgsfield's official skills (`generate`, `soul`, `product-photoshoot`) as the generation engine — do not reimplement its API
3. Cover image, video, and audio as first-class asset types
4. Coexist cleanly with the existing code track — neither replaces nor modifies core Superpowers skills
5. Autoroute on user intent so users do not have to invoke the track manually
6. Provide cost visibility and a budget gate before paid generations run
7. Keep character/style consistency across multi-shot projects

## Non-Goals

- Upstream contribution to `obra/superpowers` — this is a personal fork; the project's `CLAUDE.md` excludes domain-specific skills and third-party dependencies from core
- Reimplementing Higgsfield's API in our own wrappers
- A versioning/database system for refs and outputs — filesystem + git is enough
- NSFW gating — assume responsible use
- Marketing Studio multi-asset campaigns (V2)
- Iteration / non-linear edit mode (V2)
- Cross-modal coherence (e.g., a video with its companion audio generated as one unit) — V2; in V1 each asset is independent
- MCP integrations beyond Higgsfield (Linear briefs, Drive uploads, Figma refs) — V2

## Design Principles

### Parallel track, not modification

The gen-ai track lives entirely under `skills/gen-ai/` and never modifies core skills (`brainstorming`, `writing-plans`, etc.). The fork stays mergeable with upstream when v5.2/v6 lands.

### Higgsfield is the engine, we are the orchestrator

Skills in this track invoke `/higgsfield:generate`, `/higgsfield:soul`, `/higgsfield:product-photoshoot` (or fall back to the CLI for features the skills do not yet expose). When Higgsfield ships new capabilities, we inherit them by updating their skills — no API maintenance on our side.

### Filesystem as the project state

Project state (context bundle, brief, shot list, outputs, cost log) lives in a predictable directory layout under `./gen-ai-projects/<project-slug>/`. Sessions can resume by reading the filesystem; no extra database or session API is needed.

### Human gates at every irreversible step

Generation costs money and time. The flow has hard gates after `brainstorming-gen-ai` (brief approval), after `asset-planning` (cost-aware shot list approval), and after `producing-assets` (visual review). The agent never proceeds past a gate without explicit user confirmation.

### Intent detection, not opt-in

The bootstrap (`using-gen-ai-superpowers`) detects gen-ai intent from the user's message and routes automatically. Users do not need to learn a new command — they say "make me an image of X" and the right track activates.

## Design

### 1. Directory and skill layout

```text
skills/gen-ai/
├── using-gen-ai-superpowers/    # bootstrap; intent detection + routing
│   └── SKILL.md
├── discovering/                  # research refs before brainstorming
│   └── SKILL.md
├── brainstorming-gen-ai/         # creative brief
│   └── SKILL.md
├── asset-planning/               # asset list with cost estimate
│   └── SKILL.md
├── producing-assets/             # subagent-driven generation
│   └── SKILL.md
├── reviewing-outputs/            # visual review gate
│   └── SKILL.md
└── finishing-content/            # export + metadata
    └── SKILL.md
```

### 2. Skills

#### 2.1 `using-gen-ai-superpowers` (bootstrap)

Loaded at session start alongside `using-superpowers` via the same SessionStart hook mechanism (the bootstrap is referenced as a sibling skill in the fork's hook configuration). Detects intent on the first user message and routes.

**Intent detection rules:**

| Signal | Track |
| --- | --- |
| Keywords: `imagen`, `image`, `video`, `audio`, `generar`, `render`, `shot`, `mood`, `campaign`, `character`, `escena`, `track musical`, `sfx` | gen-ai |
| Keywords: `función`, `function`, `componente`, `component`, `bug`, `test`, `API`, `deploy`, `refactor`, `commit`, `PR` | code |
| Mixed or ambiguous | Ask once, do not assume |

If gen-ai → invoke `discovering`. If code → defer to `using-superpowers` flow. If ambiguous → single clarifying question, then route.

#### 2.2 `discovering`

Research references **before** brainstorming so the brief is informed, not blank.

**Source priority (D → C → B → A):**

1. **D — Local brand assets:** read `./brand/`, `./refs/`, `./.gen-ai/` if present
2. **C — User-provided refs:** if D is empty, ask the user for 1–3 images/links
3. **B — Higgsfield Explore:** browse the native catalog (director presets, motion presets, character cards) for candidates that match the user's intent
4. **A — Web:** WebSearch + WebFetch for trends, mood boards, public references — last resort, fills gaps

**Output:** `./gen-ai-projects/<slug>/context-bundle.json` with:

```json
{
  "intent_summary": "...",
  "vibe_tags": ["cyberpunk", "neon", "rain"],
  "palette": ["#0ff", "#f0f", "#000"],
  "refs": [{"source": "user", "path": "...", "notes": "..."}],
  "higgsfield_presets": [{"id": "...", "type": "motion", "rationale": "..."}],
  "gaps": ["no audio refs provided"]
}
```

The bundle is read by `brainstorming-gen-ai` to ground its questions.

#### 2.3 `brainstorming-gen-ai`

Inherits the question-by-question pattern from core `brainstorming` (one question per message, multiple choice when possible, hard gate before proceeding).

**Domain-specific question dimensions** (varies by asset type):

| Asset type | Dimensions |
| --- | --- |
| Image | aspect ratio, resolution, style, character consistency, count |
| Video | aspect, duration, fps, motion intensity, scene count, transitions |
| Audio | duration, genre, BPM, mood, instrumentation, vocal/instrumental |

**Output:** `./gen-ai-projects/<slug>/brief.md` — the creative spec.

**Gate:** user must approve the brief before `asset-planning` runs.

#### 2.4 `asset-planning`

Translates the brief into a discrete asset list. Each asset is one task.

**Output:** `./gen-ai-projects/<slug>/shot-list.md` (markdown table + cost estimate).

Each row:

| Field | Notes |
| --- | --- |
| `id` | `asset-01`, `asset-02`, ... |
| `type` | `image` \| `video` \| `audio` |
| `prompt` | Full text prompt |
| `higgsfield_skill` | `generate` \| `soul` \| `product-photoshoot` |
| `presets` | director / motion / character refs to bind |
| `params` | aspect, duration, resolution, etc. |
| `est_cost_usd` | best-effort estimate |
| `depends_on` | optional dependency on another asset (e.g., character ref) |

**Character/style consistency:** if the brief implies a recurring character, `asset-01` is reserved for character creation (Higgsfield Character feature) and subsequent assets bind it as a ref via `depends_on`.

**Cost gate:** if total `est_cost_usd > $5`, require explicit user confirmation before proceeding. The threshold is configurable via `./gen-ai-projects/<slug>/.config.json` (`cost_gate_usd` key) or globally via `./.gen-ai/config.json`. Append every actual generation cost to `./gen-ai-projects/<slug>/cost.log` (one line per asset: timestamp, asset id, cost).

**Gate:** user must approve the shot list (and cost estimate) before `producing-assets` runs.

#### 2.5 `producing-assets`

Subagent-driven, one subagent per asset, dispatched in parallel using the `dispatching-parallel-agents` skill from core (assets are independent unless a `depends_on` chain exists; chained assets run sequentially after their dependency completes). Each subagent:

1. Reads its row from the shot list
2. Routes by `type`:
   - `image` → invoke `/higgsfield:generate` or `/higgsfield:soul` or `/higgsfield:product-photoshoot`
   - `video` → invoke `/higgsfield:generate` with motion preset
   - `audio` → invoke `/higgsfield:generate` with audio mode (verify in V1; fallback to CLI directly via Bash if the official skill does not expose audio yet)
3. Saves output to `./gen-ai-projects/<slug>/outputs/<asset-id>/v1.<ext>` (v2, v3 on regeneration)
4. Appends actual cost to `cost.log`
5. Reports completion to the parent session

**Error handling:**

| Failure | Response |
| --- | --- |
| Auth fail (`higgsfield auth login` missing) | Abort with clear message; do not retry |
| Rate limit | Exponential backoff, 3 retries, then defer to next session |
| Generation produced but quality bad | Not handled here — `reviewing-outputs` decides |
| Skill not found / audio unsupported | Fallback to CLI via Bash; if CLI also fails, mark asset as `blocked` and continue with others |

#### 2.6 `reviewing-outputs`

Visual review gate. The agent **cannot** declare the project done without user review.

1. Generates a contact sheet (markdown with thumbnails) listing each asset with its file path
2. For each asset: user marks `approved` / `reject` / `revise <notes>`
3. Approved → symlink to `./gen-ai-projects/<slug>/approved/`
4. Rejected with notes → re-enter `producing-assets` with revised prompt (saved as `v2`, `v3`, etc.)
5. Loop until all assets are approved or user explicitly aborts

**Known failure-mode checklist** (manual flags for the user; not auto-detected in V1):

- Hands and fingers in characters
- Text rendering inside images
- Temporal coherence across video frames
- Aspect-ratio mismatch with declared platform target

#### 2.7 `finishing-content`

Final export + metadata.

1. Copy approved assets to `./gen-ai-projects/<slug>/final-export/`
2. Generate `metadata.json` with title, alt text, descriptions for each asset (LLM-generated from brief + asset prompt)
3. Print summary: total assets, total cost, output paths
4. Optionally: commit project to git (user prompt)

### 3. Project state layout

```text
./gen-ai-projects/<project-slug>/
├── context-bundle.json       (discovering)
├── brief.md                   (brainstorming-gen-ai)
├── shot-list.md               (asset-planning)
├── outputs/
│   ├── asset-01/v1.png, v2.png
│   ├── asset-02/v1.mp4
│   └── asset-03/v1.mp3
├── approved/                  (symlinks)
├── final-export/              (finishing-content)
└── cost.log
```

The slug is auto-generated from the brief title in `brief.md` (kebab-case, slugified, prefixed with `YYYY-MM-DD-`). Sessions resume by reading this directory: if a user re-enters the project (by referencing the slug or being inside the directory), the bootstrap detects existing state and skips already-completed stages.

### 4. Data flow

```text
user message
  → using-gen-ai-superpowers (intent detection)
  → discovering (D → C → B → A)
  → context-bundle.json
  → brainstorming-gen-ai
  → brief.md  [GATE 1: user approves brief]
  → asset-planning (with cost estimate)
  → shot-list.md  [GATE 2: user approves plan + cost]
  → producing-assets (subagent per asset)
  → outputs/
  → reviewing-outputs  [GATE 3: visual approval per asset]
  → approved/
  → finishing-content
  → final-export/
```

### 5. Higgsfield integration (hybrid model)

- **Engine layer (Higgsfield's responsibility):** `npx skills add higgsfield-ai/skills` installs `generate`, `soul`, `product-photoshoot`. These are invoked as `/higgsfield:generate` etc. by `producing-assets`.
- **Orchestration layer (our responsibility):** the seven skills above. We do not call Higgsfield's HTTP API directly.
- **Auth:** `higgsfield auth login` (one-time, user-driven). The bootstrap checks for auth on first gen-ai intent and prompts the user to log in if missing.
- **Audio caveat:** unverified whether the official skills expose audio at the time of writing. V1 implementation must verify on first audio asset; if not exposed, fallback to direct CLI calls via Bash. Document this in `producing-assets/SKILL.md`.

## Testing / Acceptance

### Bootstrap test

User message: `"hacé un video cyberpunk de un gato"` → autoactivates `discovering`, not core `brainstorming`.

### End-to-end test

User: `"imagen cyberpunk de un gato neón"`. Expected flow with no agent improvisation:

1. `discovering` → bundle with cyberpunk vibe, neon palette, candidate Higgsfield presets
2. `brainstorming-gen-ai` → asks aspect, style depth, count → produces brief
3. Gate 1 → user approves
4. `asset-planning` → 1 asset, image, est cost displayed
5. Gate 2 → user approves
6. `producing-assets` → invokes `/higgsfield:generate`, saves to outputs
7. `reviewing-outputs` → user approves
8. `finishing-content` → exports, prints summary

### Regression test

User: `"build a react todo list"` → autoactivates core `brainstorming`. The gen-ai track does not interfere.

### Audio verification test (V1 milestone)

User: `"generá un track lofi de 30 segundos"` → flow runs end-to-end. If `/higgsfield:generate` does not expose audio, fallback to CLI is exercised. Document the working invocation in the skill.

## Future work (V2+)

- **Iteration / non-linear edit mode:** resume any project, jump to any stage, regenerate a single asset without resetting state
- **Marketing Studio campaigns:** multi-asset coherent campaigns (image + video + audio + copy as one unit)
- **MCP integrations:** read briefs from Linear, push exports to Drive, import refs from Figma
- **Cross-modal coherence:** generate a video and its audio companion as a single coherent unit
- **Auto-detected failure modes:** vision-model checks for broken hands, illegible text, aspect mismatch
- **Marketplace publishing:** if the track stabilizes, publish as a standalone Superpowers plugin

## Open questions for V1 implementation

1. Exact intent-detection keyword list — needs adversarial testing across user phrasings (English + Spanish at minimum, since the user works bilingually)
2. Cost estimation accuracy — Higgsfield's pricing per-asset needs to be documented in `asset-planning` and kept in sync as their pricing changes
3. Audio support in official skills — verify on first audio asset; document the working invocation in `producing-assets/SKILL.md`
