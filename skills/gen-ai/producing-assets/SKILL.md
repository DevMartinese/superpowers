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

1. **Auth check first.** Run `hf auth token >/dev/null 2>&1`; non-zero exit means abort with a clear "run `higgsfield auth login` and try again" message — do not retry, do not workaround. (The CLI has no `auth status` subcommand; `auth token` is the source of truth.)
2. **Route by type:**

   | type | invocation |
   | --- | --- |
   | image | The `higgsfield-generate` skill (default), or the specialist `higgsfield-product-photoshoot` (brand/product), `higgsfield-soul-id` (face/identity training + reuse), or `higgsfield-marketplace-cards` (e-commerce) — pick per the row's `higgsfield_skill` field. CLI fallback: `hf generate create <model> --prompt "<text>" [--image <path|uuid>] --wait` |
   | video | `higgsfield-generate` with a video model (Seedance 2.0, Kling 3.0, ...). CLI fallback: same `generate create <model>` shape; pass character ref via `--image` or a soul-id reference id |
   | audio | **Not supported in V1.** Higgsfield CLI v0.1.34 generates only image / video / text. If a shot-list still contains an audio row, mark `blocked: audio not supported in V1` and skip; the brief should have flagged this in asset-planning |

3. **Save output to** `./gen-ai-projects/<slug>/outputs/<asset-id>/v<n>.<ext>` where `<n>` is the next available version number (start at 1).
4. **Append cost** to `./gen-ai-projects/<slug>/cost.log`:

   ```
   <ISO timestamp>\t<asset-id>\tv<n>\t<actual_cost_usd>
   ```

5. **Retry policy on rate-limit:** exponential backoff (5s, 15s, 45s), max 3 retries, then mark `blocked` and continue with other assets.
6. **Cost preview:** before each generation, run `hf generate cost <model> --prompt "..."` and refuse to proceed if the per-asset estimate is more than 1.5× the value in the shot-list — surface the variance to the controller.

## Aggregation

After all subagents complete:

1. Print summary: total assets, succeeded, blocked, total cost.
2. If any blocked, ask user: "Asset-X failed (rate limit / unsupported). Retry now, defer to next session, or skip?"
3. Invoke `/gen-ai:reviewing-outputs`.
