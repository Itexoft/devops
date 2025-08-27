#!/usr/bin/env bash
set -Eeuo pipefail
"$INSTALL" python 3.12.6 >/dev/null
[ -x "$OSX_ROOT/pkgs/python/3.12.6/bin/python" ]
[ "$(readlink "$OSX_ROOT/pkgs/python/current")" = "$OSX_ROOT/pkgs/python/3.12.6" ]
"$OSX_ROOT/bin/osx-python" -c 'import sys;print(sys.version)' | grep -q '^3\.12\.'
target=$("$OSX_ROOT/bin/osx-pip" config get global.target)
case "$target" in "$OSX_ROOT/site-"*) ;; *) exit 1 ;; esac
