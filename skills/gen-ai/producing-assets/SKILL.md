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
