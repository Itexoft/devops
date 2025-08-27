#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"
BASE_DIR="$(cd "$(dirname "$0")" && pwd -P)"
LOCK_DIR="/run/squid-mitm"
PID_DIR="/run/squid-mitm"
MONITOR_PID="$PID_DIR/monitor.pid"
LOCK_FILE="$LOCK_DIR/lock"
SQUID_PKG="squid-openssl"
SQUID_SERVICE="squid"
SQUID_USER="proxy"
SQUID_GROUP="proxy"
HTTP_PORT="3128"
HTTPS_PORT="3129"
HOSTNAME_TAG="squid-mitm"
CA_DIR="/etc/squid/mitm_ca"
CA_KEY="$CA_DIR/ca.key"
CA_CRT="$CA_DIR/ca.crt"
CA_PEM="$CA_DIR/ca.pem"
CA_TRUST_NAME="squid-mitm"
CA_DAYS="3650"
CA_SUBJ="/CN=$HOSTNAME_TAG/O=$HOSTNAME_TAG/L=Local/C=NA"
SSL_DB_DIR="/var/lib/squid/ssl_db"
CACHE_IF_STANDALONE_BIN="$BASE_DIR/squid-cache"
CACHE_IF_SYSTEM="/tmp/squid-cache"
SQUID_BIN_SYSTEM="/usr/sbin/squid"
SQUID_CONF="/etc/squid/squid.conf"
SQUID_CONF_BAK="/etc/squid/squid.conf.bak.mitm"
SQUID_LOG="/var/log/squid/cache.log"
CACHE_SIZE_MB="10240"
MEM_CACHE_MB="128"
FILE_MIMES_REGEX="application/(octet-stream|zip|x-zip-compressed|x-gzip|x-xz|x-bzip2|x-7z-compressed|x-tar|x-debian-package|x-rpm|java-archive|gzip|zstd|x-iso9660-image|vnd\\.ms-cab-compressed|x-msdownload)|image/.*|video/.*|audio/.*|application/pdf"
REFRESH_LONG_MIN="525600"
IPTABLES_CHAIN="SQUID_LOCAL"

require_root() {
  [ "${EUID:-$(id -u)}" -eq 0 ] || { echo "root required"; exit 1; }
}

ensure_dirs() {
  mkdir -p "$LOCK_DIR" "$PID_DIR" "$CA_DIR"
}

cache_dir_pick() {
  if [ -x "$BASE_DIR/squid-cache" ]; then
    echo "$CACHE_IF_STANDALONE_BIN"
  else
    echo "$CACHE_IF_SYSTEM"
  fi
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y "$SQUID_PKG" ca-certificates iptables
}

detect_ssl_helper() {
  if [ -x /usr/lib/squid/security_file_certgen ]; then
    echo "/usr/lib/squid/security_file_certgen"
  elif [ -x /usr/lib/squid/ssl_crtd ]; then
    echo "/usr/lib/squid/ssl_crtd"
  else
    echo ""
  fi
}

gen_ca() {
  if [ ! -f "$CA_PEM" ]; then
    openssl req -new -newkey rsa:4096 -sha256 -days "$CA_DAYS" -nodes -x509 -keyout "$CA_KEY" -out "$CA_CRT" -subj "$CA_SUBJ"
    cat "$CA_KEY" "$CA_CRT" > "$CA_PEM"
    chown -R "$SQUID_USER:$SQUID_GROUP" "$CA_DIR"
    chmod 0400 "$CA_KEY"
  fi
}

trust_ca() {
  install -m 0644 "$CA_CRT" "/usr/local/share/ca-certificates/${CA_TRUST_NAME}.crt"
  update-ca-certificates || true
}

untrust_ca() {
  rm -f "/usr/local/share/ca-certificates/${CA_TRUST_NAME}.crt"
  update-ca-certificates || true
}

write_squid_conf() {
  local helper="$1"
  local cache_dir="$2"
  [ -f "$SQUID_CONF" ] && [ ! -f "$SQUID_CONF_BAK" ] && cp -f "$SQUID_CONF" "$SQUID_CONF_BAK"
  install -d -o "$SQUID_USER" -g "$SQUID_GROUP" "$cache_dir"
  install -d -o "$SQUID_USER" -g "$SQUID_GROUP" "$(dirname "$SQUID_LOG")"
  cat >"$SQUID_CONF" <<EOF
visible_hostname $HOSTNAME_TAG
acl localnet src 0.0.0.0/0
acl step1 at_step SslBump1
http_port $HTTP_PORT intercept
https_port $HTTPS_PORT intercept ssl-bump generate-host-certificates=on dynamic_cert_mem_cache_size=4MB cert=$CA_PEM
sslcrtd_program $helper -s $SSL_DB_DIR -M 20MB
sslcrtd_children 5 startup=1 idle=1
ssl_bump peek step1
ssl_bump bump all
http_access allow localnet
cache_dir ufs $cache_dir ${CACHE_SIZE_MB} 16 256
cache_mem ${MEM_CACHE_MB} MB
maximum_object_size 102400 MB
maximum_object_size_in_memory 8 MB
acl file_mime rep_mime_type -i $FILE_MIMES_REGEX
cache deny !file_mime
refresh_pattern -i \.(deb|rpm|zip|gz|xz|zst|7z|tar|tgz|bz2|iso|img|whl|jar|pdf|png|jpe?g|gif|webp|mp4|avi|mkv|mp3|flac)$ 0 100% ${REFRESH_LONG_MIN} ignore-reload override-expire override-lastmod ignore-no-cache ignore-no-store ignore-private
refresh_pattern . 0 20% ${REFRESH_LONG_MIN} ignore-reload override-expire override-lastmod ignore-no-cache ignore-no-store ignore-private
tls_outgoing_options cafile=/etc/ssl/certs/ca-certificates.crt
EOF
  chown "$SQUID_USER:$SQUID_GROUP" "$SQUID_CONF"
}

