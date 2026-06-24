# docker-llm: Claude Code Dev Sandbox

A hardened, disposable Docker sandbox for Python/React development with the
[Claude Code](https://docs.claude.com/en/docs/claude-code) CLI pre-installed.

## Design

```
 Host machine
 ┌─────────────────────────────────────────────────────────────┐
 │  Docker Engine  (optionally using the gVisor / runsc runtime)│
 │  ┌──────────────────────────────────────────────────────┐    │
 │  │  sandbox container (non-root "vscode" user)          │    │
 │  │   - Claude Code CLI                                  │    │
 │  │   - uv (Python), pnpm (Node/React)                   │    │
 │  │   - git, configured with PAT-based auth at runtime   │    │
 │  │   - cap_drop: ALL, no-new-privileges, pids_limit      │    │
 │  └──────────────────────────────────────────────────────┘    │
 │        │                              │                       │
 │   bind mount                    named volume                  │
 │   ./workspace  <-->  /workspace  ~/.claude  <--> claude-config │
 │   (your source code)             (Claude login/session state) │
 └─────────────────────────────────────────────────────────────┘
```

**Why it's built this way:**

- **Claude Code can run arbitrary shell commands.** Everything else in this design
  exists to bound the damage if something goes wrong: a non-root user, dropped Linux
  capabilities, `no-new-privileges`, a process-count limit, and (optionally) the
  [gVisor](https://gvisor.dev/) (`runsc`) container runtime for syscall-level isolation
  on top of normal Docker isolation.
- **Source code lives on the host**, bind-mounted into `/workspace`. The container
  itself is disposable/rebuildable; your code is not.
- **Claude's own login state is a separate named volume** (`claude-config`), not part
  of the workspace mount. A Claude Pro OAuth login survives container rebuilds without
  mixing Claude's session state into your project's files.
- **GitHub auth uses a PAT**, injected only at container *runtime* via `docker-compose`
  `env_file`. It is never baked into the image (`.dockerignore`/`.gitignore` explicitly
  exclude `.env*`), so it can't leak into an image layer or get committed.

## Setup

1. Copy the env template and fill in your GitHub PAT:
   ```sh
   cp .env.example .env
   # edit .env: set GITHUB_PAT, GITHUB_USER, and SOURCE_DIR if not using ./workspace
   ```
   Use a [fine-grained PAT](https://github.com/settings/tokens?type=beta) scoped to only
   the repo(s) you need, with an expiration date.

2. (Optional, recommended) Install gVisor on the **host**:
   ```sh
   ./scripts/setup-gvisor.sh
   ```
   Then uncomment `runtime: runsc` in `docker-compose.yml`.

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

See [AGENT.md](AGENT.md) for the rules Claude Code itself follows inside this sandbox.

## Security notes

- The PAT only ever enters the container via `env_file` at container start — never via
  `COPY`/`ARG`/`ENV` in the `Dockerfile`. Keep it that way if you modify the build.
- Never mount `/var/run/docker.sock` into this container; doing so would defeat all of
  the isolation above.
- All tool versions (Node, pnpm, uv, Claude Code CLI, base image) are pinned in the
  `Dockerfile` rather than floating on `latest`, for reproducibility and auditability.
  Bump them deliberately.
