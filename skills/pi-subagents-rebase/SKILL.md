---
name: "pi-subagents-rebase"
description: "Rebase the pi-subagents self-compact fork onto the latest upstream main. Use when asked to rebase pi-subagents, sync the fork with upstream, update the mounted pi-subagents volume to the latest main, or after upstream releases new versions. Covers the fork layout, conflict-resolution pattern, known test failures, and verification."
version: 1.0.0
created: "2026-10-27"
updated: "2026-10-27"
---

## When to Use

Use when asked to rebase `/host/data/apps/pi-subagents` (branch `self-compact`) onto
upstream main, sync the fork, or confirm the mounted volume has the latest upstream
`main`. The fork adds child self-compaction to pi-subagents; it intentionally
diverges from upstream, so rebases produce conflicts that follow a known pattern.

## Repo layout

- `/host/data/apps/pi-subagents` — the fork. Remotes: `origin` = `scotb/pi-subagents`,
  `upstream` = `nicobailon/pi-subagents`.
- Branch `self-compact` carries the fork commits; branch `main` tracks upstream.
- Fork point (where `self-compact` diverged from upstream): see the rebase log in
  `SELF-COMPACT-FORK.md` in the fork repo.
- `SELF-COMPACT-FORK.md` in the fork repo is the authoritative fork documentation:
  intentional divergence, known failures, rebase log. Read it first.

## Procedure

1. `git fetch upstream`
2. Fast-forward `main` to `upstream/main`:
   `git checkout main && git merge --ff-only upstream/main`
   (this also puts the latest upstream main on the mounted volume)
3. Tag the current fork head as backup:
   `git tag backup/self-compact-pre-rebase-<date> self-compact`
4. Rebase: `git rebase --onto upstream/main <fork-point> self-compact`
5. Resolve conflicts (pattern below), `git add`, `git rebase --continue`.
6. Verify:
   - `npm run typecheck` — must pass.
   - Run the 4 known by-design failing test files — expect exactly those failures:
     `test/unit/agent-frontmatter.test.ts`, `agent-management.test.ts`,
     `agent-overrides.test.ts`, `default-extensions.test.ts`.
   - Content-diff the patch series (below) to confirm fork commits survived intact.
7. Update `SELF-COMPACT-FORK.md` with a rebase log entry (upstream version, conflict
   stops, resolutions, follow-up commits) and commit it on `self-compact`.
8. Pushes are done by the user (no GitHub credentials in the container):
   `origin main` and `origin self-compact` (force-with-lease, since the rebase
   rewrites history).

## Conflict resolution pattern

Conflicts happen because the fork and upstream both add independent code at the
same spot (event handlers, prompt-resolution paths, test files). The standard
resolution is **keep both sides**:

- Upstream block first (it is the direct continuation of the surrounding code),
  fork block after.
- When each side's block is an `if (...) {` whose closing `}` is the shared line
  after the conflict marker, you must add an explicit `}` to close the first block
  before the second opens — otherwise the second block nests inside the first.
- State variable conflicts: keep both sets of variables.
- Test file conflicts: keep both test additions; watch for the same shared-closing-
  brace issue (add the missing `});` for the first side's last test).
- After resolving, grep for leftover `<<<<<<<`, `=======`, `>>>>>>>` markers.

Test helpers go stale across upstream API changes: if a helper-built launch object
is missing a key the current code reads (e.g. `capture` on `InProcessChildLaunch`),
fix the helper — do not revert the fork logic.

## Known test failures (do not chase)

- The 4 by-design failures above (fork modifies bundled `agents/*.md` files and
  `subagentOnlyExtensions`). Never "fix" them by reverting agent changes.
- `test/unit/run-child-session.test.ts` does not run green in this container
  (verified identical pre- and post-rebase, 2026-10-27): the upstream test
  `settles a timed-out run whose session creation never returns` hangs and
  cancels the file (settles only via an unref'd 3s abort-backstop timer; the
  isolated test process has nothing keeping the event loop alive) — fails on
  pure upstream too. Two fork tests fail the same way in this environment.
  The fork test `re-routes the resumed task to a follow-up` passes in isolation.
- `test/unit/await-async-run.test.ts` → `rejects with the abort reason while
  waiting` is flaky under full-suite CPU load; passes in isolated runs.

## Content-diff verification

Compare the per-commit patch series before/after the rebase (not a single
`git diff fork-point..HEAD`, which would include all upstream changes):

```sh
mkseries() { for sha in $(git rev-list --reverse $1..$2); do
  git show --format="=== %h %s" $sha; done | grep -v '^index ' | grep -v '^@@' > "$3"; }
mkseries <old-fork-point> <old-head> /tmp/old-series.txt
mkseries <new-base> <new-head> /tmp/new-series.txt
diff /tmp/old-series.txt /tmp/new-series.txt
```

Expected differences: SHAs, and the upstream blocks kept during conflict
resolution. Anything else means a fork change was lost.

## Isolate fork vs upstream failures

When a test fails after a rebase, determine whose problem it is before touching
fork code:

1. `git worktree add /tmp/pi-subagents-upstream upstream/main`
2. `ln -s <fork>/node_modules /tmp/pi-subagents-upstream/node_modules`
   (verify `package.json` is identical first)
3. Run the failing test there. Same failure = upstream issue; different = fork
   interaction. Do the same with a worktree at the pre-rebase backup tag.
4. Remove worktrees when done: `git worktree remove <path> --force`

## Pitfalls

- Python `subprocess.run` hangs non-deterministically in this container (zombie
  python3). Use pure shell/awk for patch hunk extraction, never python scripts
  that spawn processes.
- Prefix every git/npm command with `timeout N` — git and npm can hang on stale
  state, and hangs look like a dead machine.
- Re-verify git state (`git status`, `git log`) after any interruption before
  continuing; do not assume the previous command completed.
- The 4 known failures and the environment-specific failures are documented in
  `SELF-COMPACT-FORK.md` — if a rebased tree shows new failures beyond those,
  stop and investigate before continuing the rebase.

## Verification

- `npm run typecheck` passes.
- The 4 known by-design failures are the only failures in their files.
- The patch-series diff shows only SHAs + kept upstream blocks.
- `SELF-COMPACT-FORK.md` has a rebase log entry.
- Both repos are clean and push-ready (user pushes).
