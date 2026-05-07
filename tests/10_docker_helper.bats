#!/usr/bin/env bats

load 'helpers/load'

setup() {
  export CLV_DRY_RUN=1
}

@test "clv_docker_run prints docker command and exits 0 when CLV_DRY_RUN=1" {
  run bash -c '
    CLVHOME="$HOME/.clv/test"
    IT="-i"
    SCRIPT_PATH="'"$REPO_ROOT/bin"'"
    PUBLISHED_PORTS=()
    source "$SCRIPT_PATH/inc/docker"
    clv_docker_run --entrypoint myentry myimage:1.0 arg1 arg2
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"docker run"* ]]
  [[ "$output" == *"--entrypoint myentry"* ]]
  [[ "$output" == *"myimage:1.0"* ]]
  [[ "$output" == *"arg1 arg2"* ]]
}

@test "clv_docker_run does not pass -a STDOUT (regression: stderr was lost)" {
  run bash -c '
    CLVHOME="$HOME/.clv/test"
    IT="-i"
    SCRIPT_PATH="'"$REPO_ROOT/bin"'"
    PUBLISHED_PORTS=()
    source "$SCRIPT_PATH/inc/docker"
    clv_docker_run myimage:1.0
  '
  [[ "$output" != *"-a STDOUT"* ]]
}

@test "clv_docker_run honors CLV_DOCKER_ARGS pass-through" {
  run bash -c '
    CLVHOME="$HOME/.clv/test"
    IT="-i"
    SCRIPT_PATH="'"$REPO_ROOT/bin"'"
    PUBLISHED_PORTS=()
    CLV_DOCKER_ARGS="--memory=2g --cpus=1.5"
    source "$SCRIPT_PATH/inc/docker"
    clv_docker_run myimage:1.0
  '
  [[ "$output" == *"--memory=2g"* ]]
  [[ "$output" == *"--cpus=1.5"* ]]
}
