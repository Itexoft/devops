#!/usr/bin/env bash
set -Eeuo pipefail
out=$("$INSTALL" osxcross 2>&1)
[ -x "$OSX_ROOT/pkgs/osxcross/target/bin/xcrun" ]
"$OSX_ROOT/bin/osx-xcrun" --version >/dev/null
printf '%s' "$out" | grep -q ENABLE_ARCHS
printf '%s' "$out" | grep -q UNATTENDED
printf '%s' "$out" | grep -q TARGET_DIR
