#!/usr/bin/env bats
load 'helpers/load'

@test "redis-cli shim emits expected docker command" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/redis-cli" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"redis"* ]]
  [[ "$output" == *"--entrypoint redis-cli"* ]]
}
