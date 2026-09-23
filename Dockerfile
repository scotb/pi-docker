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
#   GIT_USER_NAME / GIT_USER_EMAIL
#                Optional local-only git identity for commits made inside the
#                container (author name/email). No credentials are stored —
#                push/pull are handled manually on the host.
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
# If FORK_HASH is set (full SHA), we check out that exact commit.
#   - If it is the current tip of the default branch, nothing extra is fetched.
#   - If it is an older commit, we fetch just that commit (GitHub allows
#     fetching any reachable SHA) and check it out.
# If FORK_HASH is empty, we build whatever the default branch points to.
#
# npm run build builds all packages (Node.js-compatible output).
# Note: we intentionally do NOT run build:binary to avoid Bun dependency.
RUN git clone --depth 1 "${FORK_URL}" pi \
    && cd pi \
    && if [ -n "${FORK_HASH}" ]; then \
           if [ "$(git rev-parse HEAD)" != "${FORK_HASH}" ]; then \
               git fetch --depth 1 origin "${FORK_HASH}" \
                   || (echo "ERROR: commit ${FORK_HASH} not found" >&2; exit 1); \
               git checkout "${FORK_HASH}" \
                   || (echo "ERROR: cannot checkout ${FORK_HASH}" >&2; exit 1); \
           fi; \
       fi \
    && npm ci --ignore-scripts \
    && npm run build

# Stage the whole built monorepo (preserves symlinks and package
# structure) for the runtime stage.
RUN mkdir -p /tmp/pi-dist \
    && cp -a /tmp/pi/* /tmp/pi-dist/

# ── Runtime stage ────────────────────────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/sdk:10.0-noble

# Optional local-only git identity (identity only — no credentials).
# Example:
#   docker build --build-arg GIT_USER_NAME="Your Name" \
#                --build-arg GIT_USER_EMAIL="you@example.com" -t pi-sandbox .
ARG GIT_USER_NAME=
ARG GIT_USER_EMAIL=

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

# ---------------------------------------------------------------------------
# Headless browser (Playwright-managed Chromium) so agents can visually
# inspect pages under development.
#
# Ubuntu 24.04's apt 'chromium-browser' is a snap stub that does not work
# inside Docker, so install Playwright's standalone Chromium build instead,
# along with its system dependencies (--with-deps). Browsers land in
# /opt/playwright-browsers and are world-readable (pi runs as 'ubuntu').
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers
# PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1: the npm package's postinstall would
# otherwise download Chromium a second time to the default cache; the
# explicit `playwright install` below places it in $PLAYWRIGHT_BROWSERS_PATH.
RUN PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install -g playwright@1.63.0 \
    && playwright install --with-deps chromium \
    && NODE_PATH="$(npm root -g)" node -e "require('playwright'); console.log('playwright resolvable: OK')"
# Make the globally installed playwright package resolvable via
# require('playwright') from helper scripts and pi extensions.
# (NodeSource installs Node under /usr in this image, so npm's global
# root is /usr/lib/node_modules, not /usr/local/lib/node_modules.)
ENV NODE_PATH=/usr/lib/node_modules
# page-shot: renders a URL with headless Chromium and writes a PNG so the
# agent can view it with the built-in read tool (the model must be
# vision-capable: "input": ["text", "image"] in models.json). Workflow:
#   page-shot http://localhost:3000 /tmp/page.png && read /tmp/page.png
COPY tools/page-shot.cjs /usr/local/bin/page-shot
RUN chmod +x /usr/local/bin/page-shot

# Copy the built Pi into /opt/pi/.
COPY --from=build /tmp/pi-dist /opt/pi

# Trim the npm cache carried over from the build stage
RUN rm -rf /opt/pi/node_modules/.cache

# Set PATH to include the Pi bin directory (for lean-ctx host binaries)
ENV PATH="/home/ubuntu/.pi/bin:${PATH}"

# The base image ships with an 'ubuntu' user at UID 1000.
WORKDIR /workspace
USER ubuntu

# Apply the git identity as the ubuntu user (writes /home/ubuntu/.gitconfig).
# Identity only — no credentials; push/pull are done manually on the host.
RUN if [ -n "${GIT_USER_NAME}" ] && [ -n "${GIT_USER_EMAIL}" ]; then \
        HOME=/home/ubuntu git config --global user.name "${GIT_USER_NAME}" \
        && HOME=/home/ubuntu git config --global user.email "${GIT_USER_EMAIL}" \
        && HOME=/home/ubuntu git config --global --list; \
    else \
        echo "GIT_USER_NAME / GIT_USER_EMAIL not set — skipping git identity"; \
    fi

# Copy bundled extensions and startup script outside of ~/.pi/ so they survive
# the host volume mount (the host mount overwrites ~/.pi/ at runtime).
COPY --chown=ubuntu:ubuntu entrypoint.sh /home/ubuntu/entrypoint.sh
# self-compact extension (vendored fork — see self-compact-pi-agent/SYNC.md).
COPY --chown=ubuntu:ubuntu self-compact-pi-agent/apps/self-compact /opt/pi-extensions/self-compact
# Context thresholds for the self-compact extension, applied to every Pi process in the
# container (parent sessions AND pi-subagents children). Precedence: --compact-* CLI flag > env > shipped default.
# soft 50% / warning 70% / forced 85% (70% + 15% buffer) of the active model's context window.
ENV SELF_COMPACT_SOFT_AT="50%" \
    SELF_COMPACT_AT="70%" \
    SELF_COMPACT_BUFFER="15%"

ENTRYPOINT ["/home/ubuntu/entrypoint.sh"]
