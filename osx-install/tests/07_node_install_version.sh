#!/usr/bin/env bash
set -Eeuo pipefail
ver=22.7.0
"$INSTALL" node $ver >/dev/null
"$OSX_ROOT/bin/osx-node" -v | grep -q "v$ver"
"$OSX_ROOT/bin/osx-npm" -v >/dev/null
"$OSX_ROOT/bin/osx-npx" -v >/dev/null
