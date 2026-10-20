---
name: "pi-subagents-workflow"
description: "Correct patterns for using pi-subagents on a local shared-inference setup: native async wake (no manual wait arming), 30-minute default timeout with check-in/resume/takeover, fresh-context worker children, parent-sleep discipline, KV-cache model routing. Use when launching subagents, managing child runs, or a child times out, spins, or goes silent."
version: 1.0.2
created: "2026-08-10"
updated: "2026-10-20"
---
## When to Use
When launching any subagent, managing subagent workflows, or a child times out, spins, or goes silent. Current policy (2026-10-18): native async wake (manual subagent_wait arming is obsolete), 30-minute default timeout with check-in/resume/takeover, fresh-context worker children, and parent-sleep discipline on shared local inference.

## Procedure
1. Launch implementation/worker children with the simple async form: subagent({ agent: '<worker-model>', task: '<self-contained prompt>', async: true }). The task IS the handoff — repo/branch, in-scope files, locked design decisions, behavior contract, bare test commands, constraints, report format (≤~120 lines). Never launch an implementation child with context:'fork' (workflowScript form): a 3.3MB fork once consumed an entire small-model run on prompt echo. Fork only children that genuinely need the parent's conversation.
2. NEVER pass gate= or acceptance= for investigation/read-only tasks — this triggers acceptance verification that fails before the task completes.
3. NEVER pass worktree:true unless the git working tree is clean.
4. NEVER pass turnBudget or a hard toolBudget to mutation-capable children.
5. For read-only scouts/research: mission: false (no mission tracking needed).
6. Use simple ASCII task strings without backslashes, ampersands, or other JS-breaking characters.
7. After spawning an async child: return control. Pi NATIVELY wakes this session when the child completes — no subagent_wait arming, no status polling, no sleep loops (v1's nonBlocking subscription pattern is obsolete). bg_wait is only for non-native work (provider/detached runs) when a same-turn result is needed.
8. Parent-sleep discipline (shared local inference): write ALL description of the work in text BEFORE the spawn call — the spawn call is the final act of the turn. After the call returns, emit at most one short status line, then end the turn and resume on the native wake. Every parent token after spawn competes with the child's startup for the same local model.
9. Timeouts: spawn children with the DEFAULT 30-minute timeout (no timeoutMs). A timeout is an assessment point, not a failure: git status for real edits + tail of the child session for convergence. Converging/on-track → resume the run (action:resume, short continue message). Spinning/wheel-running (same error repeating, malformed commands, re-introduced syntax errors) → interrupt and take over the partial tree (triage with git status + diff, run the suite, finish directly, commit) or re-dispatch smaller. The 2-hour timeout that predated this policy let a run spin 4h/104k tokens before anyone noticed (2026-10-18).
10. NEVER interrupt a child just because it is silent — silence is normal during long tool calls. Only intervene on an actual needs_attention or failed signal, or at the timeout assessment in item 9.
11. Model routing (KV cache): run the child on a DIFFERENT model than the parent (e.g. coder for the worker, lead for the parent) — it unloads the parent's KV cache and loads the child model. Past KV-overrun issues came from two same-model instances running at once.
12. For complex multi-step workflows, use the Fable mode sequence: scout → oracle → worker → reviewer → worker (fix) → reviewer (final).

## Pitfalls
- 3.3MB context fork into an implementation child consumed an entire small-model run on prompt echo (2026-10) — context:'fresh' + self-contained prompt only.
- 4-hour spin loop: 59 turns / 104k tokens, malformed bash, re-introduced syntax errors, repeated hits on the same failure — hidden by a 2-hour timeout (2026-10-18). The 30-minute default + check-in is the countermeasure.
- Parent token contention: orchestrator prose after the spawn call slows the child's startup on the shared local backend (2026-09).
- Never self_compact while a child is running — the user's context-management extension misbehaves when compaction lands mid-subagent (user correction, 2026-09-24). Compact before dispatching the child, or after all children have ended.

## Verification
1. Subagent completes without failure or unnecessary interruption.
2. Child reports success/failure status; results arrive via the native completion wake (no polling).
3. On timeout: assessment (git status + session tail) recorded, and the chosen action (resume / takeover / re-dispatch) is justified by observed state.
4. Output is available and complete when retrieved via subagent status.