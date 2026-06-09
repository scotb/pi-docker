FROM node:lts-slim

ENV LLAMA_SERVER_URL=http://host.docker.internal:8007

# 1. Install dependencies as root
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl git && \
    apt-get clean

# Install Pi globally as root so it lands in /usr/local/bin (already on PATH)
RUN npm install -g --min-release-age=0 @earendil-works/pi-coding-agent

# Use the existing 'node' user (UID 1000) that ships with node:lts-slim
USER node
WORKDIR /workspace

CMD ["pi"]
