---
name: "orchestrate"
description: "Orchestrator loop for feature tickets: dispatch a worker child, run the completion gate, dispatch a read-only reviewer, adjudicate against primary sources, close with a record. Use when the user says \"orchestrate\", \"run ticket N\", or wants a ticket implemented via the worker→reviewer→close flow."
version: 11
created: "2026-09-14"
updated: "2026-09-24"
---
## When to Use
Use when the user says "orchestrate <task/ticket>", "run ticket N", or asks to implement a ticket through the worker → gate → reviewer → final review → close loop. The orchestrator (this session) coordinates child subagents; it does NOT implement features during child runs — it owns tickets, design locks, gates, docs, adjudication, and close records. One ticket at a time; one writer per working tree.

## Procedure
1. Boot (entry): load ticket state. Find the issue files (e.g. .scratch/<feature>/issues/ or the repo's tracker); read the full ticket + PRD + prior tickets' ## Comments close records (they carry locked design decisions, adjudications, and deferred gates). SIZE GATE: if the ticket is too big for one child run (heuristic: 4–5+ hours of frontier-model effort), do NOT dispatch — stop and alert the user with a proposed split (ticket creation lives in a separate skill; the orchestrator only evaluates size and raises the alert). Pin the environment BEFORE dispatch — verify, don't assume: runtime/SDK versions, dependency availability (offline package caches), the exact working test command, and sandbox capabilities (browser? vision? network? DB? is /tmp persistent?). Record what you verified; environments change and stale 'verified' notes cause real failures.
2. Lock the ticket contract and write it into the dispatch prompt: (a) in-scope file list, (b) design decisions D1..Dn (locked — no relitigating), (c) behavior contract: testable behaviors ONLY, one named test per bullet, positive and negative (compiler-enforced type guarantees go in an API/type note, not the contract), (d) test commands in bare form (no pipes), (e) constraints (deps, style, commit rule), (f) evidence requirements. If the ticket is TDD-scoped: red→green vertical slices, per-slice red+green evidence mandatory, staged reds banned.
3. Dispatch the worker: one async subagent run; the worker is the sole writer for that run. Spawn with context='fresh' — never fork the orchestrator's context into an implementation child (see Pitfalls); the self-contained prompt from step 2 IS the handoff. Spawn with a 2-hour timeout (timeoutMs 7200000) — the 30-minute default kills converging runs on local inference. Worker dispatch template:
---
ROLE: Implementation worker for ticket N: <title>. You own the working tree for this run.
REPO/BRANCH: <path> / <branch>
IN SCOPE (only these files): <list>
DESIGN DECISIONS (locked, do not relitigate): D1..., D2...
BEHAVIOR CONTRACT (one named test per bullet): <bullets>
TEST COMMANDS (bare, no pipes): <commands>
CONSTRAINTS: <deps/style>; exactly one commit, conventional subject, body references the ticket; no push.
TDD (if scoped): one vertical slice at a time — one test → run, observe red → minimal implementation → run, observe green → next. Log per-slice evidence (command + observed failure/pass). Never stage reds (no commenting out or reverting implementation to fake reds).
REPORT (≤~120 lines): what was done; per-slice/test evidence; deviations from this prompt with reasoning; files changed; commit hash.
---
4. Orchestrator discipline during child runs (local inference / shared model): write ALL description of the work in text BEFORE the spawn call (or in an earlier turn) — the spawn call is the final act of the turn. After the call returns, emit at most one short status line, then end the turn and resume on the native completion notification. Every token of orchestrator prose AFTER the spawn call competes with the child's startup for the same local model. No polling, no sleep loops, no file reading for fun, no model-consuming analysis while a child runs. Results arrive via the completion notification. ON TIMEOUT (not automatic failure): assess progress first — git status for real edits, tail of the child session for convergence (errors shrinking vs the same error repeating). Converging → resume the run (action:resume, short continue message, fresh 2-hour timeout). Spinning/wheel-running → stop and re-dispatch a smaller scope.
5. Completion gate (orchestrator, in order; record ALL evidence in the ticket):
1. Full suite run BY YOU (bare command; record pass/fail counts) — do not trust the worker's claimed results.
2. Git hygiene: expected commit(s) (subject convention + ticket in body), clean tree, changed files ⊆ in-scope list.
3. Process evidence: if TDD, run the project's ledger/verifier — the verifier is AUTHORITATIVE over worker prose; adjudicate each warning and record it. Non-TDD: evidence = your suite run + worker report + reviewer + final file review.
4. Adjudicate every worker-reported deviation (accept/reject + reasoning → ticket).
6. Dispatch the reviewer: one async run, fresh context, read-only child (NO shell/git/tests/edits — say so explicitly), HARD output budget ~120 lines in the prompt (a run has died of output length before; keep the budget even after raising token caps). Reviewer children have NO web access → supply pinned framework facts inline, or expect claim-level findings you must adjudicate. Template:
---
ROLE: Read-only code reviewer for ticket N. You have NO shell, git, test, or edit tools — do not attempt to run anything.
SCOPE: commit <hash> implementing ticket <path>.
AXES: 1) Standards — does it follow the repo's documented conventions (<refs>)? 2) Spec — does it implement the ticket + behavior contract below?
BEHAVIOR CONTRACT: <bullets>
DESIGN DECISIONS (locked): <list>
KNOWN/ACCEPTED (do not re-flag): <documented P3s, accepted deviations>
PINNED FACTS (treat as given, no web): <framework facts with citations>
OUTPUT (HARD BUDGET ~120 lines): findings as P1 (blocks: spec violation/bug) / P2 (should fix) / P3 (note), each with file:line + one-line justification; verdict PASS or BLOCK (P1+ only); ≤5-line summary.
---
7. Final review + adjudication: read EVERY changed file yourself. Adjudicate every reviewer finding against primary sources (framework docs, source, issue trackers) BEFORE rework — a reviewer BLOCK is a hypothesis, not authority, and the orchestrator's own earlier adjudication can be wrong too: when it is, record an erratum, don't silently rewrite history. If a genuine P1/P2 is confirmed: re-dispatch a focused worker run (orchestrator inline fixes only between child runs — never while a child may write), then re-run the gate. P3s: document in the ticket, don't fix.
8. Close: set the ticket resolved; append a close-gate record to the ticket's ## Comments: orchestrator-run suite counts + command, commit hash(es), reviewer verdict + per-finding adjudication with citations, accepted deviations, documented P3s. Commit the record (docs commit, ticket ref in body). Residual risks that can't be verified now → append an explicit bullet to a later ticket with a CONCRETE verification method and discriminating value. Update the project workflow doc + persistent memory with new lessons.
9. Runtime verification (when the close gate requires observed behavior — config cascades, hydration, live services, browser): a green suite is not a runtime check. Plan a discriminating check: use a NON-DEFAULT value (e.g. an override that differs from the fallback) so the fallback can't mask the behavior under test; record exact observed values (screenshot/JSON/log) in the ticket. On runtime failure: first check the most-basic 'is the feature even enabled' (one-attribute omissions cause silent total failures), validate against a pristine control before blaming the environment, and treat silent-by-design behavior (no errors, no traffic) as a signal, not noise.
## Pitfalls
Never call self_compact while a subagent is running — the user's context-management extension misbehaves when compaction lands mid-subagent (correction from user, 2026-09-24). Compact before dispatching the child, or after all children have ended, exactly like any other activity that must wait for the child.
## Verification
1. Orchestrator-run full suite green with recorded counts (command + N/N).
2. Git: expected commit with conventional subject + ticket body; tree clean; changed files ⊆ in-scope list.
3. Every reviewer finding adjudicated (accept/reject + citation) and recorded in the ticket; BLOCK adjudicated against primary sources before any rework.
4. Close record appended to the ticket and committed; ticket Status: resolved.
5. Residual risks deferred with concrete, dated gates on later tickets.
6. New lessons (tool quirks, environment facts, adjudications/errata) committed to memory and the project workflow doc.