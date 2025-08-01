# Dockerfile
FROM node:20-bullseye

# Install required packages and Claude Code CLI
RUN apt-get update \
    && apt-get install -y --no-install-recommends git jq python3 \
    && npm install -g @anthropic-ai/claude-code \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set working directory inside the container where the repository will be mounted
WORKDIR /workspace

# Default command opens a bash session (the hook will override this with `bash -lc`)
CMD ["bash"]
