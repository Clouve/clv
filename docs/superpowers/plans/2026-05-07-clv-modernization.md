# clv Modernization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix latent bugs in the existing clv shims, modernize Docker image references, drop dead dependencies, add a meta `clv` command and ~11 new shims, and stand up a test/CI baseline so future changes can ship safely.

**Architecture:** Keep the proven 3-layer architecture (top-level shim → `bin/init/` first-run hook → `bin/inc/` mixins). Introduce a single shared `bin/inc/docker` helper so all shims compose the `docker run` invocation through one code path — that lets us fix bugs once instead of 13 times and adds a `CLV_DRY_RUN` mode that prints (rather than executes) the docker command, which doubles as the test seam. Tests use [bats-core](https://github.com/bats-core/bats-core) driving shims with `CLV_DRY_RUN=1`. Bug fixes ship before any feature work; new shims and the meta `clv` command come last.

**Tech Stack:** Bash 3.2+ (macOS compat), Docker, bats-core (test runner), shellcheck (lint), GitHub Actions (CI).

**Final command roster after this plan:**
- **Kept & modernized (11):** aws, az, gcloud, git, go, helm, ncu, node, npm, prettier, python
- **Removed (1):** python2 (Python 2 EOL since 2020-01-01)
- **Added (12):** clv (meta), terraform, kubectl, yarn, pnpm, bun, deno, cargo, psql, mysql, redis-cli, make

**Phase order (must execute in order; tasks within a phase can be done independently):**
1. Phase 0 — Test harness (Tasks 1–3)
2. Phase 1 — Shared docker helper + dry-run seam (Tasks 4–5)
3. Phase 2 — Bug fixes (Tasks 6–11)
4. Phase 3 — Modernization (Tasks 12–15)
5. Phase 4 — Shim feature improvements (Tasks 16–19)
6. Phase 5 — Meta `clv` command (Task 20)
7. Phase 6 — New shims (Tasks 21–31)
8. Phase 7 — CI + project hygiene (Tasks 32–35)

---

## Phase 0 — Test harness

We can't TDD the rest of this plan without a way to assert what a shim *would* run. `CLV_DRY_RUN=1` (added in Task 4) is the seam; bats is the runner. This phase wires up bats and writes a smoke test that captures the current — pre-change — behavior of every shim, so later refactors don't silently regress them.

### Task 1: Add bats-core as a vendored test dependency

**Files:**
- Create: `tests/bats/.gitkeep`
- Modify: `.gitignore`

- [ ] **Step 1: Create the tests directory structure**

```bash
mkdir -p /Users/aj/Projects/clv/tests/bats
mkdir -p /Users/aj/Projects/clv/tests/helpers
touch /Users/aj/Projects/clv/tests/bats/.gitkeep
```

- [ ] **Step 2: Vendor bats-core, bats-support, bats-assert as git submodules**

Run:
```bash
cd /Users/aj/Projects/clv
git submodule add https://github.com/bats-core/bats-core.git tests/bats/bats-core
git submodule add https://github.com/bats-core/bats-support.git tests/bats/bats-support
git submodule add https://github.com/bats-core/bats-assert.git tests/bats/bats-assert
```

- [ ] **Step 3: Add a Makefile with `make test` target**

Create `/Users/aj/Projects/clv/Makefile`:

```makefile
.PHONY: test lint

test:
	./tests/bats/bats-core/bin/bats tests/

lint:
	shellcheck install uninstall bin/* bin/init/* bin/inc/*
```

- [ ] **Step 4: Update .gitignore to ignore .DS_Store inside tests/**

Replace contents of `.gitignore`:

```
.DS_Store
.idea
*.swp
clv.zip
clv-master/
```

- [ ] **Step 5: Verify bats works**

Run: `make test`
Expected: bats runs against an empty tests/ directory and reports `1..0` (no tests yet) — exit 0.

- [ ] **Step 6: Commit**

```bash
git add .gitignore .gitmodules tests/ Makefile
git commit -m "test: vendor bats-core and add make test target"
```

### Task 2: Add a shared bats helper that loads bats-support and bats-assert

**Files:**
- Create: `tests/helpers/load.bash`

- [ ] **Step 1: Write the helper**

Create `/Users/aj/Projects/clv/tests/helpers/load.bash`:

```bash
#!/usr/bin/env bash
# Source this from the `setup()` of any bats test file:
#   load '../helpers/load'

TESTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
REPO_ROOT="$(cd "$TESTS_ROOT/.." && pwd -P)"

load "$TESTS_ROOT/bats/bats-support/load"
load "$TESTS_ROOT/bats/bats-assert/load"

# Run a shim from the repo with CLV_DRY_RUN=1 so it prints the docker
# command instead of executing it. Output is captured in $output by bats `run`.
clv_dry() {
  CLV_DRY_RUN=1 "$REPO_ROOT/bin/$1" "${@:2}"
}
```

- [ ] **Step 2: Commit**

```bash
git add tests/helpers/load.bash
git commit -m "test: add shared bats load helper with clv_dry()"
```

### Task 3: Write a smoke test that every shim exists and is executable

**Files:**
- Create: `tests/00_smoke.bats`

- [ ] **Step 1: Write the test**

Create `/Users/aj/Projects/clv/tests/00_smoke.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/load'

@test "every top-level shim is executable" {
  for shim in "$REPO_ROOT"/bin/*; do
    [ -d "$shim" ] && continue
    [ -x "$shim" ] || { echo "not executable: $shim"; return 1; }
  done
}

@test "every shim has a shebang" {
  for shim in "$REPO_ROOT"/bin/*; do
    [ -d "$shim" ] && continue
    head -n1 "$shim" | grep -q '^#!/usr/bin/env bash' \
      || { echo "missing shebang: $shim"; return 1; }
  done
}

@test "init/clv exists and is sourced by every shim" {
  for shim in "$REPO_ROOT"/bin/*; do
    [ -d "$shim" ] && continue
    grep -q 'init/clv' "$shim" \
      || { echo "shim does not source init/clv: $shim"; return 1; }
  done
}
```

- [ ] **Step 2: Run the test, confirm green**

Run: `make test`
Expected: 3 tests pass.

- [ ] **Step 3: Commit**

```bash
git add tests/00_smoke.bats
git commit -m "test: add smoke tests asserting shim invariants"
```

---

## Phase 1 — Shared docker helper + dry-run seam

The 13 shims currently duplicate the `docker run` invocation. Centralize it. While we're at it, add `CLV_DRY_RUN` so we can assert what command *would* run without invoking docker.

### Task 4: Create `bin/inc/docker` with a `clv_docker_run` function and `CLV_DRY_RUN` support

**Files:**
- Create: `bin/inc/docker`
- Test: `tests/10_docker_helper.bats`

- [ ] **Step 1: Write the failing test**

Create `/Users/aj/Projects/clv/tests/10_docker_helper.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/load'

setup() {
  export CLV_DRY_RUN=1
}

@test "clv_docker_run prints docker command and exits 0 when CLV_DRY_RUN=1" {
  bash -c '
    CLVHOME="$HOME/.clv/test"
    IT="-i"
    SCRIPT_PATH="'"$REPO_ROOT/bin"'"
    PUBLISHED_PORTS=()
    source "$SCRIPT_PATH/inc/docker"
    clv_docker_run --entrypoint myentry myimage:1.0 arg1 arg2
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"docker run"* ]]
  [[ "$output" == *"--entrypoint myentry"* ]]
  [[ "$output" == *"myimage:1.0"* ]]
  [[ "$output" == *"arg1 arg2"* ]]
}

@test "clv_docker_run does not pass -a STDOUT (regression: stderr was lost)" {
  bash -c '
    CLVHOME="$HOME/.clv/test"
    IT="-i"
    SCRIPT_PATH="'"$REPO_ROOT/bin"'"
    PUBLISHED_PORTS=()
    source "$SCRIPT_PATH/inc/docker"
    clv_docker_run myimage:1.0
  '
  [[ "$output" != *"-a STDOUT"* ]]
}

@test "clv_docker_run honors CLV_DOCKER_ARGS pass-through" {
  bash -c '
    CLVHOME="$HOME/.clv/test"
    IT="-i"
    SCRIPT_PATH="'"$REPO_ROOT/bin"'"
    PUBLISHED_PORTS=()
    CLV_DOCKER_ARGS="--memory=2g --cpus=1.5"
    source "$SCRIPT_PATH/inc/docker"
    clv_docker_run myimage:1.0
  '
  [[ "$output" == *"--memory=2g"* ]]
  [[ "$output" == *"--cpus=1.5"* ]]
}
```

- [ ] **Step 2: Run, verify it fails**

Run: `make test`
Expected: 3 new tests fail with "no such file: bin/inc/docker".

- [ ] **Step 3: Implement `bin/inc/docker`**

Create `/Users/aj/Projects/clv/bin/inc/docker`:

```bash
#!/usr/bin/env bash
# Shared docker-run helper for all clv shims.
#
# Expects these to be set by the caller (the shim):
#   $CLVHOME            persistent home dir for this tool (~/.clv/<cmd>)
#   $IT                 -it or -i (set by init/clv)
#   $PUBLISHED_PORTS[]  optional, populated by inc/ports
#
# Optional environment input from the user:
#   CLV_DRY_RUN=1       print the docker command instead of running it
#   CLV_DOCKER_ARGS     extra flags inserted into `docker run` verbatim

clv_docker_run() {
  local extra_args=()
  if [[ -n "${CLV_DOCKER_ARGS:-}" ]]; then
    # word-split intentionally; users pass shell-style flags here
    # shellcheck disable=SC2206
    extra_args=( $CLV_DOCKER_ARGS )
  fi

  local cmd=(
    docker run "$IT" --rm
    "${PUBLISHED_PORTS[@]}"
    "${extra_args[@]}"
    -v "$CLVHOME:/root"
    -v "$PWD:/clv"
    -w "/clv"
    "$@"
  )

  if [[ "${CLV_DRY_RUN:-}" == "1" ]]; then
    printf '%s ' "${cmd[@]}"
    printf '\n'
    return 0
  fi

  "${cmd[@]}"
}
```

- [ ] **Step 4: Make it executable**

Run: `chmod +x /Users/aj/Projects/clv/bin/inc/docker`

- [ ] **Step 5: Run, verify pass**

Run: `make test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add bin/inc/docker tests/10_docker_helper.bats
git commit -m "feat(inc/docker): add shared clv_docker_run helper with CLV_DRY_RUN seam"
```

### Task 5: Migrate every existing shim to use `clv_docker_run`

Each shim drops its inline `docker run …` block and instead sources `inc/docker` and calls `clv_docker_run`. This commit centralizes the `-a STDOUT` removal (Phase 2 bug fix #1) since all shims now go through the helper.

**Files (modify each):**
- `bin/aws`, `bin/az`, `bin/gcloud`, `bin/git`, `bin/go`, `bin/helm`, `bin/ncu`, `bin/node`, `bin/npm`, `bin/prettier`, `bin/python`, `bin/python2`

**Test:** `tests/20_shim_dryrun.bats`

- [ ] **Step 1: Write the failing tests**

Create `/Users/aj/Projects/clv/tests/20_shim_dryrun.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/load'

setup() {
  export CLV_DRY_RUN=1
}

@test "aws shim emits expected docker command" {
  run clv_dry aws --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"docker run"* ]]
  [[ "$output" == *"amazon/aws-cli"* ]]
  [[ "$output" == *"--version"* ]]
  [[ "$output" != *"-a STDOUT"* ]]
}

@test "az shim emits expected docker command with az entrypoint" {
  run clv_dry az --version
  [[ "$output" == *"--entrypoint az"* ]]
  [[ "$output" == *"mcr.microsoft.com/azure-cli"* ]]
}

@test "gcloud shim emits expected docker command" {
  run clv_dry gcloud --version
  [[ "$output" == *"--entrypoint gcloud"* ]]
  [[ "$output" == *"google/cloud-sdk"* ]]
}

@test "git shim emits expected docker command" {
  run clv_dry git --version
  [[ "$output" == *"--entrypoint git"* ]]
  [[ "$output" == *"alpine/git"* ]]
}

@test "go shim publishes ports when PORTS is set" {
  PORTS="8080" run clv_dry go version
  [[ "$output" == *"--publish=8080:8080"* ]]
  [[ "$output" == *"--entrypoint go"* ]]
  [[ "$output" == *"golang"* ]]
}

@test "go shim defaults to host network when PORTS unset" {
  run clv_dry go version
  [[ "$output" == *"--network=host"* ]]
}

@test "helm shim double-mounts .config" {
  run clv_dry helm version
  [[ "$output" == *".config:/root/.config"* ]]
  [[ "$output" == *"--entrypoint helm"* ]]
  [[ "$output" == *"alpine/helm"* ]]
}

@test "node shim emits expected docker command" {
  run clv_dry node --version
  [[ "$output" == *"--entrypoint node"* ]]
  [[ "$output" == *"PATH=/root/bin:"* ]]
}

@test "npm shim mounts node home (not npm home)" {
  run clv_dry npm --version
  [[ "$output" == *"/.clv/node:/root"* ]]
  [[ "$output" == *"--entrypoint npm"* ]]
}

@test "ncu shim mounts node home" {
  run clv_dry ncu --version
  [[ "$output" == *"/.clv/node:/root"* ]]
  [[ "$output" == *"--entrypoint ncu"* ]]
}

@test "prettier shim mounts node home" {
  run clv_dry prettier --version
  [[ "$output" == *"/.clv/node:/root"* ]]
  [[ "$output" == *"--entrypoint prettier"* ]]
}

@test "python shim sets PYTHONUSERBASE" {
  run clv_dry python --version
  [[ "$output" == *"PYTHONUSERBASE=/root/base"* ]]
  [[ "$output" == *"--entrypoint python"* ]]
}
```

- [ ] **Step 2: Run, verify failures**

Run: `make test`
Expected: shim tests fail because shims still use inline `docker run` and don't honor `CLV_DRY_RUN`.

- [ ] **Step 3: Rewrite `bin/aws`**

Replace contents of `/Users/aj/Projects/clv/bin/aws`:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv amazon/aws-cli
source "$SCRIPT_PATH"/inc/docker
clv_docker_run "amazon/aws-cli:${CLV_TAG:-2}" "$@"
```

- [ ] **Step 4: Rewrite `bin/az`**

Replace contents of `/Users/aj/Projects/clv/bin/az`:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv mcr.microsoft.com/azure-cli
source "$SCRIPT_PATH"/inc/docker
clv_docker_run --entrypoint az "mcr.microsoft.com/azure-cli:${CLV_TAG:-latest}" "$@"
```

- [ ] **Step 5: Rewrite `bin/gcloud`**

Replace contents of `/Users/aj/Projects/clv/bin/gcloud`:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv google/cloud-sdk
source "$SCRIPT_PATH"/inc/docker
clv_docker_run --entrypoint gcloud "google/cloud-sdk:${CLV_TAG:-slim}" "$@"
```

- [ ] **Step 6: Rewrite `bin/git`** (full SSH/gitconfig forwarding lands in Task 17; this step keeps current behavior)

Replace contents of `/Users/aj/Projects/clv/bin/git`:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv alpine/git
source "$SCRIPT_PATH"/inc/docker
clv_docker_run --entrypoint git "alpine/git:${CLV_TAG:-latest}" "$@"
```

- [ ] **Step 7: Rewrite `bin/go`**

Replace contents of `/Users/aj/Projects/clv/bin/go`:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv go
source "$SCRIPT_PATH"/inc/ports
source "$SCRIPT_PATH"/inc/docker
clv_docker_run --entrypoint go "golang:${CLV_TAG:-1.23}" "$@"
```

- [ ] **Step 8: Rewrite `bin/helm`**

Replace contents of `/Users/aj/Projects/clv/bin/helm`:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv alpine/helm
source "$SCRIPT_PATH"/inc/docker
clv_docker_run \
    --entrypoint helm \
    -v "$CLVHOME/.config:/root/.config" \
    "alpine/helm:${CLV_TAG:-latest}" "$@"
```

- [ ] **Step 9: Rewrite `bin/ncu`**

Replace contents of `/Users/aj/Projects/clv/bin/ncu`:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv ncu
# ncu shares node's persistent home so globally-installed npm pkgs are visible
CLVHOME="$CLV/node"
source "$SCRIPT_PATH"/inc/docker
clv_docker_run \
    --entrypoint ncu \
    -e PATH="/root/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    "node:${CLV_TAG:-lts}" "$@"
```

- [ ] **Step 10: Rewrite `bin/node`**

Replace contents of `/Users/aj/Projects/clv/bin/node`:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv node
source "$SCRIPT_PATH"/inc/ports
source "$SCRIPT_PATH"/inc/docker
clv_docker_run \
    --entrypoint node \
    -e PATH="/root/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    "node:${CLV_TAG:-lts}" "$@"
```

- [ ] **Step 11: Rewrite `bin/npm`**

Replace contents of `/Users/aj/Projects/clv/bin/npm`:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv node
source "$SCRIPT_PATH"/inc/ports
# share node's home so global pkgs persist across `node` and `npm`
CLVHOME="$CLV/node"
source "$SCRIPT_PATH"/inc/docker
clv_docker_run \
    --entrypoint npm \
    -e PATH="/root/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    "node:${CLV_TAG:-lts}" "$@"
```

- [ ] **Step 12: Rewrite `bin/prettier`**

Replace contents of `/Users/aj/Projects/clv/bin/prettier`:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv prettier
CLVHOME="$CLV/node"
source "$SCRIPT_PATH"/inc/docker
clv_docker_run \
    --entrypoint prettier \
    -e PATH="/root/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    "node:${CLV_TAG:-lts}" "$@"
```

- [ ] **Step 13: Rewrite `bin/python`**

Replace contents of `/Users/aj/Projects/clv/bin/python`:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv python
source "$SCRIPT_PATH"/inc/ports
source "$SCRIPT_PATH"/inc/docker
clv_docker_run \
    --entrypoint python \
    -e PYTHONUSERBASE=/root/base \
    "python:${CLV_TAG:-3.13-slim}" "$@"
```

- [ ] **Step 14: Run, verify pass**

Run: `make test`
Expected: all dry-run shim tests pass.

- [ ] **Step 15: Commit**

```bash
git add bin/aws bin/az bin/gcloud bin/git bin/go bin/helm bin/ncu bin/node bin/npm bin/prettier bin/python tests/20_shim_dryrun.bats
git commit -m "refactor(bin): centralize docker invocation through inc/docker

All shims now compose docker run via clv_docker_run, which removes the
-a STDOUT flag (was silently dropping stderr) and adds CLV_DRY_RUN +
CLV_DOCKER_ARGS support. Image tags are now overridable via CLV_TAG."
```

---

## Phase 2 — Bug fixes

### Task 6: Fix `install` so re-running it overwrites stale shims

**Files:**
- Modify: `install`
- Test: `tests/30_install.bats`

- [ ] **Step 1: Write failing test**

Create `/Users/aj/Projects/clv/tests/30_install.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/load'

setup() {
  TMP="$(mktemp -d)"
  export PREFIX="$TMP/usr-local-bin"
  mkdir -p "$PREFIX"
  # we'll exercise install via a fake sudo + custom prefix
  cat > "$TMP/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
  chmod +x "$TMP/sudo"
  PATH="$TMP:$PATH"
  export CLV_INSTALL_PREFIX="$PREFIX"
}

teardown() {
  rm -rf "$TMP"
}

@test "install overwrites an existing shim with new content" {
  echo "old content" > "$PREFIX/aws"
  PATH="$TMP:$PATH" "$REPO_ROOT/install" aws
  run cat "$PREFIX/aws"
  [[ "$output" != "old content" ]]
  [[ "$output" == *"amazon/aws-cli"* ]]
}
```

- [ ] **Step 2: Run, verify failure**

Run: `make test`
Expected: install test fails — `install` ignores `CLV_INSTALL_PREFIX` and skips overwrite.

- [ ] **Step 3: Update `install` to honor a configurable prefix and always overwrite**

Replace contents of `/Users/aj/Projects/clv/install`:

```bash
#!/usr/bin/env bash
set -e
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"

PREFIX="${CLV_INSTALL_PREFIX:-/usr/local/bin}"

# Use sudo only if the prefix is not writable by the current user.
SUDO=""
if [[ ! -w "$PREFIX" ]]; then
  SUDO="sudo"
fi

install() {
  local INSTALL_TYPE="$1"; shift
  local CMD_LIST=("$@")

  # Wipe stale shared dirs so they always reflect this checkout.
  $SUDO rm -rf "$PREFIX/inc" "$PREFIX/init"
  $SUDO cp -r "$SCRIPT_PATH/bin/inc" "$PREFIX/"
  $SUDO cp -r "$SCRIPT_PATH/bin/init" "$PREFIX/"

  for CMD_PATH in "$SCRIPT_PATH"/bin/*; do
    [[ -d "$CMD_PATH" ]] && continue
    local CMD
    CMD="$(basename "$CMD_PATH")"
    case "$INSTALL_TYPE" in
      all)
        $SUDO cp "$CMD_PATH" "$PREFIX/$CMD"
        echo "clv installed $CMD successfully!"
        ;;
      skip)
        if [[ " ${CMD_LIST[*]} " =~ " ${CMD} " ]]; then
          echo "clv skipped $CMD"
        else
          $SUDO cp "$CMD_PATH" "$PREFIX/$CMD"
          echo "clv installed $CMD successfully!"
        fi
        ;;
      commands)
        if [[ " ${CMD_LIST[*]} " =~ " ${CMD} " ]]; then
          $SUDO cp "$CMD_PATH" "$PREFIX/$CMD"
          echo "clv installed $CMD successfully!"
        else
          echo "clv skipped $CMD"
        fi
        ;;
    esac
  done
  echo "clv has been installed successfully!"
}

if [[ $# -eq 0 ]]; then
  echo "installing all commands"
  install all
elif [[ "$1" == "-h" || "$1" == "--help" ]]; then
  cat <<EOF
USAGE: ./install [-s|--skip|-h|--help] [cmd1 cmd2 ...]

  ./install                       install all commands
  ./install go node               install go and node only
  ./install --skip git python     install all except git and python
  ./install -s git python         (short form)

ENV:
  CLV_INSTALL_PREFIX  install destination (default: /usr/local/bin)
EOF
elif [[ "$1" == "-s" || "$1" == "--skip" ]]; then
  shift
  echo "skipping $* command(s)"
  install skip "$@"
else
  echo "installing $* command(s)"
  install commands "$@"
fi
```

- [ ] **Step 4: Run, verify pass**

Run: `make test`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add install tests/30_install.bats
git commit -m "fix(install): always overwrite stale shims and add prefix override

Previously install kept stale shims because of an [[ ! -e ]] guard, so
edits never took effect on re-install. Also adds CLV_INSTALL_PREFIX so
the script can be tested without sudo, and skips sudo when the prefix
is already user-writable."
```

### Task 7: Fix `init/clv` to use fixed-string match against the init cache

**Files:**
- Modify: `bin/init/clv`
- Test: `tests/40_init_clv.bats`

- [ ] **Step 1: Write failing test**

Create `/Users/aj/Projects/clv/tests/40_init_clv.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/load'

setup() {
  HOME_BAK="$HOME"
  TMP="$(mktemp -d)"
  export HOME="$TMP"
}

teardown() {
  export HOME="$HOME_BAK"
  rm -rf "$TMP"
}

@test "init/clv treats image names with regex metachars as literals" {
  echo "amazon/aws-cli" > "$TMP/cache_seed"
  mkdir -p "$HOME/.clv"
  echo "amazon/aws-cli" > "$HOME/.clv/.init"

  # Pre-condition: a literal match should be hit.
  bash -c '
    set -e
    SCRIPT_PATH="'"$REPO_ROOT/bin"'"
    source "$SCRIPT_PATH/init/clv" amazon/aws-cli
    echo OK
  '
  [[ "$output" == *"OK"* ]]
  # Should NOT print "clv is initializing"
  [[ "$output" != *"initializing"* ]]
}
```

- [ ] **Step 2: Run, verify it currently passes by accident — but the underlying grep -q is wrong**

Run: `make test`. With the existing `grep -q`, the literal name happens to also match as regex. This test is a pin against that behavior; the real fix is in step 3 — switching to `grep -Fxq` which is *unambiguously* a literal match (defends future shim names that contain `.` or `+`).

- [ ] **Step 3: Update `bin/init/clv`**

Replace contents of `/Users/aj/Projects/clv/bin/init/clv`:

```bash
#!/usr/bin/env bash
# expects [IMAGE] [PARAMETERS...]
set -e
CLVCMD=$(basename "$0")
if [[ -t 0 ]]; then IT="-it"; else IT="-i"; fi

CLV="$HOME/.clv"
mkdir -p "$CLV"

CLVHOME="$CLV/$CLVCMD"
CLVINIT="$CLV/.init"
[[ -f "$CLVINIT" ]] || touch "$CLVINIT"

INIT_PARAMS="$*"
IMAGE="$1"; shift || true

if ! grep -Fxq -- "$INIT_PARAMS" "$CLVINIT"; then
  if [[ -f "$SCRIPT_PATH/init/$IMAGE" ]]; then
    echo "clv is initializing $INIT_PARAMS"
    # shellcheck disable=SC1090
    source "$SCRIPT_PATH/init/$IMAGE" "$@"
    echo "$INIT_PARAMS" >> "$CLVINIT"
  fi
fi
```

- [ ] **Step 4: Run, verify pass**

Run: `make test`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add bin/init/clv tests/40_init_clv.bats
git commit -m "fix(init/clv): match init cache lines as literal strings

grep -q treats the cache key as a regex, which would false-match or
break for image names containing regex metachars. Switch to grep -Fxq
for literal whole-line matching."
```

### Task 8: Fix `web/install` and `web/uninstall` to quote `$@` and use `main` instead of `master`

**Files:**
- Modify: `web/install`, `web/uninstall`

- [ ] **Step 1: Update `web/install`**

Replace contents of `/Users/aj/Projects/clv/web/install`:

```bash
#!/usr/bin/env bash
set -e
BRANCH="${CLV_BRANCH:-main}"
TS="$(date +%s)"
curl -fsSL -H 'Cache-Control: no-cache' -o clv.zip \
  "https://codeload.github.com/Clouve/clv/zip/${BRANCH}?${TS}"
unzip -q clv.zip
"./clv-${BRANCH}/install" "$@"
rm -rf "clv-${BRANCH}" clv.zip
```

- [ ] **Step 2: Update `web/uninstall`**

Replace contents of `/Users/aj/Projects/clv/web/uninstall`:

```bash
#!/usr/bin/env bash
set -e
BRANCH="${CLV_BRANCH:-main}"
TS="$(date +%s)"
curl -fsSL -H 'Cache-Control: no-cache' -o clv.zip \
  "https://codeload.github.com/Clouve/clv/zip/${BRANCH}?${TS}"
unzip -q clv.zip
"./clv-${BRANCH}/uninstall" "$@"
rm -rf "clv-${BRANCH}" clv.zip
```

- [ ] **Step 3: Confirm shellcheck is clean**

Run: `shellcheck web/install web/uninstall`
Expected: no warnings.

- [ ] **Step 4: Commit**

```bash
git add web/install web/uninstall
git commit -m "fix(web): quote \"\$@\", default to main branch, fail on curl error

- Quote \"\$@\" so installer args with spaces survive.
- Default branch is now main (override with CLV_BRANCH).
- curl uses -fsSL so HTTP errors abort instead of unzipping garbage."
```

### Task 9: Fix `bin/init/ncu` and `bin/init/prettier` to invoke npm via docker, not the host

**Files:**
- Modify: `bin/init/ncu`, `bin/init/prettier`

- [ ] **Step 1: Update `bin/init/ncu`**

Replace contents of `/Users/aj/Projects/clv/bin/init/ncu`:

```bash
#!/usr/bin/env bash
echo "clv is installing npm-check-updates"
mkdir -p "$CLV/node/lib" "$CLV/node/bin"
docker run --rm \
    -v "$CLV/node:/root" \
    "node:${CLV_TAG:-lts}" \
    npm config set prefix /root
docker run --rm \
    -v "$CLV/node:/root" \
    -e PATH="/root/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    "node:${CLV_TAG:-lts}" \
    npm i -g npm-check-updates
```

- [ ] **Step 2: Update `bin/init/prettier`**

Replace contents of `/Users/aj/Projects/clv/bin/init/prettier`:

```bash
#!/usr/bin/env bash
echo "clv is installing prettier"
mkdir -p "$CLV/node/lib" "$CLV/node/bin"
docker run --rm \
    -v "$CLV/node:/root" \
    "node:${CLV_TAG:-lts}" \
    npm config set prefix /root
docker run --rm \
    -v "$CLV/node:/root" \
    -e PATH="/root/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    "node:${CLV_TAG:-lts}" \
    npm i -g prettier
```

- [ ] **Step 3: Commit**

```bash
git add bin/init/ncu bin/init/prettier
git commit -m "fix(init): install global npm packages via docker, not host npm

Previously ncu/prettier init ran bare \`npm i -g\`, which depended on
PATH order during install (the npm shim might not yet be copied) or on
a host npm being present. Run npm directly inside the node image."
```

### Task 10: Drop the unused `[[ ! -d "/usr/local/bin/$CMD" ]]` guard in `uninstall` and stop deleting `~/.clv/.init`

The current `uninstall` removes `~/.clv/.init` on a full uninstall, which throws away every per-image init signal — so a re-install re-runs every init even though the persistent `~/.clv/<cmd>/` dirs are still there. Keep the init cache, only delete it as part of an explicit `--purge`.

**Files:**
- Modify: `uninstall`

- [ ] **Step 1: Replace contents of `/Users/aj/Projects/clv/uninstall`**

```bash
#!/usr/bin/env bash
set -e
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"

PREFIX="${CLV_INSTALL_PREFIX:-/usr/local/bin}"
SUDO=""
[[ -w "$PREFIX" ]] || SUDO="sudo"

uninstall_commands() {
  for CMD_PATH in "$@"; do
    local CMD
    CMD="$(basename "$CMD_PATH")"
    if [[ -f "$PREFIX/$CMD" ]]; then
      $SUDO rm "$PREFIX/$CMD"
      echo "clv uninstalled $CMD successfully!"
    fi
  done
}

PURGE=0
if [[ "${1:-}" == "--purge" ]]; then
  PURGE=1; shift
fi

if [[ $# -eq 0 ]]; then
  uninstall_commands "$SCRIPT_PATH"/bin/*
  $SUDO rm -rf "$PREFIX/inc" "$PREFIX/init"
  if [[ $PURGE -eq 1 && -d "$HOME/.clv" ]]; then
    rm -rf "$HOME/.clv"
    echo "clv purged ~/.clv/"
  fi
  echo "clv has been uninstalled successfully!"
elif [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<EOF
USAGE: ./uninstall [--purge] [cmd1 cmd2 ...]

  ./uninstall              uninstall all commands
  ./uninstall git python   uninstall only git and python
  ./uninstall --purge      uninstall all and remove ~/.clv/

ENV:
  CLV_INSTALL_PREFIX  uninstall source (default: /usr/local/bin)
EOF
else
  uninstall_commands "$@"
fi
echo "----------------------------------------------------------"
```

- [ ] **Step 2: Commit**

```bash
git add uninstall
git commit -m "fix(uninstall): preserve ~/.clv/.init unless --purge, support prefix override"
```

### Task 11: Pin a regression test for the `-a STDOUT` removal at the integration boundary

**Files:**
- Test: `tests/50_no_a_stdout.bats`

- [ ] **Step 1: Add the test**

Create `/Users/aj/Projects/clv/tests/50_no_a_stdout.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/load'

@test "no shim contains the literal string '-a STDOUT'" {
  ! grep -rn -- "-a STDOUT" "$REPO_ROOT/bin/" \
    || { echo "found stale -a STDOUT — stderr would be dropped"; return 1; }
}
```

- [ ] **Step 2: Run, verify pass**

Run: `make test`

- [ ] **Step 3: Commit**

```bash
git add tests/50_no_a_stdout.bats
git commit -m "test: regression-pin removal of -a STDOUT from all shims"
```

---

## Phase 3 — Modernization

### Task 12: Remove `python2`

Python 2 has been EOL since 2020-01-01. Drop the shim and its init.

**Files:**
- Delete: `bin/python2`, `bin/init/python2`
- Modify: `README.md`, `CLAUDE.md`

- [ ] **Step 1: Delete the files**

```bash
rm /Users/aj/Projects/clv/bin/python2
rm /Users/aj/Projects/clv/bin/init/python2
```

- [ ] **Step 2: Update README — remove the `python2` bullet** (full README rewrite is Task 35; this just keeps it consistent for now)

Edit `/Users/aj/Projects/clv/README.md`, remove the line:

```
- python2 (https://docs.python.org/2/)
```

- [ ] **Step 3: Update CLAUDE.md — drop python2 from the wrap list**

Edit `/Users/aj/Projects/clv/CLAUDE.md`, change the first paragraph's command list from:

```
aws, az, gcloud, git, go, helm, ncu, node, npm, prettier, python, python2
```

to:

```
aws, az, gcloud, git, go, helm, ncu, node, npm, prettier, python
```

- [ ] **Step 4: Commit**

```bash
git rm bin/python2 bin/init/python2
git add README.md CLAUDE.md
git commit -m "feat!: remove python2 shim (Python 2 EOL since 2020-01-01)

BREAKING CHANGE: ./install no longer ships a python2 command. Users
who still need Python 2 can pin via CLV_TAG=2.7 on a custom shim, but
upstream python:2.7 is unmaintained."
```

### Task 13: Pin all default image tags + document `CLV_TAG`

This is largely already done in Task 5's rewrites — every shim already does `${CLV_TAG:-<default>}`. This task verifies coverage and documents it.

**Files:**
- Test: `tests/60_image_pinning.bats`

- [ ] **Step 1: Write the test**

Create `/Users/aj/Projects/clv/tests/60_image_pinning.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/load'

@test "every shim references CLV_TAG with a default" {
  for shim in "$REPO_ROOT"/bin/*; do
    [ -d "$shim" ] && continue
    if ! grep -q 'CLV_TAG:-' "$shim"; then
      echo "shim does not honor CLV_TAG: $shim"
      return 1
    fi
  done
}

@test "no shim references a bare image name without a tag" {
  for shim in "$REPO_ROOT"/bin/*; do
    [ -d "$shim" ] && continue
    # extract clv_docker_run image arg lines
    if grep -E 'clv_docker_run.*"[a-z./-]+"\s*"\$@"' "$shim" >/dev/null; then
      echo "shim has untagged image: $shim"
      return 1
    fi
  done
}
```

- [ ] **Step 2: Run, verify pass**

Run: `make test`

- [ ] **Step 3: Commit**

```bash
git add tests/60_image_pinning.bats
git commit -m "test: enforce CLV_TAG default on every shim"
```

### Task 14: Add `CLV_DOCKER_ARGS` documentation in README + man-style help in shims

This adds nothing functional (the env var is already plumbed in Task 4) but exposes it.

**Files:**
- Modify: `bin/inc/docker` (add a comment block at top — already present from Task 4)

- [ ] **Step 1: Verify Task 4's comment block**

Confirm `/Users/aj/Projects/clv/bin/inc/docker` already documents both `CLV_DRY_RUN` and `CLV_DOCKER_ARGS` in its header comment. If yes, no code change needed.

- [ ] **Step 2: Skip commit if no diff**

This task is a no-op unless the previous step found gaps. Move on to Task 15.

### Task 15: Switch `gcloud` default to `:slim`

Already handled in Task 5 (`google/cloud-sdk:${CLV_TAG:-slim}`). Verify with a test.

**Files:**
- Test: `tests/20_shim_dryrun.bats` (extend)

- [ ] **Step 1: Add a focused test**

Append to `/Users/aj/Projects/clv/tests/20_shim_dryrun.bats`:

```bash
@test "gcloud defaults to the slim image variant" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/gcloud" --version
  [[ "$output" == *"google/cloud-sdk:slim"* ]]
}

@test "CLV_TAG override changes the gcloud image tag" {
  CLV_TAG=alpine CLV_DRY_RUN=1 run "$REPO_ROOT/bin/gcloud" --version
  [[ "$output" == *"google/cloud-sdk:alpine"* ]]
}
```

- [ ] **Step 2: Run, verify pass**

Run: `make test`

- [ ] **Step 3: Commit**

```bash
git add tests/20_shim_dryrun.bats
git commit -m "test: pin gcloud default to slim variant and CLV_TAG override"
```

---

## Phase 4 — Shim feature improvements

### Task 16: Add `inc/ssh` for SSH agent + .ssh + .gitconfig forwarding

**Files:**
- Create: `bin/inc/ssh`

- [ ] **Step 1: Create the helper**

Create `/Users/aj/Projects/clv/bin/inc/ssh`:

```bash
#!/usr/bin/env bash
# Populates SSH_MOUNTS[] with -v / -e flags so the shim can forward the
# user's SSH agent, ~/.ssh, and ~/.gitconfig into the container.
SSH_MOUNTS=()

if [[ -n "${SSH_AUTH_SOCK:-}" && -S "$SSH_AUTH_SOCK" ]]; then
  SSH_MOUNTS+=(
    -v "$SSH_AUTH_SOCK:/ssh-agent"
    -e "SSH_AUTH_SOCK=/ssh-agent"
  )
fi
if [[ -d "$HOME/.ssh" ]]; then
  SSH_MOUNTS+=( -v "$HOME/.ssh:/root/.ssh:ro" )
fi
if [[ -f "$HOME/.gitconfig" ]]; then
  SSH_MOUNTS+=( -v "$HOME/.gitconfig:/root/.gitconfig:ro" )
fi
```

- [ ] **Step 2: Commit**

```bash
git add bin/inc/ssh
git commit -m "feat(inc/ssh): add SSH agent + .ssh + .gitconfig forwarding helper"
```

### Task 17: Wire SSH forwarding into the `git` shim

**Files:**
- Modify: `bin/git`
- Test: `tests/70_git_ssh.bats`

- [ ] **Step 1: Write failing test**

Create `/Users/aj/Projects/clv/tests/70_git_ssh.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/load'

setup() {
  export CLV_DRY_RUN=1
  TMP="$(mktemp -d)"
  HOME_BAK="$HOME"
  export HOME="$TMP"
  mkdir -p "$HOME/.ssh"
  echo "[user]" > "$HOME/.gitconfig"
  export SSH_AUTH_SOCK="$TMP/agent.sock"
  # bats cannot create a real socket easily; simulate one
  python3 -c "import socket,os,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])" "$SSH_AUTH_SOCK"
}

teardown() {
  export HOME="$HOME_BAK"
  rm -rf "$TMP"
}

@test "git shim forwards SSH agent socket" {
  run clv_dry git --version
  [[ "$output" == *"$SSH_AUTH_SOCK:/ssh-agent"* ]]
  [[ "$output" == *"SSH_AUTH_SOCK=/ssh-agent"* ]]
}

@test "git shim mounts ~/.ssh and ~/.gitconfig read-only" {
  run clv_dry git --version
  [[ "$output" == *"$HOME/.ssh:/root/.ssh:ro"* ]]
  [[ "$output" == *"$HOME/.gitconfig:/root/.gitconfig:ro"* ]]
}
```

- [ ] **Step 2: Run, verify failure**

Run: `make test`

- [ ] **Step 3: Update `bin/git`**

Replace contents of `/Users/aj/Projects/clv/bin/git`:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv alpine/git
source "$SCRIPT_PATH"/inc/ssh
source "$SCRIPT_PATH"/inc/docker
clv_docker_run \
    --entrypoint git \
    "${SSH_MOUNTS[@]}" \
    "alpine/git:${CLV_TAG:-latest}" "$@"
```

- [ ] **Step 4: Run, verify pass**

Run: `make test`

- [ ] **Step 5: Commit**

```bash
git add bin/git tests/70_git_ssh.bats
git commit -m "feat(git): forward SSH agent, ~/.ssh, ~/.gitconfig into container

Without this, \`clv git clone git@github.com:…\` always fails because
the container has no credentials. Mounts are read-only, agent socket
is forwarded only when SSH_AUTH_SOCK is set."
```

### Task 18: Improve `inc/ports` to accept already-formatted mappings

Currently `PORTS="8080"` becomes `--publish=8080:8080`. Allow `PORTS="127.0.0.1:8080:8080 5432"` so power users can bind to specific interfaces.

**Files:**
- Modify: `bin/inc/ports`
- Test: `tests/80_ports.bats`

- [ ] **Step 1: Write failing test**

Create `/Users/aj/Projects/clv/tests/80_ports.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/load'

@test "PORTS=8080 expands to 8080:8080" {
  bash -c '
    PORTS="8080"
    source "'"$REPO_ROOT/bin/inc/ports"'"
    printf "%s\n" "${PUBLISHED_PORTS[@]}"
  '
  [[ "$output" == *"--publish=8080:8080"* ]]
}

@test "PORTS=127.0.0.1:8080:8080 passes through unchanged" {
  bash -c '
    PORTS="127.0.0.1:8080:8080"
    source "'"$REPO_ROOT/bin/inc/ports"'"
    printf "%s\n" "${PUBLISHED_PORTS[@]}"
  '
  [[ "$output" == *"--publish=127.0.0.1:8080:8080"* ]]
}

@test "PORTS=8080:9090 supports host:container mapping" {
  bash -c '
    PORTS="8080:9090"
    source "'"$REPO_ROOT/bin/inc/ports"'"
    printf "%s\n" "${PUBLISHED_PORTS[@]}"
  '
  [[ "$output" == *"--publish=8080:9090"* ]]
}

@test "PORTS unset defaults to host networking" {
  bash -c '
    unset PORTS
    source "'"$REPO_ROOT/bin/inc/ports"'"
    printf "%s\n" "${PUBLISHED_PORTS[@]}"
  '
  [[ "$output" == *"--network=host"* ]]
}
```

- [ ] **Step 2: Run, verify failure**

Run: `make test`

- [ ] **Step 3: Update `bin/inc/ports`**

Replace contents of `/Users/aj/Projects/clv/bin/inc/ports`:

```bash
#!/usr/bin/env bash
# PORTS is space-separated. Each token may be:
#   8080                       → --publish=8080:8080
#   8080:9090                  → --publish=8080:9090
#   127.0.0.1:8080:8080        → --publish=127.0.0.1:8080:8080
# If unset/empty, falls back to --network=host (Linux only — on Docker
# Desktop for Mac/Windows host networking is bridge by default).
PUBLISHED_PORTS=()
for PORT in $PORTS; do
  if [[ "$PORT" == *:* ]]; then
    PUBLISHED_PORTS+=( "--publish=$PORT" )
  else
    PUBLISHED_PORTS+=( "--publish=$PORT:$PORT" )
  fi
done
if [[ ${#PUBLISHED_PORTS[@]} -eq 0 ]]; then
  PUBLISHED_PORTS+=( "--network=host" )
fi
```

- [ ] **Step 4: Run, verify pass**

Run: `make test`

- [ ] **Step 5: Commit**

```bash
git add bin/inc/ports tests/80_ports.bats
git commit -m "feat(inc/ports): accept host:container and iface:host:container syntax"
```

### Task 19: Add `inc/user` for opt-in UID/GID mapping (Linux file ownership fix)

On Linux, files written inside the container land as root-owned on the host. This helper lets a shim opt in to running as the invoking user. Default off so we don't break Mac users (where Docker Desktop already maps UIDs).

**Files:**
- Create: `bin/inc/user`

- [ ] **Step 1: Create the helper**

Create `/Users/aj/Projects/clv/bin/inc/user`:

```bash
#!/usr/bin/env bash
# Opt-in UID/GID mapping. Set CLV_MAP_USER=1 to run the container as
# the host user. Disabled by default because some images (e.g.
# alpine/helm) hard-code paths under /root that are unwritable when
# running as a non-root UID.
USER_MOUNTS=()
if [[ "${CLV_MAP_USER:-0}" == "1" ]]; then
  USER_MOUNTS=( --user "$(id -u):$(id -g)" )
fi
```

- [ ] **Step 2: Wire into `clv_docker_run`**

Edit `/Users/aj/Projects/clv/bin/inc/docker` — add `"${USER_MOUNTS[@]}"` to the `cmd` array, just after `extra_args`:

```bash
  local cmd=(
    docker run "$IT" --rm
    "${PUBLISHED_PORTS[@]}"
    "${extra_args[@]}"
    "${USER_MOUNTS[@]}"
    -v "$CLVHOME:/root"
    -v "$PWD:/clv"
    -w "/clv"
    "$@"
  )
```

- [ ] **Step 3: Have every shim source `inc/user`**

Add `source "$SCRIPT_PATH"/inc/user` after `source "$SCRIPT_PATH"/init/clv …` in every shim. Apply to: aws, az, gcloud, git, go, helm, ncu, node, npm, prettier, python (and all new shims as they're written).

- [ ] **Step 4: Test**

Append to `/Users/aj/Projects/clv/tests/20_shim_dryrun.bats`:

```bash
@test "CLV_MAP_USER=1 adds --user flag" {
  CLV_MAP_USER=1 CLV_DRY_RUN=1 run "$REPO_ROOT/bin/aws" --version
  [[ "$output" == *"--user "* ]]
}

@test "CLV_MAP_USER unset omits --user flag" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/aws" --version
  [[ "$output" != *"--user "* ]]
}
```

Run: `make test`. Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add bin/inc/user bin/inc/docker bin/aws bin/az bin/gcloud bin/git bin/go bin/helm bin/ncu bin/node bin/npm bin/prettier bin/python tests/20_shim_dryrun.bats
git commit -m "feat(inc/user): opt-in UID/GID mapping via CLV_MAP_USER

Fixes the Linux 'files in ~/.clv/<cmd>/ are root-owned' problem.
Off by default to preserve macOS Docker Desktop semantics."
```

---

## Phase 5 — Meta `clv` command

### Task 20: Add a `clv` meta-command

Subcommands:
- `clv version` — print clv version (read from a `VERSION` file)
- `clv list` — list installed shims
- `clv install <shim>...` — fetch `web/install` from GitHub and install the named shims (delegates so we don't have to ship the whole `bin/` tree to `$PREFIX`)
- `clv uninstall <shim>...` — fetch `web/uninstall` and remove the named shims; `clv uninstall --purge` removes all + `~/.clv/`
- `clv update` — `docker pull` every image referenced by installed shims
- `clv prune` — remove dangling clv images and offer to delete `~/.clv/<cmd>/` for uninstalled shims

**Files:**
- Create: `bin/clv`, `VERSION`
- Test: `tests/90_meta_clv.bats`

- [ ] **Step 1: Create `VERSION`**

Create `/Users/aj/Projects/clv/VERSION` with contents:

```
2.0.0
```

- [ ] **Step 2: Write the failing test**

Create `/Users/aj/Projects/clv/tests/90_meta_clv.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/load'

@test "clv version prints the version from VERSION file" {
  run "$REPO_ROOT/bin/clv" version
  [ "$status" -eq 0 ]
  [[ "$output" == "2.0.0" ]]
}

@test "clv --help lists subcommands" {
  run "$REPO_ROOT/bin/clv" --help
  [[ "$output" == *"version"* ]]
  [[ "$output" == *"list"* ]]
  [[ "$output" == *"install"* ]]
  [[ "$output" == *"uninstall"* ]]
  [[ "$output" == *"update"* ]]
  [[ "$output" == *"prune"* ]]
}

@test "clv list prints installed shim names from PREFIX" {
  TMP="$(mktemp -d)"
  trap "rm -rf $TMP" EXIT
  mkdir -p "$TMP"
  cp "$REPO_ROOT/bin/aws" "$TMP/aws"
  cp "$REPO_ROOT/bin/git" "$TMP/git"
  CLV_INSTALL_PREFIX="$TMP" run "$REPO_ROOT/bin/clv" list
  [[ "$output" == *"aws"* ]]
  [[ "$output" == *"git"* ]]
}

@test "clv install with no args errors out" {
  run "$REPO_ROOT/bin/clv" install
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* || "$output" == *"shim"* ]]
}

@test "clv uninstall with no args errors out" {
  run "$REPO_ROOT/bin/clv" uninstall
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* || "$output" == *"shim"* ]]
}
```

- [ ] **Step 3: Run, verify failure**

Run: `make test`

- [ ] **Step 4: Implement `bin/clv`**

Create `/Users/aj/Projects/clv/bin/clv`:

```bash
#!/usr/bin/env bash
set -e
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"

PREFIX="${CLV_INSTALL_PREFIX:-/usr/local/bin}"
VERSION_FILE="$SCRIPT_PATH/../VERSION"
[[ -f "$VERSION_FILE" ]] || VERSION_FILE="$SCRIPT_PATH/VERSION"

CLV_SHIMS=(aws az clv gcloud git go helm ncu node npm prettier python \
           terraform kubectl yarn pnpm bun deno cargo psql mysql redis-cli make)

clv_list() {
  for s in "${CLV_SHIMS[@]}"; do
    [[ -f "$PREFIX/$s" ]] && echo "$s"
  done
}

clv_install() {
  if [[ $# -eq 0 ]]; then
    echo "usage: clv install <shim> [shim2 ...]" >&2
    echo "       clv install --all" >&2
    return 2
  fi
  local branch="${CLV_BRANCH:-main}"
  local args=()
  if [[ "$1" == "--all" ]]; then
    : # no args = install all in web/install
  else
    args=( "$@" )
  fi
  curl -fsSL "https://raw.githubusercontent.com/Clouve/clv/${branch}/web/install" \
    | bash -s -- "${args[@]}"
}

clv_uninstall() {
  if [[ $# -eq 0 ]]; then
    echo "usage: clv uninstall <shim> [shim2 ...]" >&2
    echo "       clv uninstall --all" >&2
    echo "       clv uninstall --purge" >&2
    return 2
  fi
  local branch="${CLV_BRANCH:-main}"
  local args=()
  if [[ "$1" == "--all" ]]; then
    : # no args = uninstall all
  elif [[ "$1" == "--purge" ]]; then
    args=( "--purge" )
  else
    args=( "$@" )
  fi
  curl -fsSL "https://raw.githubusercontent.com/Clouve/clv/${branch}/web/uninstall" \
    | bash -s -- "${args[@]}"
}

# Extract image:tag tokens from an installed shim by dry-running it.
shim_image() {
  local shim="$1"
  CLV_DRY_RUN=1 "$shim" --version 2>/dev/null \
    | tr ' ' '\n' \
    | grep -E '^[a-z0-9./_-]+:[a-zA-Z0-9._-]+$' \
    | grep -v '^/' \
    | head -n1 || true
}

clv_update() {
  for s in $(clv_list); do
    local img
    img="$(shim_image "$PREFIX/$s")"
    if [[ -n "$img" ]]; then
      echo "==> docker pull $img  (used by $s)"
      docker pull "$img" || true
    fi
  done
}

clv_prune() {
  echo "==> docker image prune for clv-tracked images"
  for s in $(clv_list); do
    local img
    img="$(shim_image "$PREFIX/$s")"
    [[ -n "$img" ]] && docker image prune -f --filter "label=org.clouve.clv=$img" || true
  done
  echo "==> ~/.clv/<cmd>/ dirs that no longer have an installed shim:"
  if [[ -d "$HOME/.clv" ]]; then
    for d in "$HOME/.clv"/*/; do
      [[ -d "$d" ]] || continue
      local name
      name="$(basename "$d")"
      if [[ ! -f "$PREFIX/$name" ]]; then
        echo "  $d"
      fi
    done
    echo "(remove manually with: rm -rf <path>)"
  fi
}

