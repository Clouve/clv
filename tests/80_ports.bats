#!/usr/bin/env bats

load 'helpers/load'

@test "PORTS=8080 expands to 8080:8080" {
  run bash -c '
    PORTS="8080"
    source "'"$REPO_ROOT/bin/inc/ports"'"
    printf "%s\n" "${PUBLISHED_PORTS[@]}"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"--publish=8080:8080"* ]]
}

@test "PORTS=127.0.0.1:8080:8080 passes through unchanged" {
  run bash -c '
    PORTS="127.0.0.1:8080:8080"
    source "'"$REPO_ROOT/bin/inc/ports"'"
    printf "%s\n" "${PUBLISHED_PORTS[@]}"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "--publish=127.0.0.1:8080:8080" ]
}

@test "PORTS=8080:9090 supports host:container mapping" {
  run bash -c '
    PORTS="8080:9090"
    source "'"$REPO_ROOT/bin/inc/ports"'"
    printf "%s\n" "${PUBLISHED_PORTS[@]}"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "--publish=8080:9090" ]
}

@test "PORTS unset defaults to host networking" {
  run bash -c '
    unset PORTS
    source "'"$REPO_ROOT/bin/inc/ports"'"
    printf "%s\n" "${PUBLISHED_PORTS[@]}"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"--network=host"* ]]
}
