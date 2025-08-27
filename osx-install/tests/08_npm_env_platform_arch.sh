#!/usr/bin/env bash
set -Eeuo pipefail
ver=22.7.0
"$INSTALL" node $ver >/dev/null
. "$OSX_ROOT/env/config.sh"
out=$("$OSX_ROOT/bin/osx-npm" config list -l)
printf '%s' "$out" | grep -q 'platform.*darwin'
printf '%s' "$out" | grep -q "arch.*$DEFAULT_ARCH"
printf '%s' "$out" | grep -q "target-arch.*$DEFAULT_ARCH"