clv_version() {
  if [[ -f "$VERSION_FILE" ]]; then
    cat "$VERSION_FILE"
  else
    echo "unknown"
  fi
}

case "${1:-}" in
  version|--version|-v) clv_version ;;
  list)                  clv_list ;;
  install)               shift; clv_install "$@" ;;
  uninstall)             shift; clv_uninstall "$@" ;;
  update)                clv_update ;;
  prune)                 clv_prune ;;
  ""|-h|--help|help)
    cat <<EOF
clv — docker-shim manager

USAGE: clv <subcommand>

  version              print clv version
  list                 list installed shims
  install <shim>...    install one or more shims (or --all)
  uninstall <shim>...  uninstall one or more shims (or --all, --purge)
  update               docker pull every image used by installed shims
  prune                prune unused clv images and report stale ~/.clv dirs
  help                 show this message

ENV:
  CLV_INSTALL_PREFIX   install prefix (default: /usr/local/bin)
  CLV_BRANCH           branch for install/uninstall fetch (default: main)
EOF
    ;;
  *)
    echo "clv: unknown subcommand '$1' (try: clv help)" >&2
    exit 2
    ;;
esac
```

- [ ] **Step 5: Make it executable**

Run: `chmod +x /Users/aj/Projects/clv/bin/clv`

- [ ] **Step 6: Run, verify pass**

Run: `make test`

- [ ] **Step 7: Commit**

```bash
git add bin/clv VERSION tests/90_meta_clv.bats
git commit -m "feat(clv): add meta command with version/list/install/uninstall/update/prune"
```

---

## Phase 6 — New shims

Each new-shim task follows the same pattern: write a dry-run test, write the shim, verify. The default `CLV_TAG` for each is the project's current stable. Pick the docker image from the project's official registry.

### Task 21: Add `terraform` shim

**Files:** `bin/terraform`, `tests/100_terraform.bats`

- [ ] **Step 1: Test**

Create `/Users/aj/Projects/clv/tests/100_terraform.bats`:

```bash
#!/usr/bin/env bats
load 'helpers/load'

