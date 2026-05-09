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
