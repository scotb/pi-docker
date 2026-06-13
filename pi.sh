#!/usr/bin/env bash
set -euo pipefail

# Run the container with the given command
docker run -it --rm \
        -v "$HOME/.pi:/home/ubuntu/.pi" \
        -v "$(pwd):/workspace" \
        -e "LLAMA_SERVER_URL=http://host.docker.internal:8007" \
        -w /workspace \
        pi-portable "$@"
