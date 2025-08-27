#!/usr/bin/env bash
set -Eeuo pipefail
if ! command -v systemctl >/dev/null 2>&1; then exit 0; fi
if ! systemctl is-system-running >/dev/null 2>&1; then exit 0; fi
if ! command -v iptables >/dev/null 2>&1; then exit 0; fi
o=$(mktemp)
bash "$SQUID" start >"$o"
[ "$(tail -n1 "$o")" = started ]
u1="https://speed.hetzner.de/100MB.bin"
u2="https://speed.hetzner.de/200MB.bin"
cache=/tmp/squid-cache
ts(){ date +%s%3N; }
s=$(ts)
curl -L -o /dev/null "$u1"
e=$(ts)
t1=$((e-s))
s=$(ts)
curl -L -o /dev/null "$u2"
e=$(ts)
t2=$((e-s))
c=$(find "$cache" -type f | wc -l)
[ "$c" -ge 2 ]
s=$(ts)
curl -L -o /dev/null "$u1"
e=$(ts)
t3=$((e-s))
s=$(ts)
curl -L -o /dev/null "$u2"
e=$(ts)
t4=$((e-s))
s=$(ts)
curl -L -o /dev/null "$u1"
e=$(ts)
t5=$((e-s))
s=$(ts)
curl -L -o /dev/null "$u2"
e=$(ts)
t6=$((e-s))
[ "$t3" -lt "$t1" ]
[ "$t4" -lt "$t2" ]
[ "$t5" -le "$t3" ]
[ "$t6" -le "$t4" ]
bash "$SQUID" stop >"$o"
[ "$(tail -n1 "$o")" = stopped ]
[ ! -f /usr/local/share/ca-certificates/squid-mitm.crt ]
if iptables -t nat -S | grep -q SQUID_LOCAL; then false; fi
if systemctl is-active --quiet squid; then false; fi
c2=$(find "$cache" -type f | wc -l)
[ "$c2" -ge "$c" ]
echo "t1=$t1 t2=$t2 t3=$t3 t4=$t4 t5=$t5 t6=$t6"
