#!/usr/bin/env bats

load 'helpers/load'

setup_file() {
  shopt -s nullglob
}

@test "every top-level shim is executable" {
  for shim in "$REPO_ROOT"/bin/*; do
    [ -d "$shim" ] && continue
    [ -x "$shim" ] || fail "not executable: $shim"
  done
}

@test "every shim has a shebang" {
  for shim in "$REPO_ROOT"/bin/*; do
    [ -d "$shim" ] && continue
    head -n1 "$shim" | grep -q '^#!/usr/bin/env bash' \
      || fail "missing shebang: $shim"
  done
}

@test "init/clv exists and is sourced by every shim" {
  for shim in "$REPO_ROOT"/bin/*; do
    [ -d "$shim" ] && continue
    [[ "$(basename "$shim")" == "clv" ]] && continue  # meta-command, not a docker shim
    grep -qE '^[[:space:]]*(\.|source)[[:space:]].*init/clv' "$shim" \
      || fail "shim does not source init/clv: $shim"
  done
}
