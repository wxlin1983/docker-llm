# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A hardened, disposable Docker sandbox that runs the Claude Code CLI for Python/React development. The security model assumes the agent inside may run arbitrary shell commands, and every design choice exists to bound that damage.

Note the two distinct agent files: this `CLAUDE.md` guides Claude Code working **on this repo** (host side); `docker/AGENT.md` is the rules file installed **inside the sandbox container** as the in-container Claude's global memory (`~/.claude/CLAUDE.md`). Changes to sandbox behavior rules go in `docker/AGENT.md`, not here.

Layout rule: `docker/` holds everything that enters the image (Dockerfile, entrypoint.sh, AGENT.md) and is the compose build context; `scripts/` holds host-side helpers and `proxy/` the egress-proxy config — both host-side, never entering the image. Keep new files on the correct side of that line.

## Commands

```sh
docker compose up -d --build          # build and start the sandbox
docker compose exec sandbox bash      # shell into it
docker compose down                   # stop it
./scripts/setup-gvisor.sh             # (host, optional) install gVisor, then uncomment `runtime: runsc` in docker-compose.yml
```

First-time setup: `cp .env.example .env` and fill in `GITHUB_PAT`/`GITHUB_USER`. Inside the container, run `claude setup-token` once in a real interactive TTY (it hangs if piped).

There are no tests or linters in this repo; verification means rebuilding the image and exercising the container.

## Architecture

Three kinds of state, deliberately separated — the container itself is disposable:

- **Source code**: host `./workspace` (or `SOURCE_DIR`) bind-mounted at `/workspace`. `workspace/` is user project data, not part of this repo (gitignored); don't treat its contents (e.g. `.pnpm-store`) as code to maintain.
- **Claude login state**: named volume `claude-config` mounted at `/home/vscode/.claude`, survives rebuilds.
- **Secrets**: `GITHUB_PAT` lives only in host `.env`, injected at container start via compose `env_file`. It must never enter the image via `COPY`/`ARG`/`ENV` — the build context is limited to `docker/`, so `.env` is structurally outside it, and `.gitignore` keeps it uncommitted.

Startup flow: `docker/entrypoint.sh` runs on every container start. It copies `/opt/sandbox/AGENT.md` to `~/.claude/CLAUDE.md` only if absent (user edits persist), and writes the PAT into `~/.git-credentials` via git's `store` credential helper.

Security layers (don't loosen one to "fix" a problem another layer causes):
- Non-root `vscode` user, with passwordless sudo explicitly removed in the Dockerfile
- `cap_drop: ALL`, `no-new-privileges`, `pids_limit: 256` in docker-compose.yml
- Resource caps: `cpus`/`mem_limit` (overridable via `SANDBOX_CPUS`/`SANDBOX_MEM_LIMIT` in `.env`), tmpfs-bounded `/tmp`
- Network egress: sandbox sits on an `internal: true` network with no route out; its only path is the `proxy` service (Squid) enforcing the domain allowlist in `proxy/allowlist.txt`. The proxy env vars in compose are convenience — the internal network is the actual enforcement, so never attach `sandbox` to `egress_net`. To allow a new domain: edit `proxy/allowlist.txt`, then `docker compose restart proxy`.
- Optional gVisor (`runsc`) runtime for syscall-level isolation
- Never mount `/var/run/docker.sock` into the container

Known residual limits (documented, not bugs to "fix" silently): Docker's embedded DNS may still forward external lookups on internal networks (low-bandwidth exfil channel), allowlisted domains that host user content (github.com) remain possible exfil targets, and disk on the `/workspace` bind mount is uncapped.

## Non-obvious constraints

- The Dockerfile pre-creates `~/.claude` owned by `vscode` **before** it becomes a volume mount point. Docker initializes a brand-new named volume's ownership from what exists at that path in the image; removing this line silently breaks `claude login` (volume becomes `root:root`). Similarly, `AGENT.md` is copied to `/opt/sandbox/`, not into `~/.claude`, because files baked into a volume mount path only reach a *brand-new* volume.
- All tool versions (base image, Node major, pnpm, uv, Claude Code CLI) are pinned as Dockerfile `ARG`s. Bump them deliberately; never switch to `latest`.
- Inside the sandbox, package management is standardized: `uv` for Python, `pnpm` for Node (see `docker/AGENT.md`). Keep the Dockerfile and AGENT.md consistent if tooling changes.
- `.devcontainer/devcontainer.json` attaches VSCode to the same compose service (`sandbox`); it references `../docker-compose.yml`, so compose changes affect both entry paths.
