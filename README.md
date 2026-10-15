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
./build.sh --tag pi-sandbox:2026-10-15         # date-tag for roll back
```

The Dockerfile **refuses to build** with empty extension hashes, so a plain
`docker build` is no longer a valid path — always go through `build.sh`
(or pass the hashes explicitly).

| Build arg | Default | Description |
|---|---|---|
| `FORK_URL` | `https://github.com/earendil-works/pi` | Git URL for the Pi monorepo |
| `FORK_HASH` | _(empty = default-branch tip)_ | Pin pi to a commit |
| `PI_SUBAGENTS_URL` | `https://github.com/scotb/pi-subagents` | Fork URL |
| `PI_SUBAGENTS_HASH` | **required** | Pin the `self-compact` branch tip (or any commit) |
| `SELF_COMPACT_URL` | `https://github.com/scotb/self-compact-pi-agent` | Fork URL |
| `SELF_COMPACT_HASH` | **required** | Pin the `deploy` branch tip (or any commit) |
| `GIT_USER_NAME` / `GIT_USER_EMAIL` | _(empty)_ | Local-only git identity for in-container commits |

> **Recommended workflow:** build once per week with `./build.sh --tag pi-sandbox:$(date +%F)`. Roll back by running a previous date tag.

### Local git identity (optional)

If you want commits made inside the container attributed to you, pass your
name and email as build args. Only the author identity is written (to
`/home/ubuntu/.gitconfig`) — **no credentials** are stored in the image;
push/pull are done manually on the host.

```bash
docker build \
  --build-arg GIT_USER_NAME="Your Name" \
  --build-arg GIT_USER_EMAIL="you@example.com" \
  -t pi-sandbox .
```

## Weekly Build Workflow

```bash
./build.sh --tag pi-sandbox:$(date +%F)
```

Date tags make roll-back trivial — run an older tag:

```bash
docker run -it --rm pi-sandbox:2026-10-08
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

The containerized version of Pi requires the `lean-ctx` binary to be present on your **host machine**. The container relies on a volume mount to access these core agent tools.

```bash
curl -fsSL https://api.earendil.works/install.sh | bash -s -- --dest ~/.pi/bin
```

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

Add `--dev` to mount the live extension forks from `~/data/apps` — the entrypoint then installs extensions from there instead of the image-baked copies (for iterating on the forks):

```bash
pi --dev
```

### Run commands directly

```bash
pi -p "fix the bug in src/main.ts"
pi /login
pi --list-models
```

### Get a bash shell inside the container

```bash
docker run -it --rm \
  -v "$HOME/.pi:/home/ubuntu/.pi" \
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

## Volume mounts

| Host path | Container path | Purpose |
|---|---|---|
| `.` (cur dir) | `/host/.` (identity) | Project files — one identity per project |
| `~/.pi` | `/home/ubuntu/.pi` | Pi config (sessions, settings, extensions, **core binaries**) |
| `~/data/apps/{pi-subagents,self-compact-pi-agent}` | `/host/data/apps/...` | Live extension forks — **only** with `pi --dev` |

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
  page-shot http://localhost:3000 /tmp/page.png [--full] [--viewport WxH] [--wait ms] [--selector css]
  ```
  Prints a JSON summary: `{ ok, out, url, status, title, consoleErrors, failedRequests }`.
  Screenshots only reach the model when it is vision-capable ("input": ["text", "image"] in `models.json`).

### Pi
- **Pi CLI**: built from source with plain `npm run build` (no Bun) and shipped to `/opt/pi/`; the entrypoint runs it as `node /opt/pi/packages/coding-agent/dist/cli.js`
- **Agent Tools**: `lean-ctx` (provided via host `~/.pi/bin` mount)
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

llama-swap and the default model/provider are configured in `~/.pi/agent/models.json` on the host. This file is mounted into the container via the `~/.pi` volume mount, so no configuration is baked into the image.

If your llama-swap instance moves or changes port, update it in that file on the host — no rebuild is required.
