# Changelog

## 2.0.0 — 2026-05-07

### Breaking changes
- Removed `python2` shim (Python 2 EOL since 2020-01-01).
- Default `gcloud` image changed from `google/cloud-sdk` to `google/cloud-sdk:slim` (~10x smaller).
- `~/.clv/.init` is no longer wiped on uninstall (use `./uninstall --purge`).

### Added
- New shims: `clv`, `terraform`, `kubectl`, `yarn`, `pnpm`, `bun`, `deno`, `cargo`, `psql`, `mysql`, `redis-cli`, `make`.
- Env vars: `CLV_TAG`, `CLV_DRY_RUN`, `CLV_DOCKER_ARGS`, `CLV_MAP_USER`, `CLV_INSTALL_PREFIX`, `CLV_BRANCH`.
- `inc/docker`, `inc/ssh`, `inc/user` shared helpers.
- bats test suite + GitHub Actions CI (shellcheck + bats + install smoke).
- `clv` meta-command: `version`, `list`, `install`, `uninstall`, `update`, `prune`.

### Fixed
- `-a STDOUT` removed from every shim — stderr was being silently dropped.
- `install` now overwrites stale shims (was no-op on re-install).
- `init/clv` cache lookup uses fixed-string match (`grep -Fxq`).
- `web/install` and `web/uninstall` quote `"$@"` and use HTTPS error checking.
- `git` shim forwards SSH agent, `~/.ssh`, and `~/.gitconfig` (was silently failing on `git clone git@…`).
- `ncu` and `prettier` init now invoke npm via docker, not the host.
- Default branch is `main` (was hardcoded `master`).

### Changed
- All image tags now pinned via `${CLV_TAG:-<default>}`.
- `install`/`uninstall` skip `sudo` when the prefix is user-writable.
