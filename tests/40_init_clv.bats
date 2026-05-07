#!/usr/bin/env bats

load 'helpers/load'

setup() {
  HOME_BAK="$HOME"
  TMP="$(mktemp -d)"
  export HOME="$TMP"
}

teardown() {
  export HOME="$HOME_BAK"
  rm -rf "$TMP"
}

@test "init/clv treats image names with regex metachars as literals" {
  mkdir -p "$HOME/.clv"
  echo "amazon/aws-cli" > "$HOME/.clv/.init"

  # Pre-condition: a literal match should be hit.
  run bash -c '
    set -e
    SCRIPT_PATH="'"$REPO_ROOT/bin"'"
    source "$SCRIPT_PATH/init/clv" amazon/aws-cli
    echo OK
  '
  [[ "$output" == *"OK"* ]]
  # Should NOT print "clv is initializing"
  [[ "$output" != *"initializing"* ]]
}
