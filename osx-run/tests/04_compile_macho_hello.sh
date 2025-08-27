#!/usr/bin/env bash
set -Eeuo pipefail
. "$OSX_ROOT/env/config.sh"
cat > hello.c <<'EOC'
int main(){return 0;}
EOC
"$RUN" clang hello.c -o hello -arch "$DEFAULT_ARCH" -mmacosx-version-min="$DEFAULT_DEPLOY_MIN"
file hello | grep -qi 'Mach-O'
