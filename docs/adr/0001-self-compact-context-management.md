# ADR 0001: self-compact extension, baked into the image

- **Status:** accepted
- **Date:** 2026-07-21

## Context

Long-running autonomous runs on the local llama-swap backend (lead, 131k nominal window, up to ~98k output tokens per turn) halt unrecoverably when context crosses ~80%: a large thinking block plus a large tool result push the next LLM call past the window, and the stop is not recoverable without a manual `/compact` and workflow restart.

The `self-compact-pi-agent` extension addresses this proactively: three usage thresholds (notice / warning / **forced tool lock**), a mandatory `note_to_self` handoff, and a custom compaction summary that preserves goal, decisions, progress, and next action.

## Decision

1. **Deploy host-side via the image (bake + runtime copy).** The extension source is the user's fork of `disler/self-compact-pi-agent`, cloned at `self-compact-pi-agent/` (gitignored from this repo; own git with `origin`=fork, `upstream`=disler; local patch commits on branch `local` — see `SYNC.md`). The Dockerfile `COPY`s `apps/self-compact/` from the working tree to `/opt/pi-extensions/self-compact`, and `entrypoint.sh` re-syncs it to `~/.pi/agent/extensions/self-compact` on every container start (always-copy; the extension stores no on-disk state). Rejected alternatives: npm `pi install` (unpublished package), host-side deploy script (second source of truth), and committing the fork into this repo (it must stay a live fork to pull upstream updates).
2. **Thresholds 50/70/85 of the window** (`SELF_COMPACT_SOFT_AT`/`SELF_COMPACT_AT`/`SELF_COMPACT_BUFFER` env in the Dockerfile), not the shipped 10/20/30 — matches observed behavior (no issues below ~80%, manual compact at 85% is reliable) and leaves ~20k headroom for the forced handoff turn. Env-based so pi-subagents children inherit the same thresholds (they are spawned without parent CLI flags).
3. **Local patches to the vendored fork** (not upstreamed yet):
   - Recognize Pi 0.87.1's split-turn summary prompt format (`# Conversation`/`# Instructions`) — without this, every split-turn compaction fails, which is the common case in the exact failure scenario.
   - `SELF_COMPACT_*` env fallback in threshold resolution.
   - `package.json` `"pi"` manifest + `index.ts` shim so Pi discovers the deployed directory.
   - Parity test honors `PI_LOADER_PATH` (image runs Pi from `/opt/pi`, not npm-global).

## Consequences

- A fresh host with the image + `~/.pi` mount is complete (one-stop shopping). Extension version is exactly what's in the image.
- The 40k `architect` model is outside the extension's effective range (keep-recent floor 20k > forced line); accepted — architect is rarely used and native overflow recovery remains its backstop.
- Occasional edge cases remain (e.g., long thinking at ~84% can still overflow one turn before the lock converges); accepted per "works within tolerance" bar.
- Acceptance gate: unit + parity suites (43 tests) against `/opt/pi` must pass before image rebuilds; live verification = threshold walk + forced-overflow repro (Phases 2–3 of the bring-up plan).
