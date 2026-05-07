#!/usr/bin/env bats

load 'helpers/load'

setup() {
  export CLV_DRY_RUN=1
  TMP="$(mktemp -d)"
  HOME_BAK="$HOME"
  export HOME="$TMP"
  mkdir -p "$HOME/.ssh"
  echo "[user]" > "$HOME/.gitconfig"
  export SSH_AUTH_SOCK="$TMP/agent.sock"
  # Create a real Unix socket so -S test in inc/ssh passes
  python3 -c "import socket,os,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])" "$SSH_AUTH_SOCK"
}

teardown() {
  export HOME="$HOME_BAK"
  rm -rf "$TMP"
}

@test "git shim forwards SSH agent socket" {
  run clv_dry git --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"$SSH_AUTH_SOCK:/ssh-agent"* ]]
  [[ "$output" == *"SSH_AUTH_SOCK=/ssh-agent"* ]]
}

@test "git shim mounts ~/.ssh and ~/.gitconfig read-only" {
  run clv_dry git --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/.ssh:/root/.ssh:ro"* ]]
  [[ "$output" == *"$HOME/.gitconfig:/root/.gitconfig:ro"* ]]
}