@test "terraform shim emits expected docker command" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/terraform" --version
  [[ "$output" == *"hashicorp/terraform"* ]]
  [[ "$output" == *"--entrypoint terraform"* ]]
}
```

- [ ] **Step 2: Implementation**

Create `/Users/aj/Projects/clv/bin/terraform`:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv hashicorp/terraform
source "$SCRIPT_PATH"/inc/user
source "$SCRIPT_PATH"/inc/docker
clv_docker_run --entrypoint terraform "hashicorp/terraform:${CLV_TAG:-latest}" "$@"
```

- [ ] **Step 3: chmod +x and commit**

```bash
chmod +x /Users/aj/Projects/clv/bin/terraform
git add bin/terraform tests/100_terraform.bats
git commit -m "feat(terraform): add terraform shim"
```

### Task 22: Add `kubectl` shim

**Files:** `bin/kubectl`, `bin/init/bitnami` (creates `~/.clv/kubectl/.kube/`), `tests/101_kubectl.bats`

- [ ] **Step 1: Test**

Create `/Users/aj/Projects/clv/tests/101_kubectl.bats`:

```bash
#!/usr/bin/env bats
load 'helpers/load'

@test "kubectl shim mounts kube config dir" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/kubectl" version --client
  [[ "$output" == *"bitnami/kubectl"* ]]
  [[ "$output" == *"--entrypoint kubectl"* ]]
}
```

