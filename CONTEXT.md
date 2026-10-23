# CONTEXT — domain language

## Context management (self-compact)

- **Context window** — the active model's max token capacity (`contextWindow` in models.json; 131k for lead/coder/reviewer, 40.9k for architect).
- **Soft line (notice)** — usage threshold where the footer bar appears. No behavior change. Env: `SELF_COMPACT_SOFT_AT` (50%).
- **Warning line** — usage threshold where the agent is guided to write its handoff note and compact soon. Env: `SELF_COMPACT_AT` (70%).
- **Forced line (tool lock)** — `warning + buffer`, capped at 90% of window (85% in this image). Every tool except `self_compact` and `view_context` is blocked until the agent compacts.
- **Handoff** — the `note_to_self` the agent must supply to `self_compact`; delivered back verbatim after compaction.
- **Threshold precedence** — `--compact-*` CLI flag > `SELF_COMPACT_*` env > shipped default (10/20/30). Children (pi-subagents) inherit only the env level.
- **Split-turn summary** — compaction case where the cut point lands mid-turn; the current turn is summarized in two LLM calls (history + turn-prefix). The turn-prefix prompt format changed in Pi 0.87.1 (`# Conversation`/`# Instructions`); the vendored extension recognizes both old and new shapes.
- **Keep-recent floor** — Pi's `keepRecentTokens` (default 20k); the extension refuses `self_compact` when nothing lies below it ("nothing to compact"). This makes the extension inert on the 40k `architect` model by design choice.
- **Overflow backstop** — Pi's native one-shot compact-and-retry on a provider context-overflow error; the extension cancels native threshold/overflow compaction and funnels it through its own handoff transaction. Depends on llama-swap's error text matching Pi's overflow patterns (llama.cpp: "the request exceeds the available context size" — matches).
- **Vendored fork** — `self-compact-pi-agent/`: SHA-pinned baked extension. Working copy pinned in `SYNC.md`, staged in the image at `/opt/pi-extensions/self-compact`, always re-synced to `~/.pi/agent/extensions/self-compact` by `entrypoint.sh` (the image is the source of truth; the extension keeps no on-disk state).

## Extension packaging

**Staging area**:
The image-side directories where baked artifacts are staged at build time: `/opt/pi-extensions/` (extension code, the hoisted npm dependency tree, pinned binaries, vendored local extensions) and `/opt/pi-skills/` (skill sources under `mattpocock/` and `local/`). The entrypoint reads staging and installs from it into `~/.pi/agent/` on every container start; it never writes there.
_Avoid_: staging copies, image copies, the hermes directory

**Baked extension**:
Extension code staged into `/opt/pi-extensions/` at image build time and installed into `~/.pi/agent/extensions/` by the entrypoint on every container start, pinned to an exact version. Pinned by git SHA (forks), npm lockfile (upstream packages), or a vendored file in this repo (local code).
_Avoid_: vendored fork, npm extension, installed package

**State volume**:
The named Docker volume (`pi-state`) holding `~/.pi` — an extension's persistent data (databases, caches, config files). Survives image rebuilds; the image owns code, the volume owns state. Selected at runtime with `PI_VOLUME`.
_Avoid_: extension data, local state, host state

**Save-restore install**:
Entry-point install pattern for an extension that writes state inside its own install directory: state files are moved aside, the directory is replaced cleanly from the image, then the state files are restored.
_Avoid_: overlay install

**Provenance echo**:
The line the entrypoint prints at startup recording each installed extension's source and pinned version, so the running code is always auditable.
_Avoid_: install log

## Skills

- **Baked skill** — a skill (a `SKILL.md` directory) staged into `/opt/pi-skills/` at image build time, pinned to an exact version, and installed into `~/.pi/agent/skills/` by the entrypoint on every container start. The image owns skill code; the volume owns state. The entrypoint reinstalls the directory from the image on every start — hand-dropped skills are ephemeral by design.
- **Skill manifest** — `skills-manifest.txt` at the repo root; the curated, dependency-closed list of skills extracted from the upstream mattpocock/skills repo at build time. A listed path missing at the pinned SHA fails the build (fail-fast; pin to a prior tip to keep building). _Avoid_: skill allowlist, skill whitelist
- **Drafting area** — `~/.pi/agent/pi-hermes-memory/skills/` on the state volume, where the `skill_manage` tool writes new global skills. Promotion to the baked set = copy into `skills/`, commit, rebuild the image.

## Docs

**Baked docs**:
This repo's `docs/` (ADRs, agent conventions, integration spec) staged into `/opt/docs/` at image build time, pinned to this repo's commit, so the environment's rationale is readable from any session — not just when the pi-docker repo is mounted. The `environment` skill (first-party, in `skills/`) is the discoverable map onto it.
_Avoid_: repo docs, docs volume

## Craft apps (image + PDF)

**Craft apps**:
The two headless ArtCraft editors baked into the image: PhotoCraft (raster image editing — cleanup, retouch, shapes, export) and PdfCraft (PDF workbench — combine, split, page ops, forms, protection). Each is a pinned CLI release under `/opt/photocraft` and `/opt/pdfcraft` (version + sha256, on `PATH`) with an MCP server registered in `~/.pi/agent/mcp.json` (seeded on fresh volumes, rooted at `/host`). The desktop apps are not baked (they need a display).
_Avoid_: image tools, pdf editor, ArtCraft

**Craft CLI**:
The stateless command interface of a craft app (`photocraft-cli`, `pdfcraft-cli`): one-shot pipelines (`run`/`batch`), command discovery (`commands`/`tools`), direct file I/O. Prefer the CLI for one-shot work; the MCP servers exist for stateful, iterative document work.
_Avoid_: craft API, craft MCP

**Craft MCP roots**:
The directory restriction the craft MCP servers apply to document access (both rooted at `/host`, the live-mounted project root), scoping agent-driven document work to mounted projects. Direct CLI invocations are not restricted by the roots.
_Avoid_: craft sandbox, mount root

## Roles in this environment

- **Orchestrator** — the long-running `lead` session (thinking=med) using the `orchestrate` skill; coordinates subagents and acts as final gatekeeper/reviewer. Primary context-overflow risk.
- **Children** — pi-subagents worker processes (`coder`, `reviewer`, …); spawned without the parent's CLI flags, covered by the same extension via the env thresholds.
- **Architect** — 40k-window advisory model, rarely used, intentionally outside the extension's protection range.
