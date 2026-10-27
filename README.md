# pi-portable

Containerized development environment for [Pi](https://pi.dev) — a full developer workstation running Pi inside Docker.

**Base image**: `mcr.microsoft.com/dotnet/sdk:10.0-noble` (Ubuntu 24.04 + .NET 10 SDK)

## Quick Start

### Build (pinned, reproducible)

`build.sh` resolves every baked repo to an exact SHA before building: heads
of the tracked branches by default (pi: `main`, pi-subagents: `self-compact`,
self-compact: `deploy`), overridable per repo. The resolved inputs are
echoed, so the exact provenance is on the record.

```bash
./build.sh                                     # heads of tracked branches
PI_SUBAGENTS_HASH=a85db042... ./build.sh       # pin one repo to a commit
PI_URL=https://github.com/you/pi ./build.sh    # point pi at a fork
./build.sh --tag pi-sandbox:1.3.0 --tag pi-sandbox:2026-10-15
#   ^ --tag is repeatable; pi-sandbox:latest is always tagged too
./build.sh --no-cache
#   ^ everything besides --tag is passed to docker build verbatim
#     (--no-cache, --build-arg, --progress=plain, --cache-from, …)
```

The Dockerfile **refuses to build** with empty extension hashes, so a plain
`docker build` is no longer a valid path — always go through `build.sh`
(or pass the hashes explicitly).

| Build arg | Default | Description |
|---|---|---|
| `FORK_URL` | `https://github.com/earendil-works/pi` | Git URL for the Pi monorepo |
| `FORK_HASH` | `71023aec…` (pi 1.3.0) | Pin pi to a commit (default: 1.3.0 release; override with `PI_HASH`) |
| `PI_SUBAGENTS_URL` | `https://github.com/scotb/pi-subagents` | Fork URL |
| `PI_SUBAGENTS_HASH` | **required** | Pin the `self-compact` branch tip (or any commit) |
| `SELF_COMPACT_URL` | `https://github.com/scotb/self-compact-pi-agent` | Fork URL |
| `SELF_COMPACT_HASH` | **required** | Pin the `deploy` branch tip (or any commit) |
| `MATT_SKILLS_URL` | `https://github.com/mattpocock/skills` | Upstream skills repo; curated by `skills-manifest.txt` |
| `MATT_SKILLS_HASH` | **required** | Pin the `main` branch tip (or any commit); build fails if a manifest entry is missing at the SHA |
| `LEAN_CTX_BIN_VERSION` / `LEAN_CTX_BIN_SHA256` | `v3.11.4` + official sha256 | Pinned lean-ctx native binary (GitHub release); build fails on sha mismatch |
| `TDD_LEDGER_SHA` | _(auto: this repo's HEAD via build.sh)_ | Provenance pin for the vendored tdd-ledger extension |
| `GIT_USER_NAME` / `GIT_USER_EMAIL` | _(empty)_ | Local-only git identity for in-container commits |

> The three upstream npm extensions (`pi-web-access`, `pi-hermes-memory`,
> `pi-lean-ctx`) are pinned by the committed `extensions/extension-lock` lockfile,
> not by build args — bump the version in `extensions/extension-lock/package.json`,
> regenerate the lockfile, rebuild (ADR-0002).

> **Recommended workflow:** build once per week with `./build.sh --tag pi-sandbox:$(date +%F)`, adding a version tag as needed (`--tag` is repeatable, e.g. `--tag pi-sandbox:1.3.0`); `pi-sandbox:latest` is always tagged. Roll back by running a previous date tag (`pi --tag <date>`).

### Local git identity (optional)

If you want commits made inside the container attributed to you, pass your
name and email as build args. Only the author identity is written (to
`/home/ubuntu/.gitconfig`) — **no credentials** are stored in the image;
push/pull are done manually on the host.

```bash
GIT_USER_NAME="Your Name" GIT_USER_EMAIL="you@example.com" ./build.sh
```

## Weekly Build Workflow

```bash
./build.sh --tag pi-sandbox:$(date +%F)
```

Date tags make roll-back trivial — run an older tag:

```bash
pi --tag 2026-10-08
```

Common operations:

```bash
# List all tagged images
docker images pi-sandbox

# Retain only the 5 most recent date-tagged builds
docker images pi-sandbox --format '{{.Tag}}' | grep -v 'latest' | tail -n +6 | while read tag; do
  docker rmi "pi-sandbox:$tag"
done
```

The Pi monorepo takes dependency integrity seriously. This Dockerfile leverages several mechanisms:

| Mechanism | What it protects against |
|---|---|
| `npm ci --ignore-scripts` | Installs strictly from `package-lock.json` with SHA-512 integrity checks. Lifecycle scripts (`preinstall`, `postinstall`, etc.) are skipped. |
| `min-release-age=2` (in `.npmrc`) | Blocks same-day dependency releases, giving time to review changes. |
| `npm audit --audit-level=critical` | Logs critical CVEs in build output; non-fatal to avoid blocking on low-severity findings. |
| Commit hash pinning | Guarantees you build against the exact commit you audited, not a moving branch target. |
| Shallow clone (`--depth 1`) | No unnecessary git history downloaded or cached. |

## Usage

### Prerequisites

None — the `lean-ctx` binary is baked into the image at a pinned version
(`/opt/pi-extensions/lean-ctx/bin/lean-ctx`), and all bundled extensions are
installed by the entrypoint at container start. Agent state lives in the
named volume `pi-state` (see Volume mounts below).

### Install the `pi` wrapper script

```bash
ln -s "$(pwd)/pi.sh" ~/bin/pi
```

### Interactive session

```bash
cd /path/to/your/project
pi
```

Starts an interactive Pi session with the current directory mounted at `/host/<path>` inside the container. Each project gets its own identity — separate session history, trust decisions, and settings.

Add `--dev` to mount the live extension forks — the entrypoint then installs extensions from them instead of the image-baked copies (for iterating on the forks). The forks must exist on the host at `/data/apps` (`pi-subagents`, `self-compact-pi-agent`); they are mounted at `/host/data/apps/...`:

```bash
pi --dev
```

Run against a specific image tag instead of `pi-sandbox:latest` — useful for
verifying a dated build before it becomes `latest`:

```bash
pi --tag 2026-10-15
```

### Windows (PowerShell)

`pi.ps1` is the Windows-side twin of `pi.sh`. Same daemon, so the `pi-state`
volume and `pi-sandbox` image are shared as-is. A project at `C:\foo` mounts
at `/host/C/foo` — its own identity, its own history, same `/host/<path>`
scheme as pi.sh.

```powershell
# one-time: allow running local scripts
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

# copy pi.ps1 to a Windows drive and add that folder to PATH, e.g.
#   C:\Users\<you>\bin\pi.ps1
cd C:\path\to\your\project
pi.ps1
pi.ps1 --tag 2026-10-15
pi.ps1 -p "fix the bug in src/main.ts"
```

Not supported from Windows: projects on the WSL side (`/data` is ext4 inside
the WSL2 VM — not bind-mountable by the Windows docker CLI) and `--dev` (the
live forks live on that same WSL side). Both are refused loudly.

### Run commands directly

```bash
pi -p "fix the bug in src/main.ts"
pi /login
pi --list-models
```

### Get a bash shell inside the container

```bash
docker run -it --rm \
  -v pi-state:/home/ubuntu/.pi \
  -v "$(pwd):/host/$(pwd)" \
  -w "/host/$(pwd)" \
  pi-sandbox bash
```

## Extensions

### self-compact (bundled)

Automatic context management for long-running sessions: context bar in the footer
(notice 50% / warning 70% / forced 85% of the active model's window), a mandatory
`note_to_self` handoff, and a custom compaction summary that preserves goal, decisions,
progress, and next action. Re-synced from the image into `~/.pi/agent/extensions/` at
container startup.

Source: the `self-compact-pi-agent` fork (`deploy` branch, pinned at build —
see `build.sh`). Details: `docs/adr/0001-self-compact-context-management.md`.

### pi-subagents (bundled)

Sub-agent orchestration (the `subagent` tool), built from the `pi-subagents`
fork's `self-compact` branch: a patched runner with the self-compact drain-hold
gate plus child context-management tools, so async children can compact
themselves mid-mission. Same install pattern as self-compact.

### Baked upstream extensions (bundled)

Extensions installed from the image instead of npm — deterministic, no runtime
npm lookup, no network needed. Pinned exactly (ADR-0002), re-installed by the
entrypoint at every container start, with a provenance line echoed at startup:

| Extension | Pin | Notes |
|---|---|---|
| `pi-web-access` | lockfile (`extensions/extension-lock`) | Web search/fetch tools; provider keys from environment; cache in `~/.pi/agent/web-search-cache` |
| `pi-hermes-memory` | lockfile | Cross-session memory; state in `~/.pi/agent/pi-hermes-memory/` + `~/.pi/agent/projects-memory/`; config in `~/.pi/agent/hermes-memory-config.json` |
| `pi-lean-ctx` | lockfile + pinned binary `v3.11.4` (sha256-verified) | `ctx_*` tools + MCP bridge; **save-restore install** — it writes state (`config.json`, `mcp-schema-cache.json`) inside its own install dir, so the entrypoint moves them aside, replaces the dir, restores them; seeds the default `config.json` (baked binary) on a fresh volume; data dir `~/.pi/lean-ctx` |
| `tdd-ledger` | local file (`extensions/tdd-ledger/`) | No upstream — this repo is the source of truth; ledger in `~/.pi/tdd-ledger` |

The npm dependency tree is staged whole into the image
(`/opt/pi-extensions/npm/node_modules`) and installed alongside each package
directory under `~/.pi/agent/extensions/` (Node resolves hoisted deps by walking
up; pi's discovery skips `node_modules`).

### Baked skills (bundled)

Skills are prompt artifacts (a `SKILL.md` directory), staged into the image
and reinstalled into `~/.pi/agent/skills/` by the entrypoint at every
container start, with a provenance line echoed (ADR-0003):

| Source | Stage | Notes |
|---|---|---|
| `skills/` (this repo) | `/opt/pi-skills/local` | First-party skills — no build arg; bump the version in the SKILL.md front matter, commit, rebuild |
| `mattpocock/skills` | `/opt/pi-skills/mattpocock` | Third-party, git-SHA-pinned (`MATT_SKILLS_HASH`); curated per `skills-manifest.txt` |

## Volume mounts

| Host path | Container path | Purpose |
|---|---|---|
| `.` (cur dir) | `/host/.` (identity) | Project files — one identity per project |
| `pi-state` (named volume; `PI_VOLUME` to override) | `/home/ubuntu/.pi` | Pi state (sessions, settings, extensions, config) |
| `/data/apps/{pi-subagents,self-compact-pi-agent}` | `/host/data/apps/...` | Live extension forks — **only** with `pi --dev` |

## What's inside

### Base environment
- **Base image**: `mcr.microsoft.com/dotnet/sdk:10.0-noble`
- **Node.js 22** (via nodesource)
- **.NET 10 SDK** (for .NET Framework and Core development)
- **Git** (shallow clones for building; also available in the final image)
- **neovim** (terminal editor)
- **ripgrep** (used by Pi's built-in search)

### Utilities
| Tool | Purpose |
|---|---|
| `jq` | JSON processing |
| `unzip` | Archive extraction |
| `wget` | URL fetching |
| `strace` | System call tracing |
| `sysstat` | CPU/memory monitoring (`mpstat`, `iostat`) |
| `procps` | `ps`, `top`, `free`, `vmstat` |
| `openssh-client` | SSH access |

### Browser
- **Chromium** (Playwright-managed, at `/opt/playwright-browsers`) — headless browser for visual page inspection. Ubuntu 24.04's apt `chromium-browser` is a snap stub that won't run in Docker, so the image uses Playwright's standalone Chromium build instead.
- **playwright** 1.63 (npm, global; resolvable via `require('playwright')` through `NODE_PATH`) for scripted automation.
- **page-shot** (`/usr/local/bin/page-shot`) — renders a URL to a PNG for the agent to view with the built-in `read` tool:
  ```sh
  page-shot http://localhost:3000 /tmp/page.png [--full] [--viewport WxH] [--wait ms] [--selector css] [--alpha]
  ```
  Prints a JSON summary: `{ ok, out, url, status, title, consoleErrors, failedRequests }`.
  Default PNGs are RGB without alpha (colortype 2) — Chromium's capture path renders to an opaque surface, so transparent page areas are baked in. Add `--alpha` to capture with a real alpha channel (RGBA, colortype 6): the page's unpainted regions come out fully transparent, which is what icon/asset capture (e.g. ICO source) needs.
  Screenshots only reach the model when it is vision-capable ("input": ["text", "image"] in `models.json`).

### Pi
- **Pi CLI**: built from source with plain `npm run build` (no Bun) and shipped to `/opt/pi/`; the entrypoint runs it as `node /opt/pi/packages/coding-agent/dist/cli.js`
- **Agent Tools**: `lean-ctx` (baked at a pinned version)
- **Baked docs**: this repo's `docs/` at `/opt/docs/` (ADRs, agent conventions, integration spec) — pinned to the repo commit, so the environment's rationale is readable from any session; the `environment` skill is the map onto it
- **llama-swap**: NOT configured in the image — provided by the host-mounted `~/.pi/agent/models.json`

## Building from a fork

Per-repo URL/hash overrides make forks a one-liner — no Dockerfile edits:

```bash
# Your pi fork, main branch
PI_URL=https://github.com/scotb/pi ./build.sh

# Your pi fork, specific commit
PI_URL=https://github.com/scotb/pi PI_HASH=$(git -C ~/src/pi rev-parse HEAD) ./build.sh
```

## Configuration

llama-swap and the default model/provider are configured in
`~/.pi/agent/models.json`, in the `pi-state` volume. No configuration is
baked into the image.

If your llama-swap instance moves or changes port, update the file in the
volume (e.g. via a one-off `docker run -v pi-state:/tmp/vol`) — no rebuild is
required.
