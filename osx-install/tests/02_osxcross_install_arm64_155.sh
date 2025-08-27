#!/usr/bin/env bash
set -Eeuo pipefail
"$INSTALL" osxcross >/dev/null
[ -x "$OSX_ROOT/pkgs/osxcross/target/bin/xcrun" ]
"$OSX_ROOT/bin/osx-xcrun" --version >/dev/null

