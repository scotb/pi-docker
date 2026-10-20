# Skill versioning

First-party skills — drafted in the drafting area
(`~/.pi/agent/pi-hermes-memory/skills/`) and promoted into this repo's
`skills/` — carry a semver `version:` in their `SKILL.md` front matter.
Upstream skills (e.g. mattpocock) are not ours to version; they are pinned
by git SHA + manifest.

## Bump policy

- **patch** — wording, cleanup, reworded pitfalls; behavior unchanged.
- **minor** — a new step, requirement, or template line added.
- **major** — a breaking change to the skill's procedure or contract.

Current baseline is `1.0.x`. Update the `updated:` front-matter date
whenever the version changes.

## Drafts vs promotion

A draft in the drafting area is in-flight, not released: iterate it without
bumping. The version is finalized at promotion (copy into `skills/` →
commit → rebuild); bump there if the draft changed since its last stamp.
After a successful promotion, delete the draft from the drafting area — a
surviving draft gets advertised twice.
