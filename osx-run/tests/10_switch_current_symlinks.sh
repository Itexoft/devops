#!/usr/bin/env bash
set -Eeuo pipefail
[ "$(readlink "$OSX_ROOT/pkgs/python/current")" = "$OSX_ROOT/pkgs/python/3.12.0" ]
[ "$(readlink "$OSX_ROOT/pkgs/node/current")" = "$OSX_ROOT/pkgs/node/22.7.0" ]
"$RUN" python -c 'import sys;print(sys.version)' | grep -q '^3\.12\.'
"$RUN" node -v | grep -q 'v22.7.0'
