#!/usr/bin/env bash
set -Eeuo pipefail
"$INSTALL" osxcross >/dev/null
. "$OSX_ROOT/env/pathrc.sh"
sdk=$(osx-xcrun --show-sdk-path)
[ -n "$sdk" ]
export SDKROOT="$sdk"
[ "$SDKROOT" = "$sdk" ]
