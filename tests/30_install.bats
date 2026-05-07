#!/usr/bin/env bats

load 'helpers/load'

setup() {
  TMP="$(mktemp -d)"
  export PREFIX="$TMP/usr-local-bin"
  mkdir -p "$PREFIX"
  # we'll exercise install via a fake sudo + custom prefix
  cat > "$TMP/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
  chmod +x "$TMP/sudo"
  PATH="$TMP:$PATH"
  export CLV_INSTALL_PREFIX="$PREFIX"
}

teardown() {
  rm -rf "$TMP"
}

@test "install overwrites an existing shim with new content" {
  echo "old content" > "$PREFIX/aws"
  PATH="$TMP:$PATH" "$REPO_ROOT/install" aws
  run cat "$PREFIX/aws"
  [[ "$output" != "old content" ]]
  [[ "$output" == *"amazon/aws-cli"* ]]
}