init_ssl_db() {
  local helper="$1"
  install -d -o "$SQUID_USER" -g "$SQUID_GROUP" "$SSL_DB_DIR"
  su -s /bin/sh -c "$helper -c -s $SSL_DB_DIR -M 20MB" "$SQUID_USER" || true
}

iptables_enable() {
  local squid_uid
  squid_uid="$(id -u "$SQUID_USER")"
  iptables -t nat -N "$IPTABLES_CHAIN" 2>/dev/null || true
  iptables -t nat -C OUTPUT -j "$IPTABLES_CHAIN" 2>/dev/null || iptables -t nat -A OUTPUT -j "$IPTABLES_CHAIN"
  iptables -t nat -C "$IPTABLES_CHAIN" -m owner --uid-owner "$squid_uid" -j RETURN 2>/dev/null || iptables -t nat -A "$IPTABLES_CHAIN" -m owner --uid-owner "$squid_uid" -j RETURN
  iptables -t nat -C "$IPTABLES_CHAIN" -d 127.0.0.0/8 -j RETURN 2>/dev/null || iptables -t nat -A "$IPTABLES_CHAIN" -d 127.0.0.0/8 -j RETURN
  iptables -t nat -C "$IPTABLES_CHAIN" -p tcp --dport 80 -j REDIRECT --to-ports "$HTTP_PORT" 2>/dev/null || iptables -t nat -A "$IPTABLES_CHAIN" -p tcp --dport 80 -j REDIRECT --to-ports "$HTTP_PORT"
  iptables -t nat -C "$IPTABLES_CHAIN" -p tcp --dport 443 -j REDIRECT --to-ports "$HTTPS_PORT" 2>/dev/null || iptables -t nat -A "$IPTABLES_CHAIN" -p tcp --dport 443 -j REDIRECT --to-ports "$HTTPS_PORT"
}

iptables_disable() {
  if iptables -t nat -S OUTPUT | grep -q "$IPTABLES_CHAIN"; then
    iptables -t nat -D OUTPUT -j "$IPTABLES_CHAIN" || true
  fi
  if iptables -t nat -S | grep -q "^-N $IPTABLES_CHAIN"; then
    while iptables -t nat -S "$IPTABLES_CHAIN" | grep -q "^-A $IPTABLES_CHAIN"; do
      local rule
      rule="$(iptables -t nat -S "$IPTABLES_CHAIN" | grep "^-A $IPTABLES_CHAIN" | head -n1 | sed 's/^-A /-D /')"
      iptables -t nat "$rule" || true
    done
    iptables -t nat -X "$IPTABLES_CHAIN" || true
  fi
}

squid_prepare_cache() {
  "$SQUID_BIN_SYSTEM" -z || true
}

squid_start() {
  systemctl restart "$SQUID_SERVICE"
}

squid_stop() {
  systemctl stop "$SQUID_SERVICE" || true
}

monitor_start() {
  if [ -f "$MONITOR_PID" ] && kill -0 "$(cat "$MONITOR_PID")" 2>/dev/null; then
    exit 0
  fi
  nohup bash -c "
    while true; do
      if ! systemctl is-active --quiet $SQUID_SERVICE; then
        iptables_disable
        untrust_ca
        exit 0
      fi
      sleep 2
    done
  " >/dev/null 2>&1 &
  echo $! > "$MONITOR_PID"
}

monitor_stop() {
  if [ -f "$MONITOR_PID" ] && kill -0 "$(cat "$MONITOR_PID")" 2>/dev/null; then
    kill "$(cat "$MONITOR_PID")" || true
    rm -f "$MONITOR_PID"
  fi
}

start() {
  require_root
  ensure_dirs
  if [ -f "$LOCK_FILE" ]; then exit 0; fi
  touch "$LOCK_FILE"
  install_packages
  local helper
  helper="$(detect_ssl_helper)"
  [ -n "$helper" ] || { echo "ssl helper not found"; rm -f "$LOCK_FILE"; exit 1; }
  gen_ca
  trust_ca
  local cache_dir
  cache_dir="$(cache_dir_pick)"
  write_squid_conf "$helper" "$cache_dir"
  init_ssl_db "$helper"
  squid_prepare_cache
  squid_start
  iptables_enable
  monitor_start
  echo "started"
}

stop() {
  require_root
  monitor_stop
  iptables_disable
  untrust_ca
  squid_stop
  rm -f "$LOCK_FILE"
  echo "stopped"
}

case "$ACTION" in
  start) start ;;
  stop) stop ;;
  *) echo "usage: $0 {start|stop}"; exit 1 ;;
esac
