#!/usr/bin/env bash
set -Eeuo pipefail
run(){
 log="$1"
 shift
 exec 3>&1
 "$@" >"$log" 2>&1
}
"$@"
