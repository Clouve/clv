#!/usr/bin/env bats
load 'helpers/load'

@test "pnpm shim emits expected docker command" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/pnpm" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"--entrypoint pnpm"* ]]
}
