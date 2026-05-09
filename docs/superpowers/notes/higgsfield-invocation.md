# Higgsfield Invocation Notes

**Verified:** 2026-05-09
**CLI version:** higgsfield 0.1.34 (built 2026-05-08)
**Skills package:** higgsfield-ai/skills (skills exposed below)
**Auth status at verification:** unauthenticated (probes are surface-only, no API calls made)

> Closes Task 12 of `docs/superpowers/plans/2026-05-06-agentic-gen-ai.md` for the
> static surface verification. Live image/video generation will be re-verified
> end-to-end after `higgsfield auth login`.

## CLI binary names

`higgsfield`, `higgs`, and `hf` are all aliases for the same binary. Skills may
use any of them; this track standardises on `higgsfield` for clarity in
documentation and on `hf` in user-facing prose where the plan already used it.

## Subcommand surface (via `higgsfield --help`)

```
account            Credits and transactions
auth               Login, logout, token  (no `status` subcommand)
generate           Create, cost, list, wait jobs  (image / video / text only)
marketing-studio   Marketing Studio assets
marketplace-cards  Marketplace product cards via backend prompt enhancement
model              List models and params
product-photoshoot Brand-quality image generation via mode-specific prompt enhancement
soul-id            Train and manage Soul refs
upload             Upload media inputs
workspace          Select billing workspace
```

### Notable mismatches with the plan

The plan and several of our gen-ai skills referenced subcommands and flags that
do not exist. Each is corrected in the iterated skill below.

| Plan / skill referenced | Actual CLI surface | Fix |
| --- | --- | --- |
| `hf auth status \| grep "logged in"` | No `auth status`. `auth token` exits 0 + prints token if authed, errors otherwise | Bootstrap auth check rewritten |
| `hf explore --query ... --limit 20` | No `explore` subcommand at all | Discovering source B rewritten using `model list` + the official skills' descriptions |
| `hf generate-audio "..." --duration <s>` | No audio output exposed; `model list` filters are `--image / --video / --text` only. `--audio` flag exists but is media INPUT to a generate job, not output | Audio dropped to V2; producing-assets and asset-planning updated |
| `/higgsfield:generate`, `/higgsfield:soul`, `/higgsfield:product-photoshoot` | Skills installed by `npx skills add higgsfield-ai/skills` use names `higgsfield-generate`, `higgsfield-soul-id`, `higgsfield-product-photoshoot`, `higgsfield-marketplace-cards` (no colon, `soul-id` not `soul`) | All four skills updated to reference the real names |

## Image (verified surface; live test pending auth)

- **Skill:** `higgsfield-generate` — entry point for image and video work. Default
  models: GPT Image 2 (image), Seedance 2.0 (video), Nano Banana 2/Pro
  (character/reference work).
- **Specialist skill:** `higgsfield-product-photoshoot` — brand/product imagery
  via GPT Image 2 with mode-specific prompt enhancement.
- **CLI fallback:**
  ```
  higgsfield generate create <model> --prompt "<text>" [--image <path|uuid>] [--wait]
  ```
- **Cost preview:** `higgsfield generate cost <model> --prompt "..."`

## Video (verified surface; live test pending auth)

- **Skill:** `higgsfield-generate` (Seedance 2.0 default; Kling 3.0, Soul
  Cinema, etc. are also exposed).
- **CLI fallback:** same `generate create <model>` shape; `--video` flag accepts
  an existing video as input.

## Character / identity (Soul)

- **Skill:** `higgsfield-soul-id` — train a personalised model on a face, returns
  a `reference_id` re-usable in subsequent generate calls.
- **CLI:** `higgsfield soul-id ...` subcommand.
- **Note:** the plan referenced `/higgsfield:soul` — corrected to
  `higgsfield-soul-id`.

## Marketplace / product cards

- **Skill:** `higgsfield-marketplace-cards` (compliant main image, secondary
  images, A+ content). Not in original plan; available out of the box and
  documented here for asset-planning to consider when target is e-commerce.

## Audio (status: unsupported in V1)

Higgsfield's CLI does not expose an audio output modality at version 0.1.34.
`model list` filters are `--image`, `--video`, `--text`; there is no
`--audio`. The `--audio` flag on `generate create` is for supplying an
existing audio file as INPUT to a video/multimodal job, not for generating
audio.

**Decision:** audio is descoped to V2 of the agentic gen-ai track. A future
iteration can integrate a different audio provider (e.g. ElevenLabs,
Suno, or whichever Higgsfield ships next) without changing the orchestration
shape. Until then:

- `asset-planning` only enumerates image and video assets.
- `producing-assets` no longer includes an audio row in its routing table.
- The user-facing brainstorming flow still asks about audio so the brief
  captures the gap explicitly, but downstream generation skips it with a
  clear "deferred to V2" note.

## Auth

- **Login (one-time, browser-based):** `higgsfield auth login`
- **Authed check (use this in scripts):** `higgsfield auth token`
  - Exit 0 + token on stdout when authed
  - Non-zero exit when not authed (no `status` subcommand exists)
- **Logout:** `higgsfield auth logout`
- **Token storage:** managed by the CLI (location not probed; `auth token`
  is the source of truth for scripts)

## Verification reproduction

All findings above were produced without authenticating, using:

```bash
npx -y -p @higgsfield/cli higgsfield --help
npx -y -p @higgsfield/cli higgsfield auth --help
npx -y -p @higgsfield/cli higgsfield generate --help
npx -y -p @higgsfield/cli higgsfield generate create --help
npx -y -p @higgsfield/cli higgsfield model list --help
npx -y skills add higgsfield-ai/skills
find .agents/skills -name SKILL.md -exec head -10 {} \;
```

Re-run any of the above to refresh.
