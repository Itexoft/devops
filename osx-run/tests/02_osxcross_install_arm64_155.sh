#!/usr/bin/env bash
set -Eeuo pipefail
"$RUN" xcrun --version >/dev/null
[ -x "$OSX_ROOT/pkgs/osxcross/target/bin/xcrun" ]

