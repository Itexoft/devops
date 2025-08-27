#!/usr/bin/env bash
set -Eeuo pipefail
"$RUN" install python 3.12 >/dev/null
"$RUN" python -c 'import sys;print(sys.version)' | grep -q '^3\.12\.'
grep -q "$OSX_ROOT/site-" "$OSX_ROOT/env/pip-macos.conf"
