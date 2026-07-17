# Agent Guide: Claude Code Dev Sandbox

You (Claude Code) are running inside a containerized sandbox. This file tells you the
rules of this environment so you don't fight its design.

## Environment

- You run as the non-root user `vscode`, in `/workspace`. `sudo` is not available —
  don't try to use it, and don't suggest installing it.
- `/workspace` is a bind mount from the host. Files you create/edit there persist on
  the host filesystem and survive container restarts/rebuilds.
- The root filesystem is **read-only**. The only writable locations are `/workspace`,
  `~/.claude`, and the tmpfs mounts at `/tmp` and `$HOME`. Attempts to write anywhere
  else (e.g. `npm install -g`, `/usr/local/...`) will fail by design — don't fight it.
- Everything outside `/workspace` and `~/.claude` is ephemeral; `$HOME` is a tmpfs
  that is wiped on every container restart (dotfiles are restored automatically).
  Don't write state you expect to survive a restart anywhere but `/workspace` or
  `~/.claude`.
- `~/.claude` is a named Docker volume, not part of `/workspace`. It holds your own
  login/session state and survives rebuilds, but it is not source code and should
  never be treated as a place to stash project files.

## Package management

- Python: use **`uv`** (`uv add`, `uv sync`, `uv run`). Do not use `pip install`,
  `poetry`, or `pipenv` directly — this project standardizes on `uv`.
- JavaScript/TypeScript: use **`pnpm`** (`pnpm add`, `pnpm install`, `pnpm run`). Do not
  use `npm` or `yarn` — `corepack` is configured for `pnpm` only.

## Git / GitHub

- Git authentication to GitHub is already configured via a credential helper backed by
  a PAT injected at container start (the image's entrypoint script). You do not need to set up
  SSH keys, run `gh auth login`, or prompt the user for credentials — `git clone`,
  `git push`, `git pull` against `https://github.com/...` URLs just work.
- Never write a GitHub token into a committed file, Dockerfile `ENV`/`ARG`, or any file
  under `/workspace` that might get committed. The PAT lives only in the host's `.env`
  file and is injected at runtime — keep it that way.

## Network

- This container has **no direct route to the internet**. All outbound traffic goes
  through an egress proxy (already configured via `HTTP_PROXY`/`HTTPS_PROXY`) that only
  allows an explicit domain allowlist: Anthropic/Claude, GitHub, npm registry, PyPI.
- If a legitimate task needs a domain that's blocked (proxy returns 403), tell the user
  to add it to `proxy/allowlist.txt` on the host and run `docker compose restart proxy`.
  Do not attempt to tunnel, use alternate ports/mirrors, or otherwise route around the
  proxy — blocked-by-default is the intended design, not a bug.

## Security model

- This container is intentionally locked down: no Linux capabilities (`cap_drop: ALL`),
  `no-new-privileges`, a process-count limit, and (when the host has it set up) the
  gVisor (`runsc`) runtime for syscall-level isolation. Don't suggest re-adding
  capabilities, installing `sudo`, or loosening `security_opt` to "fix" something —
  find a workaround that respects the sandbox instead, and flag it to the user if a
  task genuinely requires elevated privileges.
- Do not attempt to mount or access the Docker socket (`/var/run/docker.sock`) from
  inside this container under any circumstances.

## When something seems missing

If a tool, language version, or system package isn't installed, don't silently `apt-get
install` something persistent and unpinned. Tell the user, and prefer adding it properly
to the `Dockerfile` (with a pinned version) so it persists across rebuilds instead of
being a one-off change that disappears next time the image is rebuilt.
