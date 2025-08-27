#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
. ../../testing/assert.sh
assert_cmd iptables
assert_env SQUID
iptables -t nat -L >/dev/null 2>&1
o=$(mktemp)
base=$(dirname "$SQUID")
bash "$SQUID" start >"$o" || exit 1
[ "$(tail -n1 "$o")" = started ]
iptables -t nat -S | grep -q SQUID_LOCAL
assert_file "$base/mitm_ca/ca.crt"
assert_file /usr/local/share/ca-certificates/squid-mitm.crt
bash "$SQUID" stop >"$o"
[ "$(tail -n1 "$o")" = stopped ]
[ ! -f /usr/local/share/ca-certificates/squid-mitm.crt ]
