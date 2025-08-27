#!/usr/bin/env bash
set -Eeuo pipefail
systemctl is-system-running >/dev/null 2>&1 || exit 0
o=$(mktemp)
"$SQUID" start >"$o"
[ "$(tail -n1 "$o")" = started ]
tmp=$(mktemp -d)
apt-get update >/dev/null
apt-get download python3.11-minimal >/dev/null
d=$(ls python3.11-minimal_*.deb)
dpkg -x "$d" "$tmp"
[ -x "$tmp/usr/bin/python3.11" ]
"$SQUID" stop >"$o"
[ "$(tail -n1 "$o")" = stopped ]
rm -rf "$tmp" "$d"
