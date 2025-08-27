#!/usr/bin/env bash
set -Eeuo pipefail
[ "$("$SQUID" start)" = "started" ]
iptables -t nat -S | grep -q SQUID_LOCAL
[ -f /usr/local/share/ca-certificates/squid-mitm.crt ]
[ "$("$SQUID" stop)" = "stopped" ]
