#!/usr/bin/env bash
set -euo pipefail

# Install the sandbox's agent guide into Claude's global memory if not already
# present, so Claude Code follows it regardless of which project is mounted at
# /workspace. Never overwrites an existing file, so user edits persist.
if [[ ! -f "${HOME}/.claude/CLAUDE.md" ]]; then
    cp /opt/sandbox/AGENT.md "${HOME}/.claude/CLAUDE.md"
fi

# Configure git authentication from the GITHUB_PAT/GITHUB_USER env vars supplied
# via docker-compose's env_file at container start. The PAT never appears in the
# image -- only here, at runtime.
if [[ -n "${GITHUB_PAT:-}" ]]; then
    git config --global credential.helper store
    echo "https://${GITHUB_USER:-x-access-token}:${GITHUB_PAT}@github.com" > "${HOME}/.git-credentials"
    chmod 600 "${HOME}/.git-credentials"
fi

git config --global --add safe.directory /workspace

exec "$@"
