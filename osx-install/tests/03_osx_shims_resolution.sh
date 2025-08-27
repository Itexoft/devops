#!/usr/bin/env bash
set -Eeuo pipefail
"$INSTALL" osxcross >/dev/null
. "$OSX_ROOT/env/pathrc.sh"
osx-clang -v >/dev/null
[ -L "$OSX_ROOT/bin/osx-clang" ]
osx-lipo -h >/dev/null
[ -L "$OSX_ROOT/bin/osx-lipo" ]
sdk=$(osx-xcrun --show-sdk-path)
[ -n "$sdk" ]
export SDKROOT="$sdk"
[ "$SDKROOT" = "$sdk" ]
