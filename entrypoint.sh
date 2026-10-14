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

# pi-subagents: always re-sync from the fork — the fork is the source of truth for the
# patched runner (self-compact drain-hold gate + child context-management tools).
PS_SRC="/host/data/apps/pi-docker/pi-subagents"
if [ ! -d "$PS_SRC" ]; then
    PS_SRC="/opt/pi-extensions/pi-subagents"
fi
PS_DST="$HOME/.pi/agent/npm/node_modules/pi-subagents"
if [ -d "$PS_SRC" ]; then
    rm -rf "$PS_DST"
    cp -a "$PS_SRC" "$PS_DST"
    rm -rf "$PS_DST/.git"
    echo "pi-subagents synced from fork"
fi

exec node /opt/pi/packages/coding-agent/dist/cli.js "$@"
