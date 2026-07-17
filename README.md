# docker-llm: Claude Code Dev Sandbox

A hardened, disposable Docker sandbox for Python/React development with the
[Claude Code](https://docs.claude.com/en/docs/claude-code) CLI pre-installed.

## Design

```
 Host machine
 ┌────────────────────────────────────────────────────────────────────┐
 │  Docker Engine  (gVisor / runsc runtime by default)                 │
 │                                                                     │
 │   sandbox_net (internal: no route out)      egress_net              │
 │  ┌──────────────────────────────────┐  ┌───────────────────┐        │
 │  │  sandbox container               │  │  proxy container  │        │
 │  │  (non-root "vscode" user)        │──│  (Squid, domain   │──▶ internet
 │  │   - Claude Code CLI              │  │   allowlist only) │  (allowlisted
 │  │   - uv (Python), pnpm (React)    │  └───────────────────┘   domains only)
 │  │   - git, PAT auth at runtime     │                                │
 │  │   - read-only rootfs, cap_drop   │                                │
 │  │     ALL, pids/cpu/mem limits     │                                │
 │  └──────────────────────────────────┘                                │
 │        │                              │                              │
 │   bind mount                    named volume                         │
 │   ./workspace  <-->  /workspace  ~/.claude  <--> claude-config       │
 │   (your source code)             (Claude login/session state)        │
 └────────────────────────────────────────────────────────────────────┘
```

**Why it's built this way:**

- **Claude Code can run arbitrary shell commands.** Everything else in this design
  exists to bound the damage if something goes wrong: a non-root user, dropped Linux
  capabilities, `no-new-privileges`, a read-only rootfs with an ephemeral tmpfs HOME,
  process/CPU/memory limits, and (by default) the [gVisor](https://gvisor.dev/)
  (`runsc`) container runtime for syscall-level isolation on top of normal Docker
  isolation.
- **Network egress is deny-by-default.** The sandbox sits on an `internal: true`
  Docker network with no gateway — even a hostile process that ignores the proxy
  environment variables has no route anywhere. The only path out is the Squid proxy
  sidecar, which permits exactly the domains in [proxy/allowlist.txt](proxy/allowlist.txt)
  (Anthropic/Claude, GitHub, npm, PyPI) on ports 80/443, refuses connections to
  private/link-local/metadata IP ranges, and logs every attempt
  (`docker compose exec proxy tail -f /var/log/squid/access.log`). To allow another
  domain, add it there and `docker compose restart proxy`.
- **Source code lives on the host**, bind-mounted into `/workspace`. The container
  itself is disposable/rebuildable; your code is not.
- **Claude's own login state is a separate named volume** (`claude-config`), not part
  of the workspace mount. A Claude Pro OAuth login survives container rebuilds without
  mixing Claude's session state into your project's files.
- **GitHub auth uses a PAT delivered as a Docker file secret** (`.secrets/github_pat`
  → `/run/secrets/github_pat`), read once by the entrypoint at container start. It is
  never an environment variable (env vars leak into every process, crash dumps, and
  `ps e` output) and never baked into the image: the build context is limited to the
  `docker/` directory, and `.gitignore` excludes `.secrets/`. Residual risk, accepted:
  code running inside the sandbox can still read the secret file and
  `~/.git-credentials` — which is why the PAT must be narrowly scoped and short-lived,
  and why `gist.github.com` is excluded from the egress allowlist.

## Setup

1. Copy the env template and set up the PAT secret file:
   ```sh
   cp .env.example .env
   # edit .env: set GITHUB_USER, and SOURCE_DIR if not using ./workspace
   mkdir -p .secrets && chmod 700 .secrets
   printf '%s' 'github_pat_XXXX' > .secrets/github_pat && chmod 600 .secrets/github_pat
   ```
   The PAT goes in `.secrets/github_pat` (leave it empty for no GitHub auth), **not**
   in `.env` — as a Docker file secret it never appears in any process's environment.
   Use a [fine-grained PAT](https://github.com/settings/tokens?type=beta) scoped to only
   the repo(s) you need, with an expiration date.

2. Install gVisor on the **host** — the sandbox requires the `runsc` runtime and
   will not start without it:
   ```sh
   ./scripts/setup-gvisor.sh
   ```

3. Build and start the sandbox:
   ```sh
   docker compose up -d --build
   ```

4. Attach to it either:
   - **VSCode Dev Containers**: open this folder in VSCode, run
     "Dev Containers: Reopen in Container" (uses `.devcontainer/devcontainer.json`).
   - **Shell**: `docker compose exec sandbox bash`

5. Log in to Claude Code once inside the container (use a real interactive terminal, e.g.
   the VSCode integrated terminal — this won't work piped through a non-interactive shell):
   ```sh
   claude setup-token
   ```
   This persists in the `claude-config` named volume, so you won't need to log in again
   after `docker compose restart` or rebuilding the image.

## Package management

- Python deps: `uv add <package>`, `uv sync`, `uv run <command>`.
- Node/React deps: `pnpm add <package>`, `pnpm install`, `pnpm run <script>`.

## Troubleshooting

### `claude setup-token` / `/login` hangs or doesn't persist

- `claude setup-token` needs a real interactive TTY (it renders prompts in raw mode) — run
  it directly in a terminal you control (VSCode integrated terminal, or `docker compose
  exec -it sandbox bash`), not piped or redirected.
- If login appears to succeed but a subsequent command says "Not logged in" again, the
  `claude-config` volume's ownership is likely wrong (Docker creates new named volumes as
  `root:root` unless the image already has that directory pre-created and owned correctly —
  this `Dockerfile` already handles that, but if you hit it: `docker compose down`, `docker
  volume rm docker-llm_claude-config`, then `docker compose up -d --build` to let it
  re-initialize with correct ownership).

See [docker/AGENT.md](docker/AGENT.md) for the rules Claude Code itself follows inside
this sandbox.

## Repository layout

```
docker/          everything that goes into the image: Dockerfile, entrypoint.sh,
                 AGENT.md (in-container rules). Also the Docker build context.
proxy/           egress proxy config: squid.conf + allowlist.txt (host side,
                 mounted read-only into the proxy container)
scripts/         host-side helpers (gVisor install) — never enter the image
.devcontainer/   VSCode Dev Containers attach config
workspace/       your source code (gitignored), bind-mounted at /workspace
docker-compose.yml, .env(.example)   runtime wiring and secrets, host side only
```

## Security notes

- The PAT only ever enters the container as a file secret at container start — never
  via `COPY`/`ARG`/`ENV` in the `Dockerfile` and never as an environment variable. Keep
  it that way if you modify the build, and keep the build context pointed at `docker/`
  so secrets stay structurally out of reach.
- Never mount `/var/run/docker.sock` into this container; doing so would defeat all of
  the isolation above.
- All tool versions (Node, pnpm, uv, Claude Code CLI, base image, Squid image) are
  pinned rather than floating on `latest`, for reproducibility and auditability.
  Bump them deliberately.
- The rootfs is immutable (`read_only: true`) and `~/.local/bin` comes *last* on
  `PATH`, so code running in the sandbox can't replace or shadow system binaries.
  `/home/vscode` is a size-capped tmpfs wiped on every restart — the entrypoint
  restores the image's dotfiles, Claude's login state lives in the `claude-config`
  volume (`~/.claude.json` is symlinked into it), and vscode-server just re-downloads
  after a container recreate. Anything that must persist belongs in `/workspace`, the
  `Dockerfile`, or `~/.claude`. HOME is mounted `exec` (vscode-server and user tools
  must run from it) while `/tmp` stays `noexec` by design.
- Never attach the `sandbox` service to `egress_net` (or any non-internal network);
  the internal-only network is what makes the egress allowlist enforceable rather
  than advisory.
- Known residual limits of the egress design: Docker's embedded DNS may still forward
  external lookups on internal networks (a low-bandwidth DNS exfiltration channel,
  depending on Docker version), and allowlisted domains that host arbitrary user
  content (e.g. github.com) can themselves serve as exfiltration targets. Keep the
  allowlist minimal and PAT scopes narrow. Disk usage on the `/workspace` bind mount
  is not capped (host filesystem quotas would be needed); `/tmp` is capped via tmpfs.
