## This repo (read first — skip the discovery)

`pi-docker` builds the `pi-sandbox` image: `Dockerfile` + `build.sh` (resolves pins) + `entrypoint.sh` (installs from the staging area on every start). It bakes the Pi CLI, first-party extensions/skills, and pinned deps. The image owns code; the state volume (`~/.pi`) owns state.

**Read, in order, before exploring:** this `AGENTS.md` → `CONTEXT.md` (domain glossary) → the `environment` skill (the map: what lives where, pins, ops). Do **not** `ls -R` / `find` here — `extensions/extension-lock/node_modules` is tens of MB and will flood your context. Targeted `ctx_grep`/`ctx_read` on the three build files is enough.

**Dev mode (`pi --dev`):** the live forks are bind-mounted at `/host/data/apps/{pi-subagents,self-compact-pi-agent}` and the entrypoint installs from them instead of the baked copies. Edit the live fork in place to iterate.

**What the agent CANNOT do in this repo: no docker, no GitHub creds.** Never run `docker build` or `git push`. The handoff:
1. You commit changes in the live fork, and in this repo for vendored first-party code (`extensions/tdd-ledger/`, `skills/`).
2. The user quits pi and restarts with `pi --dev` so the new live fork is picked up, then tests.
3. The user pushes the fork to GitHub and runs `./build.sh` to bake it. `build.sh` resolves the fork's `self-compact` branch head via `git ls-remote`; pin a specific commit with `PI_SUBAGENTS_HASH` in `.env`.

Note: vendored code (tdd-ledger, skills) is baked, not live-mounted — it takes effect only after a `./build.sh` rebuild, even in dev mode. Live forks (pi-subagents, self-compact) take effect on the next `pi --dev` start.

## Agent skills

### Issue tracker

Issues live as local markdown files under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Five default labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` at repo root + `docs/adr/` for architectural decisions. See `docs/agents/domain.md`.

### Skill versioning

First-party skills use semver in `SKILL.md` front matter; drafting-area drafts keep their version until promotion. See `docs/agents/skill-versioning.md`.
