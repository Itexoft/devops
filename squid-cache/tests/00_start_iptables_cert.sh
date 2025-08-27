#!/usr/bin/env bash
set -Eeuo pipefail
if ! command -v iptables >/dev/null 2>&1; then exit 0; fi
iptables -t nat -L >/dev/null 2>&1 || exit 0
o=$(mktemp)
base=$(dirname "$SQUID")
bash "$SQUID" start >"$o" || exit 1
[ "$(tail -n1 "$o")" = started ]
iptables -t nat -S | grep -q SQUID_LOCAL
[ -f "$base/mitm_ca/ca.crt" ]
[ -f /usr/local/share/ca-certificates/squid-mitm.crt ]
bash "$SQUID" stop >"$o"
[ "$(tail -n1 "$o")" = stopped ]
[ ! -f /usr/local/share/ca-certificates/squid-mitm.crt ]
