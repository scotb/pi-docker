# Baked extensions with volume-held state

Pi extensions were previously installed from npm at runtime (`npm:` entries in
`settings.json`, code in `~/.pi/agent/npm/`). Pi's package manager then checked
npm for updates at runtime, so the environment drifted between image builds —
breaking the container's determinism guarantee. Some extension code also lived
only on the host mount and could be lost.

We decided: **all extension code is a baked extension** — staged into
`/opt/pi-extensions/` at image build time, pinned to an exact version, and
installed by `entrypoint.sh` on every container start. **All extension state
lives under `~/.pi`, a named Docker volume (`pi-state`)**, and survives
rebuilds. The image owns code; the volume owns config and state. The
entrypoint is read-only with respect to user config; state transitions are
one-time manual carryovers. The volume (rather than a host bind mount) makes
recovery a docker operation: run against a new volume name to start fresh,
run against the old name to roll back — volumes coexist and nothing is
deleted.

Pinning uses the tightest mechanism that matches the artifact:

| Source | Pin |
|---|---|
| Forks we patch (pi-subagents, self-compact) | git SHA, cloned at build |
| Upstream npm packages (web-access, hermes-memory, lean-ctx) | committed `package-lock.json`, `npm ci` at build |
| Local code with no upstream (tdd-ledger) | file vendored in this repo |

## Considered options

- **Git-clone every extension at a pinned SHA** — rejected for upstream npm
  packages: a git SHA is not the same artifact as the published tarball
  (e.g. pi-web-access publishes a built `dist/`), so it would force build
  steps in the image and risks version skew.
- **Vendor all third-party source into this repo** — rejected: three
  third-party codebases would need manual syncing on every update; a
  lockfile pin gives the same determinism without the maintenance.
- **Keep runtime npm installs** — rejected: that is the non-determinism being
  eliminated.

## Consequences

- An upgrade is a deliberate event: bump the pin (SHA / lockfile / vendored
  file), rebuild, verify against the acceptance bar.
- `entrypoint.sh` uses a save-restore install for pi-lean-ctx only, because
  that extension writes state (`config.json`, `mcp-schema-cache.json`) inside
  its own install directory.
- The entrypoint remains strictly read-only on user config (the only state
  it writes is pi-lean-ctx's own default `config.json` inside the
  image-owned install dir, seeded when a fresh volume has none). The one-time
  state transition is a **carryover**: the pre-volume host `~/.pi` directory
  is copied once into the fresh `pi-state` volume, excluding the npm-era
  cruft (`agent/npm`, `agent/mcp.json*`, `agent/extensions`, `agent/bin`) and
  stripping the `npm:` entries *inside the volume* (a one-and-done host
  script, `~/.pi/carryover-to-volume.sh`, kept out of this repo) — so the
  host directory stays intact as the fallback state for the old image.
- Recovery from then on is a volume swap: `PI_VOLUME=<name> pi` runs against
  any named volume; old volumes are never deleted.
- The startup provenance echo makes the running code auditable for every
  baked extension.
