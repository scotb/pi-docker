# pi-docker

Disposable Docker dev environment for Pi, designed for WSL.

## Setup

Build the image once:

```bash
docker build -t pi-portable .
```

## Usage

Install `pi` somewhere in your PATH (e.g. symlink it from `~/bin`):

```bash
# One-time: make the script available globally
ln -s "$(pwd)/pi.sh" ~/bin/pi
```

### Interactive shell

```bash
cd /path/to/your/project
pi
```

Drops you into a bash prompt with the current directory mounted at `/workspace`.

### Run Pi directly

```bash
pi -p "fix the bug in src/main.ts"
```

Any arguments are passed through to `pi`:

```bash
pi /login
pi --list-models
```

## What's inside

- **Base**: `ubuntu:24.04`
- **Node.js 22** (required for Pi)
- **git**, **curl**
- **Pi** (installed via `curl https://pi.dev/install.sh | sh`)
- **llama-swap** configured as the default LLM provider (`host.docker.internal:8007`)

## Volume mounts

| Host path | Container path | Purpose |
|---|---|---|
| `.` (current dir) | `/workspace` | Project files |
| `~/.pi` | `/home/vscode/.pi` | Pi config (sessions, settings, extensions) |
| `~/.pi-cache` | `/home/vscode/.pi-cache` | Pi cache (shared across all projects) |

## Configuration

Set `LLAMA_SERVER_URL` to point to your llama-swap instance:

```bash
export LLAMA_SERVER_URL=http://host.docker.internal:8007
```

Default is `http://host.docker.internal:8007`, which is the llama-swap service running on the Docker host (your WSL host).
