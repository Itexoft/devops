#!/usr/bin/env bash
set -Eeuo pipefail
touch "$HOME/.bashrc" "$HOME/.zshrc"
"$INSTALL" >/dev/null
dir=$(mktemp -d)
cd "$dir"
res=$(bash -ic 'osx-bcnf >/dev/null || true; pwd')
[ "$res" = "$dir" ]
[ -x "$OSX_ROOT/bin/osx-bcnf" ]
if command -v zsh >/dev/null; then
res=$(zsh -ic 'osx-zcnf >/dev/null || true; pwd')
[ "$res" = "$dir" ]
[ -x "$OSX_ROOT/bin/osx-zcnf" ]
fi

