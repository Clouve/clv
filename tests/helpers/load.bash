#!/usr/bin/env bash
# Source this from the `setup()` of any bats test file:
#   load '../helpers/load'

TESTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
REPO_ROOT="$(cd "$TESTS_ROOT/.." && pwd -P)"

load "$TESTS_ROOT/bats/bats-support/load"
load "$TESTS_ROOT/bats/bats-assert/load"

# Run a shim from the repo with CLV_DRY_RUN=1 so it prints the docker
# command instead of executing it. Output is captured in $output by bats `run`.
clv_dry() {
  CLV_DRY_RUN=1 "$REPO_ROOT/bin/$1" "${@:2}"
}
