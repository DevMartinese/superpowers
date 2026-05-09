---
name: finishing-content
description: Final export of approved gen-ai assets with metadata (titles, alt text, descriptions). Optionally commits to git. Prints summary with total cost.
---

# Finishing Content

## When this skill applies

Invoked by `reviewing-outputs` once all assets are approved.

## Steps

1. Copy approved assets from `./gen-ai-projects/<slug>/approved/` (resolving symlinks) to `./gen-ai-projects/<slug>/final-export/<asset-id>.<ext>`.
2. Generate `metadata.json` next to the export:

   ```json
   {
     "slug": "<slug>",
     "generated_at": "<ISO timestamp>",
     "total_cost_usd": <sum of cost.log>,
     "assets": [
       {
         "id": "asset-01",
         "type": "image",
         "file": "asset-01.png",
         "title": "<LLM-generated from brief + prompt>",
         "alt_text": "<LLM-generated, accessibility-focused>",
         "description": "<LLM-generated, 1-2 sentences>",
         "platform_target": "<from brief>"
       }
     ]
   }
   ```

3. Print summary to the user:

   ```
   Project: <slug>
   Assets: <N> (image: a, video: b, audio: c)
   Total cost: $<X>
   Export: ./gen-ai-projects/<slug>/final-export/
   ```

4. Ask: "¿Commit el proyecto a git? (incluye brief, shot-list, contact-sheet, metadata; excluye outputs y final-export por tamaño)"

5. On yes:

   ```bash
   git add gen-ai-projects/<slug>/{brief.md,shot-list.md,contact-sheet.md,metadata.json,cost.log,context-bundle.json}
   git commit -m "gen-ai: <slug> — <N> assets, $<X>"
   ```

6. Suggest `.gitignore` entries (only on first project):

   ```
   gen-ai-projects/*/outputs/
   gen-ai-projects/*/final-export/
   gen-ai-projects/*/approved/
   ```
