#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

cert="${SIGN_CERT-}"
pass="${SIGN_PASSWORD-}"
args=()
outdir=""

while [ $# -gt 0 ]; do
  case "${1-}" in
    --cert=*) cert="${1#*=}"; [ -z "$cert" ] && { echo "missing value for --cert" >&2; exit 2; }; shift;;
    --password=*) pass="${1#*=}"; shift;;
    -o|--output) [ $# -ge 2 ] || { echo "missing value for $1" >&2; exit 2; }; outdir="$2"; args+=("$1" "$2"); shift 2;;
    -o=*|--output=*) v="${1#*=}"; outdir="$v"; args+=("$1"); shift;;
    *) args+=("$1"); shift;;
  esac
done

[ ${#args[@]} -ge 1 ] || { echo "usage: dotnet-sign-publish.sh [dotnet publish args or binaries ...] [--cert X509] [--password=PASS]" >&2; exit 2; }
[ -n "${cert// }" ] || { echo "missing --cert or SIGN_CERT" >&2; exit 2; }

command -v curl >/dev/null 2>&1 || { echo "missing curl" >&2; exit 2; }

have() { command -v "$1" >/dev/null 2>&1; }
die() { printf 'error: %s\n' "$1" >&2; [ -n "${ERR-}" ] && [ -s "$ERR" ] && cat "$ERR" >&2; exit "${2-1}"; }
warn() { printf 'warn: %s\n' "$1" >&2; }
info() { printf '%s\n' "$1"; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT SIGTERM
ERR="$tmp/err.txt"; : >"$ERR"

GH="$tmp/gh-pick.sh" && curl -fsSL "https://raw.githubusercontent.com/Itexoft/devops/refs/heads/master/gh-pick.sh" -o "$GH" && chmod +x "$GH"
CCR="$("$GH" "@master" "lib/cert-converter.sh")"
SIGN="$("$GH" "@master" "lib/sign-tool.sh")"
[ -n "$CCR" ] || die "gh-pick failed: cert-converter.sh"
[ -n "$SIGN" ] || die "gh-pick failed: sign-tool.sh"

TS_PRIMARY="${TIMESTAMPER:-https://timestamp.digicert.com}"
TS_FALLBACK="${TIMESTAMPER_FALLBACK:-http://timestamp.sectigo.com}"

certfile="$tmp/cert.input"
if [ -f "$cert" ]; then
  cp "$cert" "$certfile"
else
  printf '%s' "$cert" >"$certfile"
fi
chmod 600 "$certfile"

PFX="$tmp/cert.pfx"
cmd=( "$CCR" "$certfile" pfx "$PFX" )
[ -n "$pass" ] && cmd+=( "--password=$pass" )
"${cmd[@]}" >/dev/null 2>&1 || die "certificate conversion to PFX failed"
[ -s "$PFX" ] || die "empty PFX produced"

SNK="$tmp/strongname.snk"
cmd=( "$CCR" "$certfile" snk "$SNK" )
[ -n "$pass" ] && cmd+=( "--password=$pass" )
"${cmd[@]}" >/dev/null 2>&1 || die "certificate conversion to SNK failed"
[ -s "$SNK" ] || die "empty SNK produced"

if [ -z "$outdir" ]; then
  for a in "${args[@]}"; do
    case "$a" in
      -p:PublishDir=*|/p:PublishDir=*) outdir="${a#*=}";;
      -property:PublishDir=*|/property:PublishDir=*) outdir="${a#*=}";;
    esac
  done
fi

stamp="$tmp/stamp"; : >"$stamp"
bins=()

is_bin_arg=0
for a in "${args[@]}"; do
  case "$a" in
    *.dll|*.exe|*.dylib|*.so|*.so.*|*.msi|*.msix|*.appx|*.msp|*.msm|*.cab|*.cat|*.wasm) is_bin_arg=1;;
    *)
      if [ -f "$a" ]; then
        case "$a" in
          *.csproj|*.sln) ;;
          *)
            if have file; then
              t="$(file -b "$a" 2>>"$ERR" || true)"
              printf '%s\n' "$t" | grep -qiE 'mach-o|pe32|elf' && is_bin_arg=1
            fi
          ;;
        esac
      fi
    ;;
  esac
