#!/usr/bin/env bash
set -Eeuo pipefail
touch "$HOME/.bashrc" "$HOME/.zshrc"
PATH="/usr/bin"
"$INSTALL" >/dev/null
p1="$PATH"
hb=$(sha1sum "$HOME/.bashrc" | cut -d' ' -f1)
hz=$(sha1sum "$HOME/.zshrc" | cut -d' ' -f1)
"$INSTALL" >/dev/null
[ "$PATH" = "$p1" ]
[ "$hb" = "$(sha1sum "$HOME/.bashrc" | cut -d' ' -f1)" ]
[ "$hz" = "$(sha1sum "$HOME/.zshrc" | cut -d' ' -f1)" ]
bash -ic 'osx-alpha >/dev/null || true'
[ -x "$OSX_ROOT/bin/osx-alpha" ]
zsh -ic 'osx-beta >/dev/null || true'
[ -x "$OSX_ROOT/bin/osx-beta" ]
