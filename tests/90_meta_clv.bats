#!/usr/bin/env bats

load 'helpers/load'

@test "clv version prints the version from VERSION file" {
  run "$REPO_ROOT/bin/clv" version
  [ "$status" -eq 0 ]
  [[ "$output" == "2.0.0" ]]
}

@test "clv --help lists subcommands" {
  run "$REPO_ROOT/bin/clv" --help
  [[ "$output" == *"version"* ]]
  [[ "$output" == *"list"* ]]
  [[ "$output" == *"install"* ]]
  [[ "$output" == *"uninstall"* ]]
  [[ "$output" == *"update"* ]]
  [[ "$output" == *"prune"* ]]
}

@test "clv list prints installed shim names from PREFIX" {
  TMP="$(mktemp -d)"
  trap "rm -rf $TMP" EXIT
  mkdir -p "$TMP"
  cp "$REPO_ROOT/bin/aws" "$TMP/aws"
  cp "$REPO_ROOT/bin/git" "$TMP/git"
  CLV_INSTALL_PREFIX="$TMP" run "$REPO_ROOT/bin/clv" list
  [[ "$output" == *"aws"* ]]
  [[ "$output" == *"git"* ]]
}

@test "clv install with no args errors out" {
  run "$REPO_ROOT/bin/clv" install
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* || "$output" == *"shim"* ]]
}

@test "clv uninstall with no args errors out" {
  run "$REPO_ROOT/bin/clv" uninstall
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* || "$output" == *"shim"* ]]
}