done

if [ "$is_bin_arg" -eq 1 ]; then
  for a in "${args[@]}"; do
    [ -f "$a" ] && bins+=("$(cd "$(dirname "$a")" && pwd -P)/$(basename "$a")")
  done
else
  command -v dotnet >/dev/null 2>&1 || die "missing dotnet"

  extra_msbuild=(
    "-p:SignAssembly=true"
    "-p:PublicSign=false"
    "-p:AssemblyOriginatorKeyFile=$SNK"
  )

  DOTNET_CLI_UI_LANGUAGE=en dotnet publish "${args[@]}" "${extra_msbuild[@]}" 2>>"$ERR" || die "dotnet publish failed"

  searchdir="."
  [ -n "$outdir" ] && searchdir="$outdir"

  list="$tmp/.targets.all"; : >"$list"

  if have file; then
    while IFS= read -r -d '' f; do
      t="$(file -b "$f" 2>>"$ERR" || true)"
      printf '%s\n' "$t" | grep -qiE 'mach-o|pe32|elf' && printf '%s\n' "$f" >>"$list"
    done < <(find "$searchdir" -type f -not -path '*/obj/*' -not -path '*/.nuget/*' -newer "$stamp" -print0 2>/dev/null || true)
  fi

  find "$searchdir" -type f -not -path '*/obj/*' -not -path '*/.nuget/*' \( -name '*.dll' -o -name '*.exe' -o -name '*.dylib' -o -name '*.dylib.*' -o -name '*.so' -o -name '*.so.*' -o -name '*.msi' -o -name '*.msix' -o -name '*.appx' -o -name '*.msp' -o -name '*.msm' -o -name '*.cab' -o -name '*.cat' -o -name '*.wasm' \) -newer "$stamp" -print 2>/dev/null >>"$list" || true

  uniq="$tmp/.targets.uniq"
  awk '!seen[$0]++' "$list" >"$uniq" 2>>"$ERR" || true
  while IFS= read -r f; do [ -n "$f" ] && bins+=("$f"); done < "$uniq"

  if [ "${#bins[@]}" -eq 0 ]; then
    : >"$list"

    if have file; then
      while IFS= read -r -d '' f; do
        t="$(file -b "$f" 2>>"$ERR" || true)"
        printf '%s\n' "$t" | grep -qiE 'mach-o|pe32|elf' && printf '%s\n' "$f" >>"$list"
      done < <(find "$searchdir" -type f -not -path '*/obj/*' -not -path '*/.nuget/*' -print0 2>/dev/null || true)
    fi

    find "$searchdir" -type f -not -path '*/obj/*' -not -path '*/.nuget/*' \( -name '*.dll' -o -name '*.exe' -o -name '*.dylib' -o -name '*.dylib.*' -o -name '*.so' -o -name '*.so.*' -o -name '*.msi' -o -name '*.msix' -o -name '*.appx' -o -name '*.msp' -o -name '*.msm' -o -name '*.cab' -o -name '*.cat' -o -name '*.wasm' \) -print 2>/dev/null >>"$list" || true

    awk '!seen[$0]++' "$list" >"$uniq" 2>>"$ERR" || true
    while IFS= read -r f; do [ -n "$f" ] && bins+=("$f"); done < "$uniq"
  fi
fi

[ "${#bins[@]}" -gt 0 ] || die "no binaries found"

signed=0 failed=0
for p in "${bins[@]}"; do
  [ -f "$p" ] || { warn "missing binary: $p"; failed=$((failed+1)); continue; }
  if "$SIGN" "$PFX" "$p" "--password=$pass"; then
    signed=$((signed+1))
  else
    failed=$((failed+1))
  fi
done

info "summary: signed=$signed failed=$failed"
exit $([ "$failed" -gt 0 ] && echo 2 || echo 0)
