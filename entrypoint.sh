#!/usr/bin/env bash
set -euo pipefail

# Install bundled extensions at container startup.
# Extensions dropped into ~/.pi/agent/extensions/ are auto-discovered
# by pi and are never checked for updates (no npm lookup needed).

EXT_SRC="/opt/pi-extensions/pi-personas"
EXT_DST="$HOME/.pi/agent/extensions/pi-personas"

if [ -d "$EXT_SRC" ] && [ ! -d "$EXT_DST" ]; then
    cp -a "$EXT_SRC" "$EXT_DST"
    echo "pi-personas extension installed from image"
fi

# self-compact: always re-sync from the image — the image is the source of truth for the
# extension version, and it keeps no state on disk (session state lives in the session journal).
SC_SRC="/opt/pi-extensions/self-compact"
SC_DST="$HOME/.pi/agent/extensions/self-compact"
if [ -d "$SC_SRC" ]; then
    rm -rf "$SC_DST"
    cp -a "$SC_SRC" "$SC_DST"
    echo "self-compact extension installed from image"
fi

exec node /opt/pi/packages/coding-agent/dist/cli.js "$@"
