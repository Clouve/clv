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
