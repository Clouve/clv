#!/usr/bin/env bats
load 'helpers/load'

@test "deno shim emits expected docker command" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/deno" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"denoland/deno"* ]]
  [[ "$output" == *"--entrypoint deno"* ]]
}
