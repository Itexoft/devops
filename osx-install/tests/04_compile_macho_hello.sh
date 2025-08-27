#!/usr/bin/env bash
set -Eeuo pipefail
"$INSTALL" osxcross >/dev/null
. "$OSX_ROOT/env/pathrc.sh"
. "$OSX_ROOT/env/config.sh"
cat > hello.c <<'EOC'
int main(){return 0;}
EOC
osx-clang hello.c -o hello -arch "$DEFAULT_ARCH" -mmacosx-version-min="$DEFAULT_DEPLOY_MIN"
file hello | grep -qi 'Mach-O'
