# ADR 0004: Interrupted-Compaction Recovery in Subagent Children

## Status

Accepted (2026-10-22). Workflow mitigation shipped (skills
`orchestrate` 1.3.0, `pi-subagents-workflow` 1.1.0,
`tdd-ticket-dispatch` 1.1.1). Fork patch **implemented** in
`scotb/pi-subagents` branch `self-compact` (commit `f93d0e11`); dev-mode
forks pick it up live, a `build.sh` image rebuild is required to bake it
into the pinned image.

## Context

The `self-compact` extension (ADR 0001) is agent-driven: the agent saves a
`note_to_self` handoff, tools lock, a summary LLM call runs (several minutes
on the local model), the session compacts, and the note is returned
verbatim. The patched `pi-subagents` runner carries a drain-hold gate so a
child does not settle/terminate while compaction is in flight.

Observed failure (user-reported, verified in
`~/.pi/agent/logs/self-compact.jsonl`): a subagent interrupted while
compacting is never recovered — the run settles, a fresh spawn is required,
and the original context is lost. Evidence, session
`subagent-worker-c9202455-…-1`:

```
compact_success          (first compaction OK: 74% → 35%)
self_compact_call        (second cycle at 46.6k tokens)
compact_start            (agent idle)
compact_failed           {aborted:true, handoff:failed, attempts:1}
session_shutdown         {handoff:failed, locked:true}
session_start            {reason:startup, handoff:failed, locked:true}
compact_start            {trigger:"recovery after startup"}
session_shutdown         {handoff:compacting, locked:true}   ← killed again
session_start            {reason:startup, handoff:failed, locked:true}
compact_start            {trigger:"recovery after startup"}
session_shutdown         {handoff:compacting, locked:true}   ← killed again
```

The recovery path *does* fire (the extension auto-retries the compaction on
session start), but the runner kills the child again mid-recovery-compaction,
twice in a row.

Observed variant (user-reported): after the orchestrator resumes the child,
the resumed task is delivered as a prompt while the session is still locked
by the failed handoff. Every tool call in that turn is blocked by the
extension (`self-compact.ts`):

```
Tool "bash" is blocked by self-compact: <reason>. Every tool except
self_compact is blocked until compaction succeeds. Write your
note_to_self and call self_compact now.
```

The model cannot do its task, cannot self-compact usefully (it has no
task context to hand off), and the run dies. This is the *delivery*
side of the same defect: the prompt lands on a locked session because
nothing coordinates delivery with the in-flight recovery compaction.

## Decision

### Root cause — two compounding defects in the `pi-subagents` fork

**A. Kill paths bypass the drain-hold gate.**
In `src/runs/background/run-child-session.ts`, `registerInterrupt`,
`registerStop`, and `registerTimeout` all call `abortChild()`
(`startup.abort()` + `session.abort()` + ABORT_SETTLE settle timer) with no
compaction-in-flight check. The drain gate
(`src/runs/shared/child-lifecycle.ts`, `projectChildLifecycle`) only protects
the *natural final-drain* path. An explicit interrupt/stop, or a timeout,
therefore cancels the summary LLM call mid-compaction →
`session_compact_failed(aborted)` → handoff saved as `failed`. The session
file itself is intact — a cancelled compaction does not destroy the branch —
so what is lost is the *recovery path*, not the data.

**B. Resumed runs inherit the original absolute deadline.**
`src/runs/background/async-execution.ts:2040-2044`:
`deadlineAt = absoluteDeadlineAt ?? Date.now() + timeoutMs`, and the
recovery descriptor (`recovery-descriptor.json`, written at line ~2168)
persists that absolute deadline. On resume:
`timeoutMs = absoluteDeadlineAt - Date.now()`. If the remainder is ≤ 0 the
resume is rejected outright ("The source run's absolute deadline expired
before recovery could launch"); if the remainder is shorter than the
recovery compaction (minutes on the local model), `terminateForTimeout →
abortChild()` kills the resumed child mid-recovery-compaction — exactly the
second and third kills in the evidence timeline. The self-compact
extension's `session_start` recovery (`recover()` → locked, schedules a
"recovery after startup" compaction 500 ms after startup if idle) can never
complete.

**C. Settlement policy does not recognize the case.**
`src/runs/shared/abort-recovery.ts`, `planAbortRecovery`: `timedOut` →
settle("elapsed timeout"); explicit stop/interrupt → settle;
`compactionAbortCandidate` (afterCompactionSettlement + zero-usage aborted
terminal) refuses an unsafe resume with the diagnostic "Compaction-induced
child abort could not be resumed safely". The run settles; the orchestrator
must spawn fresh — the intact session file is not reused.

### Mitigation shipped (2026-10-22, workflow only)

- Workers are **always dispatched with an explicit 2-hour timeout**
  (`timeoutMs: 7200000`); the extension default stays 30 minutes.
  Compaction is a few-minute event near the end of a window, so the 2-hour
  window sharply cuts the odds of an interrupt landing mid-compaction.