- [ ] **Step 2: Implementation**

Create `/Users/aj/Projects/clv/bin/kubectl`:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv bitnami/kubectl
source "$SCRIPT_PATH"/inc/user
source "$SCRIPT_PATH"/inc/docker
clv_docker_run --entrypoint kubectl \
    -v "$CLVHOME/.kube:/.kube" \
    -e KUBECONFIG=/.kube/config \
    "bitnami/kubectl:${CLV_TAG:-latest}" "$@"
```

Create `/Users/aj/Projects/clv/bin/init/bitnami`:

```bash
#!/usr/bin/env bash
mkdir -p "$CLVHOME/.kube"
```

- [ ] **Step 3: chmod, commit**

```bash
chmod +x /Users/aj/Projects/clv/bin/kubectl /Users/aj/Projects/clv/bin/init/bitnami
git add bin/kubectl bin/init/bitnami tests/101_kubectl.bats
git commit -m "feat(kubectl): add kubectl shim with .kube dir persistence"
```

### Task 23: Add `yarn` shim

**Files:** `bin/yarn`, `tests/102_yarn.bats`

- [ ] **Step 1: Test**

Create `/Users/aj/Projects/clv/tests/102_yarn.bats`:

```bash
#!/usr/bin/env bats
load 'helpers/load'

