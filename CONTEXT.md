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
- **Vendored fork** — `self-compact-pi-agent/`: working copy of the extension fork, pinned in `SYNC.md`, baked into the image at `/opt/pi-extensions/self-compact`, always re-synced to `~/.pi/agent/extensions/self-compact` by `entrypoint.sh` (the image is the source of truth; the extension keeps no on-disk state).

## Roles in this environment

- **Orchestrator** — the long-running `lead` session (thinking=med) using the `orchestrate` skill; coordinates subagents and acts as final gatekeeper/reviewer. Primary context-overflow risk.
- **Children** — pi-subagents worker processes (`coder`, `reviewer`, …); spawned without the parent's CLI flags, covered by the same extension via the env thresholds.
- **Architect** — 40k-window advisory model, rarely used, intentionally outside the extension's protection range.
