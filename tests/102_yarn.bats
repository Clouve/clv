#!/usr/bin/env bats
load 'helpers/load'

@test "yarn shim shares node home and uses node image" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/yarn" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"--entrypoint yarn"* ]]
  [[ "$output" == *"/.clv/node:/root"* ]]
}
