#!/usr/bin/env bash
set -Eeuo pipefail
systemctl is-system-running >/dev/null 2>&1 || exit 0
o=$(mktemp)
"$SQUID" start >"$o"
[ "$(tail -n1 "$o")" = started ]
iptables -t nat -S | grep -q SQUID_LOCAL
[ -f /usr/local/share/ca-certificates/squid-mitm.crt ]
"$SQUID" stop >"$o"
[ "$(tail -n1 "$o")" = stopped ]