@test "yarn shim shares node home and uses node image" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/yarn" --version
  [[ "$output" == *"--entrypoint yarn"* ]]
  [[ "$output" == *"/.clv/node:/root"* ]]
}
```

- [ ] **Step 2: Implementation**

Create `/Users/aj/Projects/clv/bin/yarn`:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv node
source "$SCRIPT_PATH"/inc/ports
source "$SCRIPT_PATH"/inc/user
CLVHOME="$CLV/node"
source "$SCRIPT_PATH"/inc/docker
clv_docker_run \
    --entrypoint yarn \
    -e PATH="/root/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    "node:${CLV_TAG:-lts}" "$@"
```

- [ ] **Step 3: chmod, commit**

```bash
chmod +x /Users/aj/Projects/clv/bin/yarn
git add bin/yarn tests/102_yarn.bats
git commit -m "feat(yarn): add yarn shim sharing node persistent home"
```

### Task 24: Add `pnpm` shim

**Files:** `bin/pnpm`, `bin/init/pnpm`, `tests/103_pnpm.bats`

- [ ] **Step 1: Test**

Create `/Users/aj/Projects/clv/tests/103_pnpm.bats`:

```bash
#!/usr/bin/env bats
load 'helpers/load'

@test "pnpm shim emits expected docker command" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/pnpm" --version
  [[ "$output" == *"--entrypoint pnpm"* ]]
}
```

