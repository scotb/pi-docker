#!/usr/bin/env bash
set -euo pipefail

# Install bundled extensions at container startup.
# Extensions dropped into ~/.pi/agent/extensions/ are auto-discovered
# by pi and are never checked for updates (no npm lookup needed).

# self-compact: prefer the live fork when the /host mount is present (dev iteration);
# fall back to the image-baked copy (production). It keeps no state on disk
# (session state lives in the session journal).
SC_SRC="/host/data/apps/pi-docker/self-compact-pi-agent/apps/self-compact"
if [ ! -d "$SC_SRC" ]; then
    SC_SRC="/opt/pi-extensions/self-compact"
fi
SC_DST="$HOME/.pi/agent/extensions/self-compact"
if [ -d "$SC_SRC" ]; then
    rm -rf "$SC_DST"
    cp -a "$SC_SRC" "$SC_DST"
    echo "self-compact extension installed from $SC_SRC"
fi

# pi-subagents: installed exactly like self-compact — from the live /host fork when
# mounted (dev iteration), otherwise the image-baked copy. The /host fork is
# source-only, so runtime deps come from the baked node_modules.
PS_SRC="/host/data/apps/pi-docker/pi-subagents"
PS_BAKED="/opt/pi-extensions/pi-subagents"
if [ ! -d "$PS_SRC" ]; then
    PS_SRC="$PS_BAKED"
fi
PS_DST="$HOME/.pi/agent/extensions/pi-subagents"
if [ -d "$PS_SRC" ]; then
    rm -rf "$PS_DST"
    cp -a "$PS_SRC" "$PS_DST"
    if [ ! -d "$PS_DST/node_modules" ] && [ -d "$PS_BAKED/node_modules" ]; then
        cp -a "$PS_BAKED/node_modules" "$PS_DST/node_modules"
    fi
    rm -rf "$PS_DST/.git" "$PS_DST/node_modules/pi-subagents"
    echo "pi-subagents installed from $PS_SRC"
fi

exec node /opt/pi/packages/coding-agent/dist/cli.js "$@"
