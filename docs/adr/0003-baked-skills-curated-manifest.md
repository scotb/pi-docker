# Baked skills with a curated manifest

Pi skills (prompt artifacts: a `SKILL.md` directory) previously lived only
on the state volume (`~/.pi/agent/skills/`) — a lost volume meant lost
skills, and the active set was whatever had been copied there by hand.
The in-house skills (`orchestrate`, `pi-subagents-workflow`) lived only in
the volume's `pi-hermes-memory` drafting area.

We decided: **skills are baked skills** — staged into `/opt/pi-skills/` at
image build time, pinned to an exact version, and installed into
`~/.pi/agent/skills/` by `entrypoint.sh` on every container start. The
entrypoint owns `~/.pi/agent/skills/` (reinstalled from the image on every
start); hand-dropped skills are ephemeral by design. Two sources:

| Source | Pin | Extraction |
|---|---|---|
| mattpocock/skills (upstream) | git SHA, cloned at build | curated by `skills-manifest.txt` (fail-fast) |
| scotb/skills (own repo) | git SHA, cloned at build | whole repo, flattened at install |

The **skill manifest** is a curated, dependency-closed list: one skill path
per line, and a listed path missing at the pinned SHA **fails the build**
rather than warning. Rationale: a silently missing skill is the same
disease ADR-0002 cured (silent drift between builds); the build-time error
hands the operator the exact SHA where the selection stopped matching,
which is the starting point of the recovery workflow (pin `MATT_SKILLS_HASH`
to the prior tip, re-curate the list).

`scotb/skills` doubles as the archive for the in-house skills, which
previously existed only on the volume. New skills are drafted in the
`pi-hermes-memory` drafting area and promoted by copy → commit → rebuild.

`--dev` live-mounts only `scotb/skills` (the repo the operator iterates
on); mattpocock/skills is upstream and gets no live mount — the curation
lever (the manifest) already lives in the pi-docker repo.

## Considered options

- **Bake the whole mattpocock/skills repo** — rejected: it would advertise
  deprecated, in-progress, and tool-specific skills (e.g. Claude Code) the
  environment doesn't use, and every skill description costs system-prompt
  weight in every session.
- **Vendor a snapshot into pi-docker** — rejected: the same manual-sync
  maintenance ADR-0002 rejected for third-party code.
- **Warn instead of failing on a missing manifest entry** — rejected: build
  output scrolls by and warnings are missed; a broken selection set would
  ship as `pi-sandbox:latest` and surface mid-session, with no record of
  which upstream commit broke it.
- **Build from a fork of mattpocock/skills** — rejected: the fork's only job
  was preservation, which the image now does; a fork as build source would
  be a second source of truth drifting from upstream.
- **Auto-detect skill dependencies** — rejected: overkill for a hand-curated
  list; the curator owns the closure.

## Consequences

- A rename/delete of a curated skill upstream breaks `./build.sh` at the
  head — recover by pinning `MATT_SKILLS_HASH` to the prior tip.
- The first start on a new image wipes the volume's old whole-repo
  `mattpocock-skills` checkout (replaced by the curated set) and the
  in-house skills must be deleted from the `pi-hermes-memory` drafting
  area once, or they get advertised twice.
- A skill name collision between the two sources fails container start.
- Upgrades are deliberate events: bump a pin (SHA), re-curate if needed,
  rebuild, verify the provenance echo lists the expected skills.
