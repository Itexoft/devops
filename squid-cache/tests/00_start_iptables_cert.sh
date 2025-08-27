#!/usr/bin/env bash
set -Eeuo pipefail
if ! command -v systemctl >/dev/null 2>&1; then exit 0; fi
if ! systemctl is-system-running >/dev/null 2>&1; then exit 0; fi
if ! command -v iptables >/dev/null 2>&1; then exit 0; fi
o=$(mktemp)
"$SQUID" start >"$o"
[ "$(tail -n1 "$o")" = started ]
iptables -t nat -S | grep -q SQUID_LOCAL
[ -f /usr/local/share/ca-certificates/squid-mitm.crt ]
"$SQUID" stop >"$o"
[ "$(tail -n1 "$o")" = stopped ]
