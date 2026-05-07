# clv

Thin Bash shims that wrap CLI tools so each invocation runs inside a transient Docker container. Persistent per-tool config lives at `~/.clv/<command>/`. Nothing to compile; install copies the shims to `/usr/local/bin/`.

## Available commands

| Cloud | VCS | Languages | Build/Lint | Databases | K8s |
|---|---|---|---|---|---|
| `aws` | `git` | `node`, `npm`, `yarn`, `pnpm`, `bun`, `deno` | `make`, `prettier`, `ncu` | `psql`, `mysql`, `redis-cli` | `kubectl`, `helm` |
| `az` |   | `go`, `python`, `cargo` |   |   | `terraform` |
| `gcloud` |   |   |   |   |   |

Plus `clv` itself (`clv version | list | install | uninstall | update | prune`).

## Install

Install everything:

```bash
curl -fsSL https://raw.githubusercontent.com/Clouve/clv/main/web/install | bash
```

Install a subset:

```bash
curl -fsSL https://raw.githubusercontent.com/Clouve/clv/main/web/install | bash -s -- aws kubectl
```

Install all but a few:

```bash
curl -fsSL https://raw.githubusercontent.com/Clouve/clv/main/web/install | bash -s -- --skip mysql redis-cli
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/Clouve/clv/main/web/uninstall | bash
```

`./uninstall --purge` also removes `~/.clv/`.

## Environment variables

All shims respect:

| Var | Effect |
|---|---|
| `CLV_TAG` | Override the default image tag for the next call (`CLV_TAG=20 node script.js` uses `node:20`). |
| `CLV_DRY_RUN=1` | Print the `docker run` command instead of executing it — useful for debugging. |
| `CLV_DOCKER_ARGS` | Spliced verbatim into the `docker run` invocation (e.g. `CLV_DOCKER_ARGS=--memory=2g`). |
| `CLV_MAP_USER=1` | Run as host UID/GID. Fixes root-owned files in `~/.clv/<cmd>/` on Linux; not needed on macOS Docker Desktop. |
| `PORTS` | Space-separated. Bare numbers expand to `host:host`. Colon-form passes through. Unset → `--network=host`. |

Examples:

```bash
PORTS="8080 5432" npm start
PORTS="127.0.0.1:8080:8080" go run main.go
CLV_TAG=3.12 python script.py
CLV_DRY_RUN=1 git clone …    # see what would run
```

## Persistence

Each command's HOME is bind-mounted from `~/.clv/<cmd>/`, so credentials, configs, and globally-installed packages survive across calls. `node`, `npm`, `yarn`, `pnpm`, `ncu`, and `prettier` share a single `~/.clv/node/` so global packages are visible to all of them.

## Notes / caveats

- **macOS / Docker Desktop:** `--network=host` (the default when `PORTS` is unset) maps to bridge networking on Docker Desktop. If you need port access from the host, set `PORTS` explicitly.
- **Linux file ownership:** Without `CLV_MAP_USER=1`, files written under `~/.clv/<cmd>/` are root-owned. Set `CLV_MAP_USER=1` per-call or in your shell profile.
- **Image pulls:** First call to each shim pulls the image (~MB to GB depending on tool). `clv update` re-pulls all installed shims' images.

## Hacking

```bash
# Lint
make lint
# Test
make test
# Re-install after edits
./install
```

See [CLAUDE.md](CLAUDE.md) for architecture details.

## License

[MIT](LICENSE)
