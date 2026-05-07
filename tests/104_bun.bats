#!/usr/bin/env bats
load 'helpers/load'

@test "bun shim emits expected docker command" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/bun" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"oven/bun"* ]]
  [[ "$output" == *"--entrypoint bun"* ]]
}
