# pi-portable

Containerized development environment for [Pi](https://pi.dev) — a full developer workstation running Pi inside Docker.

**Base image**: `mcr.microsoft.com/dotnet/sdk:10.0-noble` (Ubuntu 24.04 + .NET 10 SDK)

## Quick Start

### Build with the latest official main branch

```bash
docker build -t pi-sandbox .
```

### Build from a specific fork and commit

Pin to a commit hash for reproducible, auditable builds:

```bash
docker build \
  --build-arg FORK_URL=https://github.com/scotb/pi \
  --build-arg FORK_HASH=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2 \
  -t pi-sandbox .
```

| Build arg | Default | Description |
|---|---|---|
| `FORK_URL` | `https://github.com/earendil-works/pi` | Git URL for the Pi monorepo |
| `FORK_HASH` | _(empty)_ | Full 40-char commit hash. Omit to use the branch's current HEAD. |
| `GIT_USER_NAME` | _(empty)_ | Local-only git identity (author name) for commits made inside the container |
| `GIT_USER_EMAIL` | _(empty)_ | Local-only git identity (author email) for commits made inside the container |

> **Recommended workflow:** Build once per week, tag the image with the date, and pin to the commit hash. Roll back by running a previous tag.

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
# 1. Fetch latest commits
git -C /data/apps/pi clone fetch origin main

# 2. Get the current commit hash
COMMIT=$(git ls-remote origin main | cut -f1)
echo "Building against: $COMMIT"

# 3. Build and tag
docker build \
  --build-arg FORK_URL=https://github.com/scotb/pi \
  --build-arg FORK_HASH="$COMMIT" \
  --build-arg GIT_USER_NAME="Your Name" \
  --build-arg GIT_USER_EMAIL="you@example.com" \
  -t pi-sandbox:latest \
  -t pi-sandbox:$(date +%F) \
  .

# 4. If something breaks, roll back to last week's image
docker run -it --rm pi-sandbox:$(date -d '7 days ago' +%F)
```

## Image Tagging

Docker image tags are how you version, version-control, and roll back your Pi sandbox. Every `docker build` command accepts one or more `-t <name>` flags to assign tags.

### Single tag

The simplest form — one name, one version:

```bash
docker build -t pi-sandbox:2025-07-14 .
```

### Multiple tags in one build

Assign **multiple tags** to the same build with multiple `-t` flags. The first tag in the sequence is the **default** — it's the name used when you omit a tag later:

```bash
docker build \
  --build-arg FORK_HASH="$(git ls-remote origin main | cut -f1)" \
  -t pi-sandbox:latest \
  -t pi-sandbox:2025-07-14 \
  -t pi-sandbox:$(git ls-remote origin main | cut -f1 | cut -c1-7) \
  .
```

This creates **three** tags pointing to the exact same image:

| Tag | Meaning |
|---|---|
| `pi-sandbox:latest` | Convenience alias — always points to the most recent build. |
| `pi-sandbox:2025-07-14` | Date-based tag — easy to reason about, easy to roll back. |
| `pi-sandbox:a1b2c3d` | Short commit hash — tells you **exactly** which commit was built. |

### Tag naming strategies

| Strategy | Example tag | Best for |
|---|---|---|
| **Date** | `pi-sandbox:2025-07-14` | Human-readable versioning; roll back by going back a number of days. |
| **Short commit hash** | `pi-sandbox:a1b2c3d` | Auditable — tells you exactly which commit was baked in. |
| **Full commit hash** | `pi-sandbox:a1b2c3d4e5f6...` | Immutable — guaranteed to be the exact commit (40 chars). |
| **Fork alias** | `pi-sandbox:fork` | You maintain a personal fork; this tag always points to your fork's tip. |
| **Version** | `pi-sandbox:v0.84.1` | If your fork produces releases with semantic versions. |

### Common operations

```bash
# List all tagged images
docker images pi-sandbox

# Inspect a specific tag (shows commit hash, build date, etc.)
docker inspect pi-sandbox:2025-07-14 --format='{{json .RepoTags}}'

# Run a specific tagged version
docker run -it --rm pi-sandbox:2025-07-14

# Run the latest build (omit the tag — Docker uses the default)
docker run -it --rm pi-sandbox

# Retain only the 5 most recent date-tagged builds
docker images pi-sandbox --format '{{.Tag}}' | grep -v 'latest' | tail -n +6 | while read tag; do
  docker rmi "pi-sandbox:$tag"
done
```

### Recommended weekly tagging pattern

Combine **all three** tag strategies in a single build command:

```bash
# 1. Fetch latest
git fetch origin main

# 2. Get the commit info
COMMIT=$(git ls-remote origin main | cut -f1)
SHORT=$(git ls-remote origin main | cut -f1 | cut -c1-7)
DATE=$(date +%F)

# 3. Build with all three tags
docker build \
  --build-arg FORK_URL=https://github.com/earendil-works/pi \
  --build-arg FORK_HASH="$COMMIT" \
  -t pi-sandbox:latest \
  -t pi-sandbox:"$DATE" \
  -t pi-sandbox:"$SHORT" \
  .

echo "Built: $SHORT ($DATE)"
```

Result — one image, three ways to reference it:
```
$ docker images pi-sandbox
REPOSITORY      TAG         IMAGE ID       SIZE
pi-sandbox      latest      a1b2c3d4e5f6   2.4 GB
pi-sandbox      2025-07-14    a1b2c3d4e5f6   2.4 GB
pi-sandbox      a1b2c3d     a1b2c3d4e5f6   2.4 GB
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

### pi-personas (bundled)

Switch between lead, coder, reviewer, and architect personas mid-session. Auto-installed at container startup.

See [pi-personas/README.md](./pi-personas/README.md) for full documentation.

## Volume mounts

| Host path | Container path | Purpose |
|---|---|---|
| `.` (cur dir) | `/host/.` (identity) | Project files — one identity per project |
| `~/.pi` | `/home/ubuntu/.pi` | Pi config (sessions, settings, extensions, **core binaries**) |

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

If you maintain your own fork and want to switch between official and fork builds without editing the Dockerfile:

```bash
# Official repo, main branch
docker build -t pi-sandbox .

# Your fork, main branch
docker build --build-arg FORK_URL=https://github.com/scotb/pi -t pi-sandbox:fork .

# Your fork, specific commit
docker build \
  --build-arg FORK_URL=https://github.com/scotb/pi \
  --build-arg FORK_HASH="$(git -C ~/src/pi rev-parse HEAD)" \
  -t pi-sandbox:fork-$(git -C ~/src/pi rev-parse --short HEAD) \
  .
```

## Configuration

llama-swap and the default model/provider are configured in `~/.pi/agent/models.json` on the host. This file is mounted into the container via the `~/.pi` volume mount, so no configuration is baked into the image.

If your llama-swap instance moves or changes port, update it in that file on the host — no rebuild is required.
