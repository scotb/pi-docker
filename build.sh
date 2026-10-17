#!/usr/bin/env bash
# build.sh — build the pi-sandbox image with resolved, pinned inputs.
#
# Each baked repo is resolved to a full SHA: by default the current head of
# its tracked branch (git ls-remote — no clone, no auth for public repos),
# overridable per repo via env var. The resolved inputs are echoed before
# the build so the exact provenance is on the record. The Dockerfile
# refuses to build with empty hashes, so this script (or explicit
# --build-arg values) is always required.
#
#   ./build.sh                                     # heads of tracked branches
#   PI_SUBAGENTS_HASH=a85db042... ./build.sh       # pin one repo to a commit
#   PI_URL=https://github.com/you/pi ./build.sh    # point pi at a fork
#   GIT_USER_NAME="S" GIT_USER_EMAIL="s@x" ./build.sh
#   ./build.sh --tag pi-sandbox:1.3.0 --tag pi-sandbox:2026-10-15
#     (--tag is repeatable; pi-sandbox:latest is always tagged)
#
# Adding a baked extension:
#   git fork      — add a row to REPOS below and a matching clone block in
#                   the Dockerfile (same shape as the existing ones).
#   upstream npm  — add the exact version to vendor/extension-lock/package.json,
#                   regenerate package-lock.json, and add the package to the
#                   Dockerfile's manifest jq line + the entrypoint's install loop.
#   local code    — vendor the file(s) under vendor/<name>/, COPY them in the
#                   Dockerfile, and add an install block in entrypoint.sh.
set -euo pipefail

cd "$(dirname "$0")"

TAGS=("pi-sandbox:latest")
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag) TAGS+=("$2"); shift 2 ;;
        *) echo "unknown arg: $1 (use --tag, repeatable)" >&2; exit 1 ;;
    esac
done

# name|default_url|tracked_branch|hash_override_env|build_arg_prefix
REPOS=(
    "pi|https://github.com/earendil-works/pi|main|PI_HASH|FORK"
    "pi-subagents|https://github.com/scotb/pi-subagents|self-compact|PI_SUBAGENTS_HASH|PI_SUBAGENTS"
    "self-compact|https://github.com/scotb/self-compact-pi-agent|deploy|SELF_COMPACT_HASH|SELF_COMPACT"
)

args=()
echo "=== Resolved build inputs ==="
for row in "${REPOS[@]}"; do
    IFS='|' read -r name url branch hash_env arg_prefix <<<"$row"
    upper="$(tr '[:lower:]' '[:upper:]' <<<"$name" | tr '-' '_')"
    url_env="${upper}_URL"
    url="${!url_env:-$url}"
    sha="${!hash_env:-}"
    if [ -z "$sha" ]; then
        sha="$(git ls-remote "$url" "refs/heads/$branch" | awk 'NR==1{print $1}')"
        [ -n "$sha" ] || { echo "ERROR: cannot resolve head of $name '$branch' @ $url" >&2; exit 1; }
        src="head of $branch"
    else
        src="pinned"
    fi
    echo "  $name: $url @ $sha ($src)"
    args+=(--build-arg "${arg_prefix}_URL=$url" --build-arg "${arg_prefix}_HASH=$sha")
done

# Record this repo's own commit as the tdd-ledger provenance pin.
args+=(--build-arg "TDD_LEDGER_SHA=$(git rev-parse HEAD 2>/dev/null || echo '?')")

# Forward the optional build-time git identity if set in the environment.
for v in GIT_USER_NAME GIT_USER_EMAIL LEAN_CTX_BIN_VERSION LEAN_CTX_BIN_SHA256; do
    [ -n "${!v:-}" ] && args+=(--build-arg "$v=${!v}")
done

tag_args=()
for t in "${TAGS[@]}"; do
    tag_args+=(-t "$t")
done
docker build --no-cache "${args[@]}" "${tag_args[@]}" -f Dockerfile .
