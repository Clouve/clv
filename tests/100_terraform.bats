#!/usr/bin/env bats
load 'helpers/load'

@test "terraform shim emits expected docker command" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/terraform" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"hashicorp/terraform"* ]]
  [[ "$output" == *"--entrypoint terraform"* ]]
}
