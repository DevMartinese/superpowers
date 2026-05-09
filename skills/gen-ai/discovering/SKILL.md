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

### B — Higgsfield model + skill catalog

`@higgsfield/cli@0.1.34` does not expose an `explore` subcommand. Use the
model list and the installed Higgsfield skill descriptions as the catalog
instead:

```bash
hf model list --image          # GPT Image 2, Nano Banana 2/Pro, Soul V2/Cinema/Cast/Location, ...
hf model list --video          # Seedance 2.0, Kling 3.0, ...
hf generate cost <model> --prompt "<draft>"   # cheap dry-run for budgeting
```

Also consult the installed Higgsfield skills for the specialist entry points
they cover (each one's frontmatter `description:` is the catalog entry):

- `higgsfield-generate` — general image/video gen, defaults to GPT Image 2 / Seedance 2.0
- `higgsfield-product-photoshoot` — brand/product imagery via mode-specific prompt enhancement
- `higgsfield-soul-id` — train and reuse a Soul Character (face/identity ref)
- `higgsfield-marketplace-cards` — e-commerce listing visuals with backend compliance

Capture model names and skill names — these are the IDs `producing-assets`
will route to. See `docs/superpowers/notes/higgsfield-invocation.md` for the
verified surface.

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
