#!/usr/bin/env bash
set -Eeuo pipefail
"$INSTALL" python 3.11.0 >/dev/null
"$INSTALL" python 3.12.0 >/dev/null
[ "$(readlink "$OSX_ROOT/pkgs/python/current")" = "$OSX_ROOT/pkgs/python/3.12.0" ]
"$INSTALL" node 22.6.0 >/dev/null
"$INSTALL" node 22.7.0 >/dev/null
[ "$(readlink "$OSX_ROOT/pkgs/node/current")" = "$OSX_ROOT/pkgs/node/22.7.0" ]
"$OSX_ROOT/bin/osx-python" -c 'import sys;print(sys.version)' | grep -q '^3\.12\.'
"$OSX_ROOT/bin/osx-node" -v | grep -q 'v22.7.0'
