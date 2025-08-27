#!/usr/bin/env bash
set -Eeuo pipefail
if SDK_TARBALL_URL="file:///nonexistent.tar.xz" "$INSTALL" osxcross >/tmp/log 2>&1; then exit 1; fi
grep -q 'SDK tarball not found' /tmp/log
