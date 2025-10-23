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
