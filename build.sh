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
#   ./build.sh --tag pi-sandbox:test
#
# Adding a baked extension: add a row to REPOS below and a matching clone
# block in the Dockerfile (same shape as the existing ones).
set -euo pipefail

cd "$(dirname "$0")"

TAG="pi-sandbox:latest"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag) TAG="$2"; shift 2 ;;
        *) echo "unknown arg: $1 (use --tag)" >&2; exit 1 ;;
    esac
done

# name|default_url|tracked_branch|hash_override_env|build_arg_prefix
REPOS=(
    "pi|https://github.com/earendil-works/pi|main|PI_HASH|FORK"
    "pi-subagents|https://github.com/scotb/pi-subagents|self-compact|PI_SUBAGENTS_HASH|PI_SUBAGENTS"
    "self-compact|https://github.com/scotb/self-compact-pi-agent|deploy|SELF_COMPACT_HASH"
)

args=()
echo "=== Resolved build inputs ==="
for row in "${REPOS[@]}"; do
    IFS='|' read -r name url branch hash_env arg_prefix <<<"$row"
    upper="$(tr '[:lower:]' '[:upper:]' <<<"$name")"
    url="${!${upper}_URL:-$url}"
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

# Forward the optional build-time git identity if set in the environment.
for v in GIT_USER_NAME GIT_USER_EMAIL; do
    [ -n "${!v:-}" ] && args+=(--build-arg "$v=${!v}")
done

docker build "${args[@]}" -t "$TAG" -f Dockerfile .