- [ ] **Step 2: Implementation**

Create `/Users/aj/Projects/clv/bin/pnpm`:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv pnpm
source "$SCRIPT_PATH"/inc/ports
source "$SCRIPT_PATH"/inc/user
CLVHOME="$CLV/node"
source "$SCRIPT_PATH"/inc/docker
clv_docker_run \
    --entrypoint pnpm \
    -e PATH="/root/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    "node:${CLV_TAG:-lts}" "$@"
```

Create `/Users/aj/Projects/clv/bin/init/pnpm`:

```bash
#!/usr/bin/env bash
echo "clv is installing pnpm"
mkdir -p "$CLV/node/bin" "$CLV/node/lib"
docker run --rm \
    -v "$CLV/node:/root" \
    "node:${CLV_TAG:-lts}" \
    npm config set prefix /root
docker run --rm \
    -v "$CLV/node:/root" \
    "node:${CLV_TAG:-lts}" \
    npm i -g pnpm
```

- [ ] **Step 3: chmod, commit**

```bash
chmod +x /Users/aj/Projects/clv/bin/pnpm /Users/aj/Projects/clv/bin/init/pnpm
git add bin/pnpm bin/init/pnpm tests/103_pnpm.bats
git commit -m "feat(pnpm): add pnpm shim"
```

### Task 25: Add `bun` shim

**Files:** `bin/bun`, `tests/104_bun.bats`

- [ ] **Step 1: Test**

Create `/Users/aj/Projects/clv/tests/104_bun.bats`:

```bash
#!/usr/bin/env bats
load 'helpers/load'

