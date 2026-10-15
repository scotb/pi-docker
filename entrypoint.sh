#!/usr/bin/env bash
set -euo pipefail

# Install bundled extensions at container startup.
# Extensions dropped into ~/.pi/agent/extensions/ are auto-discovered
# by pi and are never checked for updates (no npm lookup needed).
#
# Source selection is explicit, never inferred from what happens to be
# mounted: PI_DEV=1 (set by pi.sh --dev) selects the live fork repos under
# /host/data/apps when they are present; anything else uses the
# image-baked copies under /opt/pi-extensions. The provenance (source +
# SHA) of each install is echoed so the running code is always auditable.

DEV="${PI_DEV:-0}"

# self-compact: live fork (dev iteration) or image-baked copy (production).
# It keeps no state on disk (session state lives in the session journal).
SC_LIVE="/host/data/apps/self-compact-pi-agent/apps/self-compact"
SC_BAKED="/opt/pi-extensions/self-compact"
SC_SRC="$SC_BAKED"
# A live fork counts only if it actually contains a checkout. A bind source
# that does not exist on the host is auto-created by docker as an empty
# directory, which would otherwise be copied over the baked extension and
# silently disable it.
if [ "$DEV" = "1" ] && [ -f "$SC_LIVE/package.json" ]; then
    SC_SRC="$SC_LIVE"
fi
SC_DST="$HOME/.pi/agent/extensions/self-compact"
rm -rf "$SC_DST"
cp -a "$SC_SRC" "$SC_DST"
if [ "$SC_SRC" = "$SC_LIVE" ]; then
    SC_SHA="$(git -C "$(dirname "$SC_LIVE")" rev-parse --short HEAD 2>/dev/null || echo '?')"
else
    SC_SHA="$(cat "$SC_BAKED.sha" 2>/dev/null || echo '?')"
fi
echo "self-compact extension installed from $SC_SRC @ $SC_SHA"

# pi-subagents: same pattern. The live fork is source-only, so runtime
# deps come from the baked node_modules.
PS_LIVE="/host/data/apps/pi-subagents"
PS_BAKED="/opt/pi-extensions/pi-subagents"
PS_SRC="$PS_BAKED"
if [ "$DEV" = "1" ] && [ -f "$PS_LIVE/package.json" ]; then
    PS_SRC="$PS_LIVE"
fi
PS_DST="$HOME/.pi/agent/extensions/pi-subagents"
rm -rf "$PS_DST"
cp -a "$PS_SRC" "$PS_DST"
if [ ! -d "$PS_DST/node_modules" ] && [ -d "$PS_BAKED/node_modules" ]; then
    cp -a "$PS_BAKED/node_modules" "$PS_DST/node_modules"
fi
rm -rf "$PS_DST/.git" "$PS_DST/node_modules/pi-subagents"
if [ "$PS_SRC" = "$PS_LIVE" ]; then
    PS_SHA="$(git -C "$PS_LIVE" rev-parse --short HEAD 2>/dev/null || echo '?')"
else
    PS_SHA="$(cat "$PS_BAKED.sha" 2>/dev/null || echo '?')"
fi
echo "pi-subagents installed from $PS_SRC @ $PS_SHA"
echo "pi installed at /opt/pi @ $(cat /opt/pi.sha 2>/dev/null || echo '?')"

exec node /opt/pi/packages/coding-agent/dist/cli.js "$@"
