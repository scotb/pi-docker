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

exec pi "$@"