@test "bun shim emits expected docker command" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/bun" --version
  [[ "$output" == *"oven/bun"* ]]
  [[ "$output" == *"--entrypoint bun"* ]]
}
```

- [ ] **Step 2: Implementation**

Create `/Users/aj/Projects/clv/bin/bun`:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv oven/bun
source "$SCRIPT_PATH"/inc/ports
source "$SCRIPT_PATH"/inc/user
source "$SCRIPT_PATH"/inc/docker
clv_docker_run --entrypoint bun "oven/bun:${CLV_TAG:-latest}" "$@"
```

- [ ] **Step 3: chmod, commit**

```bash
chmod +x /Users/aj/Projects/clv/bin/bun
git add bin/bun tests/104_bun.bats
git commit -m "feat(bun): add bun shim"
```

### Task 26: Add `deno` shim

**Files:** `bin/deno`, `tests/105_deno.bats`

- [ ] **Step 1: Test**

Create `/Users/aj/Projects/clv/tests/105_deno.bats`:

```bash
#!/usr/bin/env bats
load 'helpers/load'

@test "deno shim emits expected docker command" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/deno" --version
  [[ "$output" == *"denoland/deno"* ]]
  [[ "$output" == *"--entrypoint deno"* ]]
}
```

- [ ] **Step 2: Implementation**

Create `/Users/aj/Projects/clv/bin/deno`:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv denoland/deno
source "$SCRIPT_PATH"/inc/ports
source "$SCRIPT_PATH"/inc/user
source "$SCRIPT_PATH"/inc/docker
clv_docker_run --entrypoint deno "denoland/deno:${CLV_TAG:-latest}" "$@"
```

- [ ] **Step 3: chmod, commit**

```bash
chmod +x /Users/aj/Projects/clv/bin/deno
git add bin/deno tests/105_deno.bats
git commit -m "feat(deno): add deno shim"
```

### Task 27: Add `cargo` (Rust) shim

**Files:** `bin/cargo`, `tests/106_cargo.bats`

- [ ] **Step 1: Test**

Create `/Users/aj/Projects/clv/tests/106_cargo.bats`:

```bash
#!/usr/bin/env bats
load 'helpers/load'

@test "cargo shim emits expected docker command" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/cargo" --version
  [[ "$output" == *"rust"* ]]
  [[ "$output" == *"--entrypoint cargo"* ]]
}
```

- [ ] **Step 2: Implementation**

Create `/Users/aj/Projects/clv/bin/cargo`:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv rust
source "$SCRIPT_PATH"/inc/ports
source "$SCRIPT_PATH"/inc/user
source "$SCRIPT_PATH"/inc/docker
clv_docker_run --entrypoint cargo "rust:${CLV_TAG:-latest}" "$@"
```

- [ ] **Step 3: chmod, commit**

```bash
chmod +x /Users/aj/Projects/clv/bin/cargo
git add bin/cargo tests/106_cargo.bats
git commit -m "feat(cargo): add cargo shim using upstream rust image"
```

### Task 28: Add `psql` shim

**Files:** `bin/psql`, `tests/107_psql.bats`

- [ ] **Step 1: Test**

Create `/Users/aj/Projects/clv/tests/107_psql.bats`:

```bash
#!/usr/bin/env bats
load 'helpers/load'

@test "psql shim emits expected docker command" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/psql" --version
  [[ "$output" == *"postgres"* ]]
  [[ "$output" == *"--entrypoint psql"* ]]
}
```

- [ ] **Step 2: Implementation**

Create `/Users/aj/Projects/clv/bin/psql`:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv postgres
source "$SCRIPT_PATH"/inc/ports
source "$SCRIPT_PATH"/inc/user
source "$SCRIPT_PATH"/inc/docker
clv_docker_run --entrypoint psql "postgres:${CLV_TAG:-17-alpine}" "$@"
```

- [ ] **Step 3: chmod, commit**

```bash
chmod +x /Users/aj/Projects/clv/bin/psql
git add bin/psql tests/107_psql.bats
git commit -m "feat(psql): add psql shim using postgres:17-alpine"
```

### Task 29: Add `mysql` shim

**Files:** `bin/mysql`, `tests/108_mysql.bats`

- [ ] **Step 1: Test**

Create `/Users/aj/Projects/clv/tests/108_mysql.bats`:

```bash
#!/usr/bin/env bats
load 'helpers/load'

@test "mysql shim emits expected docker command" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/mysql" --version
  [[ "$output" == *"mysql:"* ]]
  [[ "$output" == *"--entrypoint mysql"* ]]
}
```

- [ ] **Step 2: Implementation**

Create `/Users/aj/Projects/clv/bin/mysql`:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv mysql
source "$SCRIPT_PATH"/inc/ports
source "$SCRIPT_PATH"/inc/user
source "$SCRIPT_PATH"/inc/docker
clv_docker_run --entrypoint mysql "mysql:${CLV_TAG:-8}" "$@"
```

- [ ] **Step 3: chmod, commit**

```bash
chmod +x /Users/aj/Projects/clv/bin/mysql
git add bin/mysql tests/108_mysql.bats
git commit -m "feat(mysql): add mysql client shim"
```

### Task 30: Add `redis-cli` shim

