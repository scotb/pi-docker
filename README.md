# pi-docker
Disposable Docker dev env for Pi, designed for WSL.

## Setup
Build the image once:
```bash
docker build -t pi-portable .
```

### ⚠️ Important: Post-Build Requirement
This containerized version of Pi requires the `lean-ctx` binary to be present on your **host machine**. The container relies on a volume mount to access these core agent tools.

If you haven't already, install the `lean-ctx` binary to your host's `~/.pi/bin` directory:
```bash
# Replace this with your preferred installation method
curl -fsSL https://api.earendil.works/install.sh | bash -s -- --dest ~/.pi/bin
```

## Usage
Install `pi.sh` somewhere in your PATH (e.g. symlink it from `~/bin`):
```bash
# One-time: make the script available globally
ln -s "$(pwd)/pi.sh" ~/bin/pi
```

### Interactive shell
```bash
cd /path/to/your/project
pi
```
Starts an interactive pi session with the current directory mounted at its original path (prefixed with `/host`) inside the container. Each project gets its own identity: separate session history, trust decisions, and settings.

To get a bash shell inside the container instead, run:
```bash
docker run -it --rm -v "$HOME/.pi:/home/ubuntu/.pi" -v "$(pwd):/host/$(pwd)" -w "/host/$(pwd)" --entrypoint bash pi-portable
```

### Run Pi directly
```bash
pi -p "fix the bug in src/main.ts"
```
Any arguments are passed through to `pi`:
```bash
pi /login
pi --list-models
```

## Extensions

### pi-personas (bundled)
Switch between lead, coder, reviewer, and architect personas mid-session. Each persona defines a distinct identity with tailored tools, models, and instructions — enabling a natural development pipeline (investigate → implement → review → finalize).

This extension is bundled with the image and auto-installed at container startup. No separate install step is needed.

See [pi-personas/README.md](./pi-personas/README.md) for full documentation.

## What's inside
- **Base**: `mcr.microsoft.com/dotnet/sdk:10.0-noble` (Ubuntu 24.04 based)
- **Node.js 22** (installed via nodesource)
- **git**, **curl**, **ripgrep**
- **Pi CLI**: installed via `npm install -g @earendil-works/pi-coding-agent`
- **Agent Tools**: `lean-ctx` (must be provided via host `~/.pi/bin` mount)
- **llama-swap** is NOT configured in the image — it's provided by the host-mounted `~/.pi/agent/models.json`
- Runs as the `ubuntu` user (`UID 1000`)

## Volume mounts
| Host path | Container path | Purpose |
| `.` (cur dir) | `/host/.` (identity) | Project files — one identity per project |
| `~/.pi` | `/home/ubuntu/.pi` | Pi config (sessions, settings, extensions, and **core binaries**) |

## cfg
llama-swap and the default model/provider are configured in `~/.pi/agent/models.json` on the host (see [volume mounts](#volume-mounts)). This file is mounted into the container, so no cfg is needed inside the image.
If your llama-swap instance moves or changes port, update it in that file — it's read at runtime, so no rebuild is required.
