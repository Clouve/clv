#!/usr/bin/env bats
load 'helpers/load'

@test "mysql shim emits expected docker command" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/mysql" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"mysql:"* ]]
  [[ "$output" == *"--entrypoint mysql"* ]]
}
