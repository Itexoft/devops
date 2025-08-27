#!/usr/bin/env bash
set -Eeuo pipefail
shellcheck -e SC1091,SC2154,SC2034,SC2086,SC2015 "$INSTALL" run-tests.sh osx-install/tests/*.sh
