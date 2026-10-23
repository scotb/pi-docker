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

# The state volume is fresh on first use (agent/extensions is excluded from
# the carryover — the image owns extension code), so create it.
EXT_DIR="$HOME/.pi/agent/extensions"
mkdir -p "$EXT_DIR"

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
SC_DST="$EXT_DIR/self-compact"
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

# Baked upstream extensions (ADR-0002): the whole node_modules tree plus
# each package's own directory. pi auto-discovers the packages (their
# package.json pi.extensions manifest) and Node resolves their hoisted
# dependencies from the sibling node_modules directory. The node_modules
# directory itself is never treated as an extension by pi's discovery.
NPM_BAKED="/opt/pi-extensions/npm"
rm -rf "$EXT_DIR/node_modules"
cp -a "$NPM_BAKED/node_modules" "$EXT_DIR/node_modules"
for pkg in pi-web-access pi-hermes-memory; do
    rm -rf "$EXT_DIR/$pkg"
    cp -a "$NPM_BAKED/node_modules/$pkg" "$EXT_DIR/$pkg"
done
# pi-lean-ctx: save-restore install (ADR-0002). This extension writes host
# state (config.json, mcp-schema-cache.json) INSIDE its own install directory
# — the path is hardcoded — so the state files are moved aside, the
# directory is replaced cleanly, then the state is restored.
LC_DST="$EXT_DIR/pi-lean-ctx"
LC_STATE="$(mktemp -d)"
for f in config.json mcp-schema-cache.json; do
    if [ -f "$LC_DST/$f" ]; then mv "$LC_DST/$f" "$LC_STATE/$f"; fi
done
rm -rf "$LC_DST"
cp -a "$NPM_BAKED/node_modules/pi-lean-ctx" "$LC_DST"
for f in config.json mcp-schema-cache.json; do
    if [ -f "$LC_STATE/$f" ]; then mv "$LC_STATE/$f" "$LC_DST/$f"; fi
done
rm -rf "$LC_STATE"
# A fresh state volume has no lean-ctx state yet: seed the default config
# so the MCP bridge spawns the baked binary (this is the extension's own
# image-owned install dir, not user config).
if [ ! -f "$LC_DST/config.json" ]; then
    cat > "$LC_DST/config.json" <<'EOF'
{
  "mode": "additive",
  "enableMcp": true,
  "binary": "/opt/pi-extensions/lean-ctx/bin/lean-ctx",
  "env": {
    "LEAN_CTX_COMPRESSION": "off",
    "LEAN_CTX_DATA_DIR": "/home/ubuntu/.pi/lean-ctx"
  }
}
EOF
fi
# mcp.json — Pi's MCP server registry (user-level config). A fresh state
# volume has none yet: seed the two baked craft CLIs (the image's agent
# interfaces, rooted at /host). Never overwrite an existing file — once
# created, the volume owns it.
MCP_CONFIG="$HOME/.pi/agent/mcp.json"
if [ ! -f "$MCP_CONFIG" ]; then
    cat > "$MCP_CONFIG" <<'EOF'
{
  "mcpServers": {
    "photocraft": {
      "command": "/opt/photocraft/bin/photocraft-cli",
      "args": ["mcp", "--automation-read-root", "/host", "--automation-write-root", "/host"]
    },
    "pdfcraft": {
      "command": "/opt/pdfcraft/bin/pdfcraft-cli",
      "args": ["mcp", "--root", "/host"]
    }
  }
}
EOF
    echo "mcp.json seeded at $MCP_CONFIG (photocraft + pdfcraft servers, roots /host)"
fi
# tdd-ledger: vendored in the pi-docker repo (no upstream).
TL_DST="$EXT_DIR/tdd-ledger"
rm -rf "$TL_DST"
cp -a /opt/pi-extensions/tdd-ledger "$TL_DST"

# Baked skills (ADR-0003): the image owns skill code. ~/.pi/agent/skills/ is
# reinstalled from the image on every start, so hand-dropped skills are
# ephemeral by design. Two sources:
#   matt:  third-party, curated by skills-manifest.txt at build time
#   local: first-party, vendored in the pi-docker repo (like tdd-ledger)
SKILLS_DIR="$HOME/.pi/agent/skills"
rm -rf "$SKILLS_DIR"
mkdir -p "$SKILLS_DIR"

MATT_SKILLS=()
for d in /opt/pi-skills/mattpocock/*/; do
    [ -f "$d/SKILL.md" ] || continue
    name="$(basename "$d")"
    cp -a "$d" "$SKILLS_DIR/$name"
    MATT_SKILLS+=("$name")
done
echo "matt skills installed from /opt/pi-skills/mattpocock @ $(cat /opt/pi-skills/mattpocock.sha 2>/dev/null || echo '?') (${#MATT_SKILLS[@]}: $(IFS=', '; echo "${MATT_SKILLS[*]}"))"

LOCAL_SKILLS=()
for d in /opt/pi-skills/local/*/; do
    [ -f "$d/SKILL.md" ] || continue
    name="$(basename "$d")"
    if [ -e "$SKILLS_DIR/$name" ]; then
        echo "ERROR: skill name collision: '$name' (matt vs local)" >&2
        exit 1
    fi
    cp -a "$d" "$SKILLS_DIR/$name"
    LOCAL_SKILLS+=("$name")
done
echo "local skills installed from /opt/pi-skills/local (pi-docker repo) (${#LOCAL_SKILLS[@]}: $(IFS=', '; echo "${LOCAL_SKILLS[*]}"))"
NPM_MANIFEST="$(jq -r 'to_entries | map(.key + "-" + .value) | join(", ")' "$NPM_BAKED/manifest.json" 2>/dev/null || echo '?')"
echo "baked npm extensions installed from $NPM_BAKED @ $NPM_MANIFEST"
echo "pi-lean-ctx installed from $NPM_BAKED/node_modules/pi-lean-ctx (state saved/restored); binary @ $(cat /opt/pi-extensions/lean-ctx.version 2>/dev/null || echo '?')"
echo "tdd-ledger installed from /opt/pi-extensions/tdd-ledger @ $(cat /opt/pi-extensions/tdd-ledger.sha 2>/dev/null || echo '?') (pi-docker repo)"
echo "photocraft-cli installed from /opt/photocraft/bin @ $(cat /opt/photocraft.version 2>/dev/null || echo '?') (sha256-pinned release)"
echo "pdfcraft-cli installed from /opt/pdfcraft/bin @ $(cat /opt/pdfcraft.version 2>/dev/null || echo '?') (sha256-pinned release)"
echo "docs baked at /opt/docs @ $(cat /opt/docs.sha 2>/dev/null || echo '?') (pi-docker repo)"
echo "pi installed at /opt/pi @ $(cat /opt/pi.sha 2>/dev/null || echo '?')"

exec node /opt/pi/packages/coding-agent/dist/cli.js "$@"
