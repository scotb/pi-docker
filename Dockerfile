# pi-portable — Containerized Pi development environment
#
# Two-stage build:
#   Stage 1 (build):  Clone the Pi monorepo, install deps, build all packages
#   Stage 2 (runtime): Install Node.js and deps for running pi
#
# Build args:
#   FORK_URL   — Git URL for the Pi monorepo (default: official repo)
#   FORK_HASH  — Full 40-char commit hash to pin the build to.
#                Recommended over branch names for reproducible, auditable builds.
# ==============================================================================

# ── Build stage ──────────────────────────────────────────────────────────────
ARG FORK_URL=https://github.com/earendil-works/pi
ARG FORK_HASH=

FROM mcr.microsoft.com/dotnet/sdk:10.0-noble AS build

ARG FORK_URL
ARG FORK_HASH

# Install Node 22
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends \
        git \
        ripgrep \
        unzip \
        ca-certificates \
        curl \
        nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/local/bin:${PATH}"

WORKDIR /tmp

# Verify tools are available before attempting the build
RUN echo "=== Node ===" && node --version \
    && echo "=== npm ===" && npm --version

# Clone the repository at the pinned commit.
# --depth 1 for a shallow clone (no unnecessary history).
# If FORK_HASH is set, we check out that exact commit.
# If FORK_HASH is empty, we build whatever the default branch points to.
#
# npm run build builds all packages (Node.js-compatible output).
# Note: we intentionally do NOT run build:binary to avoid Bun dependency.
RUN git clone --depth 1 "${FORK_URL}" pi \
    && cd pi \
    && if [ -n "${FORK_HASH}" ]; then \
           git checkout "${FORK_HASH}" || (echo "ERROR: commit ${FORK_HASH} not found" >&2; exit 1); \
       fi \
    && npm ci --ignore-scripts \
    && npm run build

# Stage the whole built monorepo (preserves symlinks and package
# structure) for the runtime stage.
RUN mkdir -p /tmp/pi-dist \
    && cp -a /tmp/pi/* /tmp/pi-dist/

# ── Runtime stage ────────────────────────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/sdk:10.0-noble

# Install Node 22, runtime deps, and a standard dev toolset.
# This is a developer environment — tools like neovim, jq, strace, etc. are
# available out of the box.  ripgrep is used by Pi's built-in search.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends \
        curl \
        git \
        ripgrep \
        jq \
        unzip \
        wget \
        openssh-client \
        neovim \
        strace \
        sysstat \
        procps \
        nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/local/bin:${PATH}"

# Copy the built Pi into /opt/pi/.
COPY --from=build /tmp/pi-dist /opt/pi

# Trim the npm cache carried over from the build stage
RUN rm -rf /opt/pi/node_modules/.cache

# Set PATH to include the Pi bin directory (for lean-ctx host binaries)
ENV PATH="/home/ubuntu/.pi/bin:${PATH}"

# The base image ships with an 'ubuntu' user at UID 1000.
WORKDIR /workspace
USER ubuntu

# Copy bundled extensions and startup script outside of ~/.pi/ so they survive
# the host volume mount (the host mount overwrites ~/.pi/ at runtime).
COPY --chown=ubuntu:ubuntu entrypoint.sh /home/ubuntu/entrypoint.sh
# COPY --chown=ubuntu:ubuntu pi-personas /opt/pi-extensions/pi-personas  # Removed - use extension on host instead of baking into image

ENTRYPOINT ["/home/ubuntu/entrypoint.sh"]
