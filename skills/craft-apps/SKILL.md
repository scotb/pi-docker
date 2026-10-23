---
name: "craft-apps"
description: "Headless image + PDF editing in this environment: PhotoCraft (image cleanup/retouch, Find Edges for coloring-book pages, icon creation, batch pipelines) and PdfCraft (combine/split PDFs, page ops, book assembly). Use when asked to clean up images, make coloring-book pages, create icons or images for web pages, batch-process photos, or assemble/edit PDF books — via photocraft-cli, pdfcraft-cli, or their MCP servers."
version: 1.0.0
created: "2026-10-23"
updated: "2026-10-23"
---
## When to Use
- **Image work**: cleaning up scanned pages/photos (tone, whiten, sharpen), photo → coloring-book page (Find Edges), creating icons/images for web pages, batch-processing many images.
- **PDF work**: combining pages into a book, splitting, rotating, page labels/bookmarks, metadata, protecting.
- The tools: `photocraft-cli` (`/opt/photocraft/bin`, on PATH) and `pdfcraft-cli` (`/opt/pdfcraft/bin`, on PATH), each also registered as an MCP server (`photocraft`, `pdfcraft`) in `~/.pi/agent/mcp.json` — seeded on fresh volumes, rooted at `/host`.
- NOT for: taking screenshots (use `page-shot`), vector art (VectorCraft is not baked in).

## The discovery rule (do this first)
Both apps are early alpha (v0.13.0): command ids and parameter names change between versions. **Never trust remembered command ids — discover them:**
- PhotoCraft: `photocraft-cli commands` (CLI list; use the subcommand's own filter flags) — via MCP: `command_list` with a filter.
- PdfCraft: `pdfcraft-cli tools` — the full JSON-Schema tool table.
- `--help` on any subcommand for flags.
Only then compose the pipeline. A "command not found" usually means the id changed, not that the feature is missing.

## PhotoCraft CLI (stateless, one-shot)
```
photocraft-cli run <input> --cmd <id> [--params '{...}'] ... --out <output>
photocraft-cli info <input>
photocraft-cli convert ...      # discover flags: photocraft-cli convert --help
photocraft-cli batch ...        # discover flags: photocraft-cli batch --help
```
Verified recipes (v0.13.0):
- **Scan cleanup**: `photocraft-cli run scan.ppm --cmd image.autoTone --cmd filter.sharpen.smartSharpen --params '{"amount":60}' --out out.png`
- **Coloring-book page**: `photocraft-cli run photo.png --cmd filter.stylize.findEdges --out page.png`

## PhotoCraft MCP (stateful documents)
Tools: `command_list`, `command_run`, `command_batch`, `doc_new`, `doc_open`, `doc_inspect`, `doc_place`, `doc_render_preview`, `doc_export`, `doc_save`, `doc_close`, `jobs_list`, `jobs_cancel`.
- **Icon recipe**: `doc_new` (transparent canvas) → add shapes/gradients/type via `command_run` (discover ids with `command_list`) → `doc_export` PNG + ICO (ICO ≤ 256×256) → verify with `doc_render_preview` (bounded preview).
- **Iterative edit**: `doc_open` → `command_run` steps → `doc_render_preview` to inspect → adjust → `doc_save`/`doc_export`.

## PdfCraft CLI
```
pdfcraft-cli tools                        # JSON-Schema tool table
pdfcraft-cli info <file.pdf>              # structured facts (pages, fields, size)
pdfcraft-cli run <tool> key=value ...     # one-shot; e.g. run text_find doc=1 query=invoice
pdfcraft-cli run --script steps.json --root <dir> [--report]
```
- **Book recipe**: open the page PDFs → combine into one document → rotate/delete/move pages → page labels + bookmarks → metadata → protect → save.
- Render pages to PNG (discover the exact tool name via `tools`) so the agent can visually verify layout with read before declaring the book done.

## Pitfalls
- Early alpha: discover before running; versions move ids and parameters.
- The MCP servers are rooted at `/host` — files outside mounted projects are invisible to MCP tools; invoke the CLI directly for other paths.
- `render_preview` returns a BOUNDED image — for full-quality checks, export and view the file with read.
- ICO output is capped at 256×256.
- Batch: input and output directories must not overlap (verify with `--help` before running large batches).
- Desktop app binaries are NOT baked (they need a display) — CLI/MCP only.
- `mcp.json` is seeded on fresh volumes only: if the servers are missing in an existing container, add them manually (the JSON lives in the pi-docker Dockerfile/entrypoint).

## Verification
- `photocraft-cli run` on a test image produces the output file (nonzero size).
- `pdfcraft-cli info <pdf>` returns JSON with page facts.
- Startup provenance echo lines: `photocraft-cli installed from /opt/photocraft/bin @ v0.13.0 ...` and `pdfcraft-cli installed from /opt/pdfcraft/bin @ v0.13.0 ...`.
