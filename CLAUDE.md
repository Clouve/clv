# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`clv` ships thin Bash shims that wrap CLI tools (aws, az, clv, gcloud, git, go, helm, ncu, node, npm, prettier, python, terraform, kubectl, yarn, pnpm, bun, deno, cargo, psql, mysql, redis-cli, make) so each invocation runs inside a transient Docker container. There is nothing to build or compile — installation copies the shim scripts into `/usr/local/bin/`.

## Architecture

Three layers, all under [bin/](bin/):

1. **Command shims** — [bin/aws](bin/aws), [bin/gcloud](bin/gcloud), [bin/node](bin/node), etc. One file per exposed CLI. Each shim sources its init script, optionally sources [bin/inc/ports](bin/inc/ports), then `docker run --rm` the appropriate image with `$@` forwarded.
2. **Init layer** — [bin/init/clv](bin/init/clv) is the dispatcher every shim sources first. It ensures `~/.clv/` exists, sets `CLVHOME=$HOME/.clv/<cmd>`, and runs a one-time per-image init from [bin/init/](bin/init/) (e.g. [bin/init/node](bin/init/node), [bin/init/python](bin/init/python)) — recording completion in `~/.clv/.init` so it doesn't re-run.
3. **Includes** — sourced by shims after `init/clv`:
   - [bin/inc/docker](bin/inc/docker) defines `clv_docker_run`, the single docker-run dispatcher honored by every shim. Honors `CLV_DRY_RUN=1` (print and exit) and `CLV_DOCKER_ARGS` (extra flags).
   - [bin/inc/ports](bin/inc/ports) translates the `PORTS` env into `--publish=…` flags, falling back to `--network=host`.
   - [bin/inc/ssh](bin/inc/ssh) forwards `$SSH_AUTH_SOCK`, `~/.ssh`, and `~/.gitconfig` into the container (only `git` uses this today).
   - [bin/inc/user](bin/inc/user) opt-in `--user $(id -u):$(id -g)` mapping when `CLV_MAP_USER=1`.

### Persistence model

Containers are transient (`--rm`); the per-tool home dir at `~/.clv/<cmd>` is bind-mounted to `/root` inside the container, so credentials, configs, and globally-installed packages persist across runs. The current working directory is mounted at `/clv` and set as the container's workdir, so the tool sees the user's project files.

Special cases:
- **npm** mounts `~/.clv/node` (not `~/.clv/npm`) so `node` and `npm` share the same `/root`. Globally-installed npm packages live there because [bin/init/node](bin/init/node) configures `npm config set prefix /root`.
- **python** sets `PYTHONUSERBASE=/root/base` so `pip install --user` lands in `~/.clv/python/base`.
- **helm** double-mounts `$CLVHOME/.config` over `/root/.config` in addition to the full `/root` mount.

### Install / uninstall flow

[install](install) (and its web wrapper [web/install](web/install)) runs `uninstall bin` first to clear stale shims, then copies [bin/inc/](bin/inc/) and [bin/init/](bin/init/) directory trees into `/usr/local/bin/`, then copies each top-level shim file. Three modes: `all` (no args), `commands` (whitelist), `skip` (blacklist via `-s`/`--skip`). All copies use `sudo`. [uninstall](uninstall) reverses this and also removes `~/.clv/.init`.

## Commands

```bash
./install                       # install all shims to /usr/local/bin/ (uses sudo)
./install go node               # install only listed shims
./install --skip git python     # install all except listed
./uninstall                     # remove all shims, inc/, init/, and ~/.clv/.init
./uninstall git python          # remove only listed shims
```

Tests live under [tests/](tests/) and run via `make test` (bats-core, vendored as a submodule). Lint via `make lint` (shellcheck). There is no build step. Changes to a shim take effect after re-running `./install` (or by editing `/usr/local/bin/<cmd>` directly during development).

## When adding a new command

1. Create [bin/&lt;cmd&gt;](bin/) following the pattern of [bin/aws](bin/aws) (no ports) or [bin/node](bin/node) (with ports).
2. The shim **must** start by computing `SCRIPT_PATH` and `source "$SCRIPT_PATH"/init/clv <docker-image>` — this is what populates `$CLVHOME` and `$IT` and runs first-time init.
3. If the tool needs directories pre-created in its home (config dirs, base dirs), add a matching [bin/init/&lt;image&gt;](bin/init/) script. The filename must match the **image name** passed to `init/clv`, not the command name.
4. Add the command to the list in [README.md](README.md).
5. Use `--entrypoint <cmd>` on `docker run` when the image's default entrypoint is wrong (most images need this; `amazon/aws-cli` does not).

## Environment contract for shims

Inside a shim script, after sourcing `init/clv`, these are available:
- `$CLVHOME` — `~/.clv/<command-name>`, the persistent home dir for this tool
- `$IT` — `-it` if stdin is a TTY, else `-i`
- `$SCRIPT_PATH` — directory containing the shim (so `init/` and `inc/` paths resolve)
- `$PUBLISHED_PORTS[@]` — only after sourcing `inc/ports`; expands to `--publish=…` flags or `--network=host`

## Environment contract for users

Any shim respects:
- `CLV_TAG` — override the default image tag (e.g. `CLV_TAG=20 node …` for node:20)
- `CLV_DRY_RUN=1` — print the docker command and exit instead of executing
- `CLV_DOCKER_ARGS` — extra flags spliced into `docker run` (e.g. `--memory=2g`)
- `CLV_MAP_USER=1` — run as host UID/GID (Linux file-ownership fix)
- `PORTS` — space-separated; bare numbers expand to `host:host`, colon-form passes through
