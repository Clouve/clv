#!/usr/bin/env bats
load 'helpers/load'

@test "cargo shim emits expected docker command" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/cargo" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"rust"* ]]
  [[ "$output" == *"--entrypoint cargo"* ]]
}
