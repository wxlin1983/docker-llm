#!/usr/bin/env bash
set -euo pipefail

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
