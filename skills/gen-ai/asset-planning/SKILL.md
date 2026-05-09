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
