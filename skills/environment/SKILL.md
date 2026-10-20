---
name: "environment"
description: "How the pi-sandbox container is constructed and operated: image owns code, volume owns state; baked vs staging area vs drafting area; pinning, rebuild, rollback, skill promotion, `--dev`, volume recovery. Use when asked how the environment is built, where something lives, how to update it, or when a skill/extension seems to have vanished."
version: 1.0.3
created: "2026-10-19"
updated: "2026-10-20"
---
## When to Use
Use when asked how this environment is constructed, where something lives (skills, extensions, state, models), why something vanished after a rebuild or container start, or how to update the environment (promote a skill, bump a pin, rebuild, roll back, swap volumes). This is a map of the environment, not a task procedure — read it, then act.

## The ownership rule
- **The image owns code.** Everything under `/opt` is baked at build time, pinned to an exact version, and reinstalled from the image on every container start. The entrypoint is read-only with respect to user config, with two exceptions: `~/.pi/agent/skills/` is reinstalled from the image on every start, and pi-lean-ctx's default `config.json` is seeded on a fresh volume.
- **The volume owns state.** `~/.pi` is the named Docker volume `pi-state` (selected at runtime with `PI_VOLUME`): sessions, settings, memory, extension state, hand-dropped files.
- Corollary: **hand-dropped code is ephemeral by design.** Anything that must persist as code must be baked (repo → commit → rebuild).
- The startup **provenance echo** (the lines the entrypoint prints) records each installed artifact's source and pin — the live, authoritative view of what is running.

## Map: what lives where
**Image (baked, image-owned):**
- `/opt/pi` — Pi CLI built from source at a pinned commit (`/opt/pi.sha`)
- `/opt/pi-extensions` — **staging area** for extensions: `pi-subagents/` + `self-compact/` (git-SHA-pinned forks), `npm/` (upstream packages from the committed lockfile + hoisted `node_modules` + `manifest.json`), `lean-ctx/` (pinned native binary, sha256-verified), `tdd-ledger/` (vendored — this repo is the source of truth)
- `/opt/pi-skills` — **staging area** for skills: `mattpocock/` (upstream, curated by `skills-manifest.txt`, SHA-pinned) + `local/` (first-party, from this repo's `skills/`)
- `/opt/docs` — this repo's `docs/` baked in: ADRs, agent conventions, integration spec
- `/opt/playwright-browsers` — headless Chromium; `/usr/local/bin/page-shot` — URL→PNG renderer (`page-shot <url> <out.png>`; capture is available to every model, viewing the PNG requires vision)

**Volume `pi-state` (`~/.pi`, volume-owned):**
- `agent/extensions/` — installed extensions (reinstalled from staging on every start)
- `agent/skills/` — installed skills (reinstalled from staging on every start; ephemeral)
- `agent/pi-hermes-memory/` — **drafting area** (`skills/` is where `skill_manage` writes new global skills) + cross-session memory store
- `agent/projects-memory/` — per-project memory
- `agent/models.json` — llama-swap endpoints/models (host-provided config; never baked)
- **Model capabilities (host-provided — change with model swaps):** as of 2026-10 the lead and coder models are vision-capable (can view PNGs/screenshots); the reviewer model is not. Screenshots are first-class proof-of-work for lead/coder.
- `agent/web-search-cache/`, `tdd-ledger/` state, `~/.pi/lean-ctx` data dir, sessions, settings

**Live mounts (host):**
- current project → `/host/<path>` (one Pi identity per project directory)
- `/data/apps/{pi-subagents,self-compact-pi-agent}` — live extension forks on the host, used **only** with `pi --dev`

## Names (canonical — full glossary in the pi-docker repo's `CONTEXT.md`)
- **baked** — staged into the image at build time, pinned, reinstalled by the entrypoint on every start (extensions, skills, docs, binaries)
- **staging area** — the image-side `/opt/pi-extensions` + `/opt/pi-skills` the entrypoint installs from
- **drafting area** — `~/.pi/agent/pi-hermes-memory/skills/` on the volume; where new skills are born (not the staging area)
- **state volume** — the named Docker volume holding `~/.pi`
- **provenance echo** — the startup lines recording source + pin of everything installed
- **save-restore install** — the entrypoint pattern for an extension that writes state inside its own install dir (pi-lean-ctx)

## Pins & upgrades
| Artifact | Pin |
|---|---|
| Pi monorepo | git SHA (`FORK_HASH`) |
| pi-subagents / self-compact forks | git SHA (required build args) |
| Upstream npm extensions | committed `extensions/extension-lock` lockfile |
| lean-ctx binary | version + sha256 (build args) |
| mattpocock skills | git SHA + `skills-manifest.txt` (missing entry fails the build) |
| First-party skills, tdd-ledger, docs | this repo's commit |

An upgrade is a deliberate event: bump the pin → `./build.sh --tag pi-sandbox:$(date +%F)` → verify the provenance echo. The Dockerfile refuses to build with empty hashes — always go through `./build.sh`.

## Operations
- **Promote a skill**: iterate in the drafting area → copy into `skills/<name>/` in the pi-docker repo → commit → rebuild. Once promoted, delete the draft from the drafting area or it gets advertised twice.
- **Rebuild / roll back**: date-tagged builds; run an older tag to roll back (`pi --tag 2026-10-15`). `latest` is always tagged too.
- **`--dev`**: mounts the live extension forks from the host's `/data/apps` (must exist there); the entrypoint installs from them instead of the image-baked copies (for iterating on the forks).
- **Volume recovery**: `PI_VOLUME=<name> pi` — volumes coexist and nothing is deleted; a fresh start is a new volume name, a rollback is the old one.

## Rationale
`/opt/docs/adr/` — 0001 (self-compact context management), 0002 (baked extensions with volume-held state), 0003 (baked skills with a curated manifest). Read them for the why and the rejected alternatives.

## Staleness rule
If this document contradicts the filesystem or the startup provenance echo, this document is stale — trust the filesystem and the echo, and flag the skill for an update in the pi-docker repo (edit it in the same commit as the Dockerfile change it describes).
