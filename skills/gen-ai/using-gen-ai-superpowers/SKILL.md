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

On first gen-ai routing decision, verify Higgsfield CLI auth. The CLI has no
`auth status` subcommand; use `auth token` and rely on the exit code (prints
the token on stdout when authed, errors otherwise):

```bash
hf auth token >/dev/null 2>&1 || echo "NOT_LOGGED_IN"
```

If `NOT_LOGGED_IN`, stop and prompt: "Higgsfield CLI not authenticated. Run `higgsfield auth login` and try again." Do not proceed.

If `hf` is not on PATH at all, also surface install instructions:
`npm install -g @higgsfield/cli` then `higgsfield auth login` then
`npx skills add higgsfield-ai/skills`. See
`docs/superpowers/notes/higgsfield-invocation.md` for verified surface.
