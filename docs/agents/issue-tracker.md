# Issue tracker

Issues are local markdown files under `.scratch/<feature>/` — deliberately
not in a remote tracker. `.scratch/` is gitignored; it is working state,
not repo content.

## Layout

```
.scratch/<feature>/
  PRD.md              # what and why (one page)
  issues/
    NN-slug.md        # one file per issue, numbered in priority order
  HANDOFF.md          # optional: current state for the next session/agent
```

## Lifecycle

Each issue file carries a triage label in its front matter (see
`triage-labels.md`). An issue is done when its file is deleted or moved —
completed working state does not accumulate in `.scratch/`.

## Rules

- One directory per feature; create it when work starts.
- Keep issue files short and current — they are the source of truth for
  agents picking up the work.
- Clean up `.scratch/` when a feature ships (the repo's git history and
  ADRs are the durable record).
