# ADR 0001: Self-Compact Context Management Extension

## Status

Accepted (2026-10-15). Implemented and proven end-to-end (including in
async subagent children).

## Context

Pi's built-in compaction fires on a fixed schedule and produces a generic
summary. Long-running agent sessions — especially autonomous subagent
children — lose goal, decisions, and next-action state at exactly the moment
context pressure peaks. We needed compaction that is (a) agent-driven,
(b) format-aware of what an agent must carry forward, and (c) safe to run
while the agent's runner is mid-flight (no shutdown races).

## Decision

Adopt a custom `self-compact` extension (fork:
`scotb/self-compact-pi-agent`, branch `deploy`), paired with a patched
`pi-subagents` runner (fork: `scotb/pi-subagents`, branch `self-compact`):

- **Thresholds**: soft 50% / warning 70% / forced 85% of the active model's
  context window (env-configurable; image defaults set in the Dockerfile).
- **Agent-driven compaction**: the extension surfaces a `self_compact` tool
  and compacts on threshold crossing; the agent decides *when* within the
  bands, and must write a `note_to_self` handoff that is returned verbatim
  after compaction.
- **Custom summary format**: goal, constraints, progress (done / in
  progress / blocked), key decisions, exact next action, critical context.
- **Runner drain-hold gate**: the pi-subagents child runner must not settle
  or terminate while compaction is in flight (agent_end / terminal-stop
  gates + settle-skip). Without this, children race `session_shutdown`
  against an in-progress summary attempt.
- **Format compatibility**: the extension recognizes Pi 0.87.1's
  split-turn summary prompt format (older versions failed compaction
  against it).
- **Audit logging**: every lifecycle event is journaled to
  `~/.pi/agent/logs/self-compact.jsonl` for post-mortem debugging.

## Consequences

- Two more pinned, public forks to maintain (`build.sh` resolves their
  branch heads to SHAs; the Dockerfile fails fast on unpinned builds).
- The extension is source-only (jiti `.ts`); loading changes requires a
  full container restart, not `/reload`.
- Iteration path: `pi.sh --dev` mounts the live forks from `/data/apps`;
  the entrypoint installs from them when `PI_DEV=1`.
- Compaction behavior in children depends on *both* forks being at
  compatible revisions — they are bumped together in `build.sh`.