- The 2-hour mark is an **assessment point** (assess / resume / take over),
  not a wall clock — this is what contained the 4-hour thrash loop of 2026-10.
- Rationale for reverting the 2026-10-18 30-minute policy: on-track workers
  too often just needed a bit more time, and mid-task interrupts are
  disruptive; the old 4-hour thrash was a failure of the previous coder
  model, not of the timeout length.

### Fork patch (implemented, `scotb/pi-subagents` branch `self-compact`, commit `f93d0e11`)

1. **Resume delivery gate** in `run-child-session.ts` (new — covers the
   locked-prompt variant): on a file-storage reopen whose session file
   exists, the resumed task is held through a 3 s grace window. If a
   `compaction_start` lands during the window (a recovery compaction), the
   task is re-routed to a queued `followUp` so it lands after the handoff
   note is delivered — never as a prompt on the locked session. A 10-min
   cap and a 15 s compaction-failure grace timer settle with a diagnostic
   instead of holding forever. The final drain is suppressed while the gate
   is held or a re-routed follow-up is pending.
2. **Drain-gate the kill paths** in `run-child-session.ts`: an
   interrupt/stop/timeout that lands while a compaction is in flight is
   deferred until the final `compaction_end` (or a taking-over
   `turn_start`/`agent_start`), capped at 10 min — the summary call can no
   longer be cancelled mid-flight, so the handoff no longer ends `failed`.
3. **Fresh recovery budget on resume** in `async-execution.ts`: a resumed
   run whose absolute deadline has expired gets a fresh 30-minute budget
   (`RECOVERY_RESUME_BUDGET_MS = DEFAULT_ASYNC_TIMEOUT_MS`); a remainder
   under 10 minutes is lifted to `RECOVERY_RESUME_MIN_MS`. The extended
   `deadlineAt` propagates to the recovery descriptor so later resumes
   inherit it. The extension default (30 min) is unchanged.
4. **Verification**: `tsc --noEmit` clean; three new unit tests in
   `test/unit/run-child-session.test.ts` (re-route to follow-up, normal
   prompt delivery when no compaction starts, deferred timeout kill); full
   suite shows no new failures vs baseline. Item 3 of the pending plan
   (`abort-recovery.ts` diagnostic) was dropped: with kills drain-gated and
   delivery gated, a mid-compaction kill no longer produces the
   unresumable `compactionAbortCandidate` state it was meant to diagnose.

### Live e2e verification (2026-10-22, dev-mode fork)

- **Stop mid-compaction** (run `4c3bd650`): a user stop landed mid-summary;
  the drain-gated kill deferred, `compact_success` + `handoff_delivered`
  intact, clean shutdown. Pre-patch this produced `compact_failed
  {aborted:true, handoff:failed}`. Note: a `stopped` run is **terminal by
  design** — the runner refuses to resume it ("was stopped and cannot be
  resumed"). The resumable interrupt is the timeout.
- **Full compaction→continue cycle** (runs `195bbdb9`, `68eb2884`): real
  children self-compacted (52 s / 116 s local-model summaries), received
  the handoff note, and continued the task to completion.
- The e2e caught a regression in `f93d0e11`: the recovery budget floor
  silently extended fresh-spawn timeouts (120 s → 600 s, verified twice in
  run descriptors). Fixed in `45327ce1` — budget logic extracted into
  `extendRecoveryResumeBudget()`, resume-only — with six unit tests.
- **Timeout → resume → continue** (runs `97af52eb` → `36b7188b`): with
  `45327ce1` live, a true 120 s deadline was respected and the run timed
  out at exactly 120000 ms (`timedOut: true`). Resuming it revived the
  session; the child read the input, self-compacted (`compact_success` +
  `handoff_delivered`), re-read the first line, and wrote the result file —
  completing the task ~51 minutes past the original (expired) deadline,
  live-verifying the fresh `RECOVERY_RESUME_BUDGET_MS` grant (an inherited
  expired deadline would have killed it immediately).
- Remaining (low value): a timeout landing exactly mid-summary (the
  deferral mechanism is identical to the stop test above, which proved it
  live), and the re-route path against a genuinely failed handoff (hard to
  force live without breaking the summarizer).

## Consequences

- 2-hour dispatch means longer-running workers; the 2-hour assessment (read
  the TDD ledger / session tail) is now mandatory to keep the 4-hour-thrash
  failure mode from returning.
- The fork patch lives in the dev-mode fork (`self-compact` branch);
  the pinned image is unaffected until a `build.sh` rebuild bakes in the
  new SHAs. Until then, a mid-compaction interrupt (rare under the 2-hour
  dispatch policy) still loses the run in image-pinned environments.
- The "never `self_compact` while a subagent is running" pitfall stands
  (the parent's own compaction during a child run is a separate, still-
  misbehaving path).
