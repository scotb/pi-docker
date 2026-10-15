#!/usr/bin/env bash
set -euo pipefail

# The project directory is mounted at the path it occupies on the host, nested
# under /host.  Launching from /data/apps/foo mounts it at /host/data/apps/foo.

# Why not a fixed /workspace?  Pi keys its session history and trust decisions 
# off the container working directory.  Mounting every project at /workspace
# made them all share one identity: a single chat history for every project, 
# and a single blanket trust entry covering projects never opened.

# why the /host prefix rather than mirroring the host path exactly?  It keeps
# every mount inside one subtree, so a project can never shadow the container's
# own files (/usr/lib/node_modules, /home/ubuntu/.pi, /etc).  Dropping the 
# prefix later is a one-line change here plus renaming the session buckets in 
# ~/.pi/agent/sessions and the keys in ~/.pi/agent/trust.json.

# Known limitations, both accepted deliberately:
#    * A project path containing  ':' breaks the -v argument, as docker uses ':'
#      as its field separator.  Fails loudly with an "invalid mode" error.
#    * Symlinks are not resolved.  Two symlinked routes to the same directory
#      count as two projects, with separate history.

project="$(pwd)"

if [[ "$project" == "/" || "$project" == "$HOME" ]]; then
  echo "pi: refusing to launch from '$project'." >&2
  echo "    Everything below it would be mounted into the container, which" >&2
  echo "    defeats the isolation this sandbox exists to provide" >&2
  echo "    cd into a project directory and try again" >&2
  exit 1
fi

# --dev: also mount the extension fork repos from their home on the host
# (/data/apps), so the entrypoint's live-fork override takes effect while
# developing pi-docker. The flag is consumed here and never passed to pi.
dev=0
args=()
for arg in "$@"; do
    case "$arg" in
        --dev) dev=1 ;;
        *) args+=("$arg") ;;
    esac
done

mounts=(
    -v "$HOME/.pi:/home/ubuntu/.pi"
    -v "$project:/host$project"
)
envs=(-e "LLAMA_SERVER_URL=http://host.docker.internal:8007")
if [[ "$dev" == 1 ]]; then
    envs+=(-e PI_DEV=1)
    mounts+=(
        -v "/data/apps/pi-subagents:/host/data/apps/pi-subagents"
        -v "/data/apps/self-compact-pi-agent:/host/data/apps/self-compact-pi-agent"
    )
fi

# Run the container with the given command
docker run -it --rm \
        "${mounts[@]}" \
        "${envs[@]}" \
        -w "/host$project" \
        pi-sandbox:latest ${args[@]+"${args[@]}"}
