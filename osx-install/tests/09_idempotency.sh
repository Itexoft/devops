#!/usr/bin/env bash
set -Eeuo pipefail
touch "$HOME/.bashrc"
"$INSTALL" >/dev/null
h1=$(sha1sum "$HOME/.bashrc" | cut -d' ' -f1)
"$INSTALL" >/dev/null
[ "$h1" = "$(sha1sum "$HOME/.bashrc" | cut -d' ' -f1)" ]
"$INSTALL" node 22.7.0 >/dev/null
c1=$(readlink "$OSX_ROOT/pkgs/node/current")
"$INSTALL" node 22.7.0 >/dev/null
c2=$(readlink "$OSX_ROOT/pkgs/node/current")
[ "$c1" = "$c2" ]
. "$OSX_ROOT/env/pathrc.sh"
. "$OSX_ROOT/env/pathrc.sh"
count=$(printf '%s' "$PATH" | grep -o "$OSX_ROOT/bin" | wc -l)
[ "$count" -eq 1 ]
