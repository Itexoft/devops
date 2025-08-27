#!/usr/bin/env bash
set -Eeuo pipefail
sdk=$("$RUN" xcrun --show-sdk-path)
[ -n "$sdk" ]
export SDKROOT="$sdk"
[ "$SDKROOT" = "$sdk" ]
