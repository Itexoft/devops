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
p2="$PATH"
. "$OSX_ROOT/env/pathrc.sh"
p3="$PATH"
[ "$p2" = "$p3" ]
