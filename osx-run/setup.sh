#!/usr/bin/env bash
set -Eeuox pipefail

cmd="$HOME/osx-run/osx-run.sh"
mkdir -p "$(dirname "$cmd")"
curl -L https://raw.githubusercontent.com/Itexoft/devops/refs/heads/master/osx-run/osx-run.sh -o "$cmd"
chmod +x "$cmd" && $cmd

$cmd install osxcross