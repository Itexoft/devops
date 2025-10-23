#!/usr/bin/env bash
set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DLL="$DIR/netai.dll"
RUNTIME="$DIR/netai.runtimeconfig.json"
DEPS="$DIR/netai.deps.json"
DOTNET_ROLL_FORWARD="${DOTNET_ROLL_FORWARD:-LatestMajor}" DOTNET_NOLOGO=1 dotnet exec --runtimeconfig "$RUNTIME" --depsfile "$DEPS" "$DLL" "$@"
