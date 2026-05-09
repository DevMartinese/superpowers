---
name: asset-planning
description: Translate an approved brief into a shot/asset list with cost estimate and dependencies. Output is shot-list.md with one row per asset.
---

# Asset Planning

## When this skill applies

Invoked after `brainstorming-gen-ai` and explicit user approval of `brief.md`.

## Decomposition rules

1. Each user-facing deliverable is one or more assets.
2. If the brief implies a recurring character or style anchor, asset-01 is reserved for creating/loading that anchor via `higgsfield-soul-id` (face/identity) or a style-locked seed image. Subsequent assets bind it via `depends_on`.
3. Assets that share a Higgsfield model can run in parallel. Assets with `depends_on` chains run sequentially after their dependency completes.
4. **Audio is V2.** Higgsfield CLI v0.1.34 does not generate audio output (only image, video, text). If the brief asks for audio, capture it under "Open decisions for V2" in the brief and proceed with image/video only. See `docs/superpowers/notes/higgsfield-invocation.md`.

## Output: shot-list.md

Save to `./gen-ai-projects/<slug>/shot-list.md`:

```markdown
# Shot List — <slug>

## Estimated total cost: $<total>

| id | type | prompt | higgsfield_skill | model | params | est_cost_usd | depends_on |
| --- | --- | --- | --- | --- | --- | --- | --- |
| asset-01 | image | "Neon cyberpunk cat, profile, studio lighting" | higgsfield-product-photoshoot | gpt_image_2 | aspect=1:1, res=hi | 0.40 | — |
| asset-02 | video | "Asset-01 cat in rainy alley, slow tracking left" | higgsfield-generate | seedance_2 | aspect=9:16, dur=6s, fps=30, character:asset-01 | 1.20 | asset-01 |

## Dependencies

- asset-02 binds asset-01 as character ref (consistency anchor)

## Deferred to V2

- Audio backing track (Higgsfield CLI does not generate audio; revisit with a separate provider)
```

## Cost gate

Before declaring the plan ready, compute total `est_cost_usd`. Read `./gen-ai-projects/<slug>/.config.json` (or `./.gen-ai/config.json`) for `cost_gate_usd` (default $5).

If total > threshold, present: "El plan estima $X. Threshold actual: $Y. ¿Confirmás antes de ejecutar?"

If user adjusts threshold, write it to `.config.json`.

## Output handoff

After user approves the shot list (and cost), invoke `/gen-ai:producing-assets`.
