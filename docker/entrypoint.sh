#!/usr/bin/env bash
set -euo pipefail

# HOME is an ephemeral tmpfs (the rootfs is read-only); restore the image's
# home skeleton (shell dotfiles etc.) on every start. -n never overwrites a
# file that already exists — notably anything inside the ~/.claude volume.
cp -anT /opt/sandbox/home-skel "${HOME}" || true

# Claude Code keeps per-user state (onboarding, project trust) in
# ~/.claude.json, *outside* the ~/.claude volume. HOME resets on every
# restart, so keep the real file in the volume and reach it via symlink.
if [[ ! -e "${HOME}/.claude.json" ]]; then
    ln -sf "${HOME}/.claude/.claude.json" "${HOME}/.claude.json"
fi

# Install the sandbox's agent guide into Claude's global memory if not already
# present, so Claude Code follows it regardless of which project is mounted at
# /workspace. Never overwrites an existing file, so user edits persist.
if [[ ! -f "${HOME}/.claude/CLAUDE.md" ]]; then
    cp /opt/sandbox/AGENT.md "${HOME}/.claude/CLAUDE.md"
fi

# Configure git authentication from the Docker file secret (never an env var:
# env vars would be visible to every process in the container). An empty or
# missing secret file simply means no GitHub auth is configured.
if [[ -s /run/secrets/github_pat ]]; then
    git config --global credential.helper store
    echo "https://${GITHUB_USER:-x-access-token}:$(< /run/secrets/github_pat)@github.com" > "${HOME}/.git-credentials"
    chmod 600 "${HOME}/.git-credentials"
fi

git config --global --add safe.directory /workspace

exec "$@"
