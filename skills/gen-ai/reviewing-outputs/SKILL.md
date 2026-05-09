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
