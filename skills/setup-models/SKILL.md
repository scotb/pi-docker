---
name: "setup-models"
description: "Apply a model profile to configure Pi's models, providers, and subagent role→model routing. Profiles: local (llama-swap single-GPU inference) and commercial (GitHub Copilot suite). Use when setting up a new machine or fresh state volume, switching between local and commercial inference, when a configured model or provider does not resolve, or when asked to configure models, providers, Copilot, or subagent model routing."
version: 1.0.1
created: "2026-11-24"
updated: "2026-11-24"
---
## When to Use
When configuring Pi on a new machine or fresh state volume, switching between local and commercial inference, when a model or provider in `settings.json` does not resolve, or when the user asks to configure models, a provider, Copilot, or subagent model routing.

## The two layers (both live in the state volume; neither is baked)
- `~/.pi/agent/models.json` — **custom providers only** (e.g. llama-swap). Built-in providers (`github-copilot`, `anthropic`, `openai`, …) need no entry.
- `~/.pi/agent/settings.json` — `defaultProvider`, `defaultModel` (the lead model), and `subagents.agentOverrides` mapping each agent role to a model. Bare model IDs resolve against `defaultProvider`.

## Profiles — the source of truth
`/opt/profiles/` (baked from the pi-docker repo, pinned to its commit):
- `local.json` — llama-swap: lead/coder=Qwen 27B, reviewer=gemma 31B, researcher=Qwen 35B-A3B, architect=Qwen 14B. Concurrency 1.
- `commercial.json` — GitHub Copilot: lead/worker/oracle=claude-opus-4-8, scout/researcher/reviewer/delegate=claude-sonnet-5-5. Concurrency 3 (cost cap).

A profile's `settings` block merges into `settings.json`; its `models` block (when present) writes `models.json`; its `runtime.parallelConcurrency` sets `parallel.concurrency` in `~/.pi/agent/extensions/subagent/config.json`.

## Procedure
1. Determine the target environment (ask; a fresh volume with a Copilot login and no llama-swap server is commercial).
2. Verify what is available: `pi /models` for built-in providers; for local, confirm the llama-swap server answers at `http://host.docker.internal:8007`. If a profile's model ID is not in the available list, stop and reconcile the profile in the pi-docker repo — never invent IDs.
3. Read `/opt/profiles/<name>.json`.
4. Merge its `settings` into `~/.pi/agent/settings.json` (preserve unrelated keys).
5. Write its `models` block to `~/.pi/agent/models.json` only when present.
6. Set `parallel.concurrency` in `~/.pi/agent/extensions/subagent/config.json`.
7. Verify: spawn a scout child with a trivial task; check the child's model in `subagent({ action: "status" })` matches the profile.

## Environment-specific guardrails
These rules from the `pi-subagents-workflow` skill exist for single-GPU shared inference; drop them when the active profile has no local provider:

| Rule | local (llama-swap) | commercial (Copilot) |
|---|---|---|
| Concurrency | 1 | 3 (cost cap) |
| KV-cache routing: child on a different model than the parent | required | not required — same-model children may run in parallel |
| Parent-sleep discipline (spawn is the final act of the turn) | required | not required |
| 2-hour dispatch timeout (`timeoutMs: 7200000`) | required | recommended |

## Pitfalls
- Drift: the profile in the repo is authoritative. If the volume's `settings.json` diverges, fix the profile in the pi-docker repo (edit → commit → rebuild) and re-apply — a hand-patched volume file is overwritten the next time a profile is applied.
- Commercial model IDs vary by tenant and change over time — always reconcile against `pi /models` before applying (step 2).
- `models.json` entries for built-in providers are redundant and can shadow the built-in catalog — write the file for custom providers only.

## Verification
- `pi /models` lists the default model and every model in the profile's overrides.
- A scout child completes a trivial task on the profile's model.
- `parallel.concurrency` in the subagent config matches the profile.
