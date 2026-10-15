# Domain docs

Single-context convention: one `CONTEXT.md` at the repo root plus
`docs/adr/` for architectural decisions. No per-package context files.

## CONTEXT.md

The repo's vocabulary and current architecture in one page: what the
project is, its components, and the terms used across docs and issues.
Update it when the architecture changes meaningfully — not per commit.

## docs/adr/

One file per significant decision: `NNNN-short-slug.md` with Status,
Context, Decision, Consequences. Decisions are append-only — supersede an
ADR by writing a new one that references it, never by editing history.
