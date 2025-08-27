#!/usr/bin/env bash
set -Eeuo pipefail
systemctl is-system-running >/dev/null 2>&1 || exit 0
o=$(mktemp)
"$SQUID" start >"$o"
[ "$(tail -n1 "$o")" = started ]
u1="https://speed.hetzner.de/200MB.bin"
u2="https://speed.hetzner.de/1GB.bin"
cache=/tmp/squid-cache
s=$(date +%s)
curl -L -o /dev/null "$u1"
e=$(date +%s)
t1=$((e-s))
s=$(date +%s)
curl -L -o /dev/null "$u2"
e=$(date +%s)
t2=$((e-s))
c=$(find "$cache" -type f | wc -l)
[ "$c" -ge 2 ]
s=$(date +%s)
curl -L -o /dev/null "$u1"
e=$(date +%s)
t3=$((e-s))
s=$(date +%s)
curl -L -o /dev/null "$u2"
e=$(date +%s)
t4=$((e-s))
[ "$t3" -lt "$t1" ]
[ "$t4" -lt "$t2" ]
"$SQUID" stop >"$o"
[ "$(tail -n1 "$o")" = stopped ]
[ ! -f /usr/local/share/ca-certificates/squid-mitm.crt ]
if iptables -t nat -S | grep -q SQUID_LOCAL; then false; fi
if systemctl is-active --quiet squid; then false; fi
c2=$(find "$cache" -type f | wc -l)
[ "$c2" -ge "$c" ]
echo "t1=$t1 t2=$t2 t3=$t3 t4=$t4"
