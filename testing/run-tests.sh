#!/usr/bin/env bash
set -Eeuo pipefail
if ! command -v shellcheck >/dev/null 2>&1 || ! command -v file >/dev/null 2>&1; then /usr/bin/sudo apt-get update; /usr/bin/sudo apt-get install -y shellcheck file; fi
mkdir -p artifacts
printf 'bash %s\n' "$(bash --version | head -n1)"
printf 'zsh %s\n' "$(zsh --version 2>/dev/null | head -n1)"
printf 'clang %s\n' "$(clang --version 2>/dev/null | head -n1)"
printf 'lld %s\n' "$(ld.lld --version 2>/dev/null | head -n1)"
printf 'npm %s\n' "$(npm -v 2>/dev/null)"
printf 'node %s\n' "$(node -v 2>/dev/null)"
printf 'python %s\n' "$(python -V 2>&1)"
printf 'shellcheck %s\n' "$(shellcheck --version 2>/dev/null | head -n1)"
pass=0
fail=0
RUN="$(pwd)/osx-run/osx-run.sh"
export RUN
run(){
t="$1"
name=$(basename "$t")
log=artifacts/${name%.sh}.log
work=$(mktemp -d)
home=$(mktemp -d)
OSX_ROOT="$work/opt/osx"
HOME="$home"
export OSX_ROOT HOME
testing/stub-env.sh "$OSX_ROOT"
cmd=("$t")
[ -n "${TRACE:-}" ] && cmd=(bash -x "$t")
if "${cmd[@]}" >"$log" 2>&1; then
echo "$name PASS"
pass=$((pass+1))
else
echo "$name FAIL"
fail=$((fail+1))
fi
rm -rf "$work" "$home"
}
tests=()
if [ "$#" -eq 0 ]; then
echo "usage: $0 <dir|tests...>"
exit 1
fi
if [ -d "$1" ]; then
for f in "$1"/*.sh; do
tests+=("$f")
 done
else
for a in "$@"; do
tests+=("$a")
 done
fi
for t in "${tests[@]}"; do
run "$t"
done
echo "passed $pass failed $fail"
[ "$fail" -eq 0 ]
