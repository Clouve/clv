#!/usr/bin/env bats
load 'helpers/load'

@test "make shim uses gcc image (ships make)" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/make" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"gcc:"* ]]
  [[ "$output" == *"--entrypoint make"* ]]
}
