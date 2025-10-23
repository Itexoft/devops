#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ -n "${PYTHONPATH:-}" ]]; then
  export PYTHONPATH="$PROJECT_ROOT:$PYTHONPATH"
else
  export PYTHONPATH="$PROJECT_ROOT"
fi

python3 -m scai.cli "$@"
exit_code=$?

if [[ "${1:-}" == "service" && "${2:-}" == "stop" ]]; then
  python3 - <<'PY'
import os
import stat

def rm(path: str) -> None:
    if not os.path.exists(path):
        return
    mode = os.lstat(path).st_mode
    if stat.S_ISDIR(mode):
        for name in os.listdir(path):
            if name in ('.', '..'):
                continue
            rm(os.path.join(path, name))
        try:
            os.rmdir(path)
        except OSError:
            pass
    else:
        try:
            os.unlink(path)
        except OSError:
            pass

rm(os.path.join(r"${SCRIPT_DIR}", "runtime"))
PY
fi

exit $exit_code
