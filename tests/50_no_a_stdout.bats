#!/usr/bin/env bats

load 'helpers/load'

@test "no shim contains the literal string '-a STDOUT'" {
  ! grep -rn -- "-a STDOUT" "$REPO_ROOT/bin/" \
    || { echo "found stale -a STDOUT — stderr would be dropped"; return 1; }
}
