#!/usr/bin/env bats

load 'helpers/load'

@test "every shim references CLV_TAG with a default" {
  for shim in "$REPO_ROOT"/bin/*; do
    [ -d "$shim" ] && continue
    [[ "$(basename "$shim")" == "clv" ]] && continue
    grep -q 'CLV_TAG:-' "$shim" \
      || fail "shim does not honor CLV_TAG: $shim"
  done
}

@test "no shim references a bare image name without a tag" {
  for shim in "$REPO_ROOT"/bin/*; do
    [ -d "$shim" ] && continue
    [[ "$(basename "$shim")" == "clv" ]] && continue
    grep -E 'clv_docker_run.*"[a-z./-]+"\s*"\$@"' "$shim" >/dev/null \
      && fail "shim has untagged image: $shim"
  done
  return 0  # ensure success when no match found
}
