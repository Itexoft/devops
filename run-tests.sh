#!/usr/bin/env bash
set -Eeuo pipefail
INSTALL="./osx-install/osx-install.sh"
export INSTALL
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
run(){
t="$1"
name=$(basename "$t")
log=artifacts/${name%.sh}.log
work=$(mktemp -d)
home=$(mktemp -d)
OSX_ROOT="$work/opt/osx"
HOME="$home"
export OSX_ROOT HOME
if "$t" >"$log" 2>&1; then
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
for f in osx-install/tests/*.sh; do
tests+=("$f")
done
else
for a in "$@"; do
tests+=("osx-install/tests/$a")
done
fi
for t in "${tests[@]}"; do
run "$t"
done
echo "passed $pass failed $fail"
[ "$fail" -eq 0 ]
