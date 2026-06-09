#!/usr/bin/env bash
set -euo pipefail

LLAMA_SERVER_URL="${LLAMA_SERVER_URL:-http://host.docker.internal:8007}"

# Run the container with the given command
docker run -it \
        --name "pi-docker" \
        --rm \
        -v "$HOME/.pi:/home/node/.pi" \
        -v "$(pwd):/workspace" \
        -e "LLAMA_SERVER_URL=$LLAMA_SERVER_URL" \
        pi-portable "$@"

# Main
# if [ "$#" -eq 0 ]; then
#     # No args — start an interactive bash session
#     run bash
# else
#     # Args provided — run Pi with them
#     run pi "$@"
# fi