**Files:** `bin/redis-cli`, `tests/109_redis_cli.bats`

- [ ] **Step 1: Test**

Create `/Users/aj/Projects/clv/tests/109_redis_cli.bats`:

```bash
#!/usr/bin/env bats
load 'helpers/load'

@test "redis-cli shim emits expected docker command" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/redis-cli" --version
  [[ "$output" == *"redis"* ]]
  [[ "$output" == *"--entrypoint redis-cli"* ]]
}
```

- [ ] **Step 2: Implementation**

Create `/Users/aj/Projects/clv/bin/redis-cli`:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv redis
source "$SCRIPT_PATH"/inc/ports
source "$SCRIPT_PATH"/inc/user
source "$SCRIPT_PATH"/inc/docker
clv_docker_run --entrypoint redis-cli "redis:${CLV_TAG:-7-alpine}" "$@"
```

- [ ] **Step 3: chmod, commit**

```bash
chmod +x /Users/aj/Projects/clv/bin/redis-cli
git add bin/redis-cli tests/109_redis_cli.bats
git commit -m "feat(redis-cli): add redis-cli shim"
```

### Task 31: Add `make` shim

**Files:** `bin/make`, `tests/110_make.bats`

- [ ] **Step 1: Test**

Create `/Users/aj/Projects/clv/tests/110_make.bats`:

```bash
#!/usr/bin/env bats
load 'helpers/load'

@test "make shim emits expected docker command" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/make" --version
  [[ "$output" == *"--entrypoint make"* ]]
}
```

- [ ] **Step 2: Implementation**

Create `/Users/aj/Projects/clv/bin/make`:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv alpine
source "$SCRIPT_PATH"/inc/user
source "$SCRIPT_PATH"/inc/docker
clv_docker_run --entrypoint make "alpine:${CLV_TAG:-latest}" "$@"
```

Note: `alpine` doesn't ship `make` by default. Add an init that installs it on first run:

Create `/Users/aj/Projects/clv/bin/init/alpine`:

```bash
#!/usr/bin/env bash
echo "clv is preparing alpine with make + build-base"
docker run --rm "alpine:${CLV_TAG:-latest}" \
    sh -c "apk add --no-cache make build-base >/dev/null"
```

Better alternative: use the `gcc` image which already has make:

Replace `bin/make` with:

```bash
#!/usr/bin/env bash
SCRIPT_PATH="$(
  cd "$(dirname "$0")" || exit
  pwd -P
)"
source "$SCRIPT_PATH"/init/clv gcc
source "$SCRIPT_PATH"/inc/user
source "$SCRIPT_PATH"/inc/docker
clv_docker_run --entrypoint make "gcc:${CLV_TAG:-latest}" "$@"
```

…and skip the alpine init. Adjust the test image expectation:

```bash
@test "make shim uses gcc image (ships make)" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/make" --version
  [[ "$output" == *"gcc:"* ]]
}
```

- [ ] **Step 3: chmod, commit**

```bash
chmod +x /Users/aj/Projects/clv/bin/make
git add bin/make tests/110_make.bats
git commit -m "feat(make): add make shim using gcc image"
```

---

## Phase 7 — CI + project hygiene

### Task 32: Add `shellcheck` to the Makefile and CI

**Files:** `.github/workflows/ci.yml`

- [ ] **Step 1: Create the workflow**

Create `/Users/aj/Projects/clv/.github/workflows/ci.yml`:

```yaml
name: ci

on:
  pull_request:
  push:
    branches: [main]

jobs:
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: true
      - uses: ludeeus/action-shellcheck@master
        with:
          scandir: '.'
          ignore_paths: 'tests/bats'

  bats:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: true
      - name: Run bats tests
        run: ./tests/bats/bats-core/bin/bats tests/

  install-smoke:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install to a temporary prefix
        run: |
          mkdir -p /tmp/clv-prefix
          CLV_INSTALL_PREFIX=/tmp/clv-prefix ./install
          test -x /tmp/clv-prefix/aws
          test -x /tmp/clv-prefix/clv
      - name: Verify clv version
        run: |
          PATH="/tmp/clv-prefix:$PATH"
          clv version
      - name: Uninstall
        run: |
          CLV_INSTALL_PREFIX=/tmp/clv-prefix ./uninstall
          test ! -e /tmp/clv-prefix/aws
```

- [ ] **Step 2: Verify locally that shellcheck passes**

Run: `make lint`
Expected: zero warnings. Fix any that appear by quoting variables, replacing `$@` with `"$@"`, etc.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add shellcheck, bats, and install-smoke GitHub Actions"
```

### Task 33: Update `CLAUDE.md` with the new architecture (env vars, inc/ helpers, new shims)

**Files:** `CLAUDE.md`

- [ ] **Step 1: Replace the relevant sections**

Edit `/Users/aj/Projects/clv/CLAUDE.md`:

Update the architecture description so the "Includes" bullet reads:

```
3. **Includes** — sourced by shims after `init/clv`:
   - [bin/inc/docker](bin/inc/docker) defines `clv_docker_run`, the single docker-run dispatcher honored by every shim. Honors `CLV_DRY_RUN=1` (print and exit) and `CLV_DOCKER_ARGS` (extra flags).
   - [bin/inc/ports](bin/inc/ports) translates the `PORTS` env into `--publish=…` flags, falling back to `--network=host`.
   - [bin/inc/ssh](bin/inc/ssh) forwards `$SSH_AUTH_SOCK`, `~/.ssh`, and `~/.gitconfig` into the container (only `git` uses this today).
   - [bin/inc/user](bin/inc/user) opt-in `--user $(id -u):$(id -g)` mapping when `CLV_MAP_USER=1`.
```

Update the command list in the first section:

```
aws, az, clv, gcloud, git, go, helm, ncu, node, npm, prettier, python, terraform, kubectl, yarn, pnpm, bun, deno, cargo, psql, mysql, redis-cli, make
```

Add a new "Environment contract for users" section under "Environment contract for shims":

```
## Environment contract for users

Any shim respects:
- `CLV_TAG` — override the default image tag (e.g. `CLV_TAG=20 node …` for node:20)
- `CLV_DRY_RUN=1` — print the docker command and exit instead of executing
- `CLV_DOCKER_ARGS` — extra flags spliced into `docker run` (e.g. `--memory=2g`)
- `CLV_MAP_USER=1` — run as host UID/GID (Linux file-ownership fix)
- `PORTS` — space-separated; bare numbers expand to `host:host`, colon-form passes through
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(claude): describe new inc/ helpers and CLV_* env vars"
```

### Task 34: Rewrite README

**Files:** `README.md`

- [ ] **Step 1: Replace the README content**

Replace `/Users/aj/Projects/clv/README.md` with:

````markdown
# clv

Thin Bash shims that wrap CLI tools so each invocation runs inside a transient Docker container. Persistent per-tool config lives at `~/.clv/<command>/`. Nothing to compile; install copies the shims to `/usr/local/bin/`.

## Available commands

| Cloud | VCS | Languages | Build/Lint | Databases | K8s |
|---|---|---|---|---|---|
| `aws` | `git` | `node`, `npm`, `yarn`, `pnpm`, `bun`, `deno` | `make`, `prettier`, `ncu` | `psql`, `mysql`, `redis-cli` | `kubectl`, `helm` |
| `az` |   | `go`, `python`, `cargo` |   |   | `terraform` |
| `gcloud` |   |   |   |   |   |

Plus `clv` itself (`clv version | list | update | prune`).

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
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs(readme): rewrite for new shim roster, env vars, and caveats"
```

### Task 35: Bump VERSION and tag a release

**Files:** `VERSION`, `CHANGELOG.md`

- [ ] **Step 1: Create CHANGELOG**

Create `/Users/aj/Projects/clv/CHANGELOG.md`:

```markdown
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
- `clv` meta-command: `version`, `list`, `update`, `prune`.

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
```

- [ ] **Step 2: Bump VERSION**

Already set to `2.0.0` in Task 20. Confirm.

- [ ] **Step 3: Commit and tag**

```bash
git add CHANGELOG.md
git commit -m "chore: changelog for 2.0.0"
git tag -a v2.0.0 -m "clv 2.0.0"
```

(Push and PR creation deferred to user — do not push tags or branches without explicit confirmation.)

---

## Self-review checklist (run before handing off)

- [x] Every spec section has a covering task (bugfixes 1–10 → Tasks 4–11; modernization 11–13 → Tasks 12–15; new shims → Tasks 21–31; quality-of-life → Tasks 14–20; CI/hygiene → Tasks 32–35).
- [x] No "TBD"/"implement later"/"add validation" placeholders.
- [x] Type/name consistency: `clv_docker_run`, `PUBLISHED_PORTS`, `SSH_MOUNTS`, `USER_MOUNTS`, `CLVHOME`, `CLV_TAG` used identically across all tasks.
- [x] Every task has exact file paths and complete code blocks.
- [x] Bug-fix phase precedes feature/new-shim phases so we never build on broken foundations.
- [x] Tests are written before the implementation in every task that introduces new behavior.

## Open questions — resolved

1. ~~Drop any of the 12 new shims?~~ **No — keep all 12.**
2. ~~Add `clv install` / `clv uninstall` subcommands?~~ **Yes — included in Task 20 (delegates to `web/install` / `web/uninstall`).**
3. ~~Bump to v2.0.0?~~ **Yes — confirmed.**
