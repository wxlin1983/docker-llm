# Pinned base: Ubuntu 24.04 devcontainer image with a non-root "vscode" user already set up.
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Bump deliberately, not floating on @latest.
ARG NODE_MAJOR=22
ARG PNPM_VERSION=11.9.0
ARG UV_VERSION=0.9.7
ARG CLAUDE_CODE_VERSION=2.1.187

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        curl \
        build-essential \
        ca-certificates \
        gnupg \
    && rm -rf /var/lib/apt/lists/*

# Node.js (pinned major version) via NodeSource.
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# pnpm via corepack, pinned version.
RUN corepack enable \
    && corepack prepare pnpm@${PNPM_VERSION} --activate

# Claude Code CLI, pinned version.
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
    && npm cache clean --force

# Drop passwordless sudo for the default user: defense in depth alongside
# no-new-privileges, since sudo itself is typically a setuid-root binary.
RUN rm -f /etc/sudoers.d/vscode \
    && (deluser vscode sudo 2>/dev/null || true) \
    && (deluser vscode admin 2>/dev/null || true)

USER vscode
ENV HOME=/home/vscode
ENV PATH="${HOME}/.local/bin:${PATH}"

# uv, pinned version, installed for the non-root user.
RUN curl -LsSf https://astral.sh/uv/${UV_VERSION}/install.sh | sh

# Pre-create ~/.claude, owned by vscode, *before* it's used as a volume mount
# point. Docker only initializes a brand-new named volume's ownership/contents
# from whatever already exists at that path in the image; without this, Docker
# would create the mount point itself as root:root, silently breaking
# `claude login` for the non-root vscode user (no need to relax cap_drop/run
# as root to fix this).
RUN mkdir -p "${HOME}/.claude"

# AGENT.md (sandbox rules for Claude Code itself) goes to a path outside the
# ~/.claude volume mount, since anything copied directly into ~/.claude here
# would only land in a brand-new volume, not one that already exists. The
# entrypoint installs it into ~/.claude/CLAUDE.md (Claude's global memory) on
# every start if not already present there.
COPY --chown=vscode:vscode AGENT.md /opt/sandbox/AGENT.md

WORKDIR /workspace

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
