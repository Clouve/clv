#!/usr/bin/env bats
load 'helpers/load'

@test "psql shim emits expected docker command" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/psql" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"postgres"* ]]
  [[ "$output" == *"--entrypoint psql"* ]]
}
