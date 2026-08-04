FROM mcr.microsoft.com/dotnet/sdk:10.0-noble

# Install Node.js LTS, Pi dependencies, and dev tooling
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends \
        curl \
        git \
        ripgrep \
        nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Pi globally
RUN npm install -g --min-release-age=0 @earendil-works/pi-coding-agent

# Set PATH to include the Pi bin directory
ENV PATH="/home/ubuntu/.pi/bin:${PATH}"

# The base image ships with an 'ubuntu' user at UID 1000 that we keep.
# Its home directory is /home/ubuntu, matching the pi.sh mount path for
# ~/.pi.  WORKDIR is overridden at runtime by pi.sh to the project path.
USER ubuntu
WORKDIR /workspace

# Copy bundled extensions and startup script outside of ~/.pi/ so they survive
# the host volume mount (the host mount overwrites ~/.pi/ at runtime).
COPY --chown=ubuntu:ubuntu entrypoint.sh /home/ubuntu/entrypoint.sh
COPY --chown=ubuntu:ubuntu pi-personas /opt/pi-extensions/pi-personas

ENTRYPOINT ["/home/ubuntu/entrypoint.sh"]
