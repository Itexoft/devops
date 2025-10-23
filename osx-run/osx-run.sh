#!/usr/bin/env bash
set -Eeuo pipefail

: "${OSX_RUN_TRACE:=1}"
: "${OSX_RUN_FORCE:=1}"
: "${SDK_VER:=latest}"

 export CXXFLAGS="${CXXFLAGS:-} -stdlib=libc++"
 export LDFLAGS="${LDFLAGS:-} -stdlib=libc++"

if [ "${OSX_RUN_TRACE:-0}" != 0 ]; then set -x; fi

die() {
 echo "$*" >&2
 exit 1
}

script_dir() {
 if cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1; then
  pwd -P
 else
  pwd -P
 fi
}

run_sudo() {
 if [ "$(id -u)" -eq 0 ]; then
  "$@"
 else
  /usr/bin/sudo "$@"
 fi
}

path_prepend_unique() {
 local d="$1"
 [ -n "$d" ] || return 0
 [ -d "$d" ] || return 0
 case ":$PATH:" in
  *":$d:"*) ;;
  *) PATH="$d:$PATH"; export PATH ;;
 esac
}

flag_append_unique() {
 local var="$1"
 local flag="$2"
 local cur="${!var-}"
 case " $cur " in
  *" $flag "*) ;;
  *)
   if [ -n "$cur" ]; then
    printf -v "$var" '%s %s' "$cur" "$flag"
   else
    printf -v "$var" '%s' "$flag"
   fi
   export "$var"
   ;;
 esac
}

ensure_apt_deps() {
 export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"
 command -v apt-get >/dev/null 2>&1 || return 0
 run_sudo apt-get update
 run_sudo apt-get install -y --no-install-recommends build-essential clang lld llvm cmake git patch python3 xz-utils curl libssl-dev liblzma-dev libxml2-dev bzip2 cpio zlib1g-dev uuid-dev ninja-build pkg-config ca-certificates file zstd libc++-dev libc++abi-dev
}

ensure_ld64_lld() {
 ensure_llvm_prebuilt

 local d="$HOME/.local/bin"
 mkdir -p "$d"

 local cand=""
 if [ -n "${LLVM_ROOT:-}" ] && [ -x "$LLVM_ROOT/current/bin/ld64.lld" ]; then
  cand="$LLVM_ROOT/current/bin/ld64.lld"
 else
  cand="$(command -v ld64.lld 2>/dev/null || true)"
 fi

 [ -n "$cand" ] && [ -x "$cand" ] || die "Required dependency 'ld64.lld' is not installed"

 ln -sf "$cand" "$d/ld64.lld"
 path_prepend_unique "$d"
 command -v ld64.lld >/dev/null 2>&1 || die "Required dependency 'ld64.lld' is not installed"
}

resolve_latest_macos_sdk_ver() {
 local eff=""
 local tag=""

 eff="$(curl -fsSL -H 'User-Agent: osx-run' -o /dev/null -w '%{url_effective}' https://github.com/joseluisq/macosx-sdks/releases/latest || true)"
 tag="${eff##*/}"

 if printf %s "$tag" | grep -Eq '^[0-9]+([.][0-9]+)*$'; then
  printf %s "$tag"
  return 0
 fi

 printf %s "26.1"
}

resolve_sdk_ver() {
 local _repo_dir="${1:-}"
 local v="${SDK_VER:-latest}"
 if [ -z "$v" ] || [ "$v" = latest ]; then
  v="$(resolve_latest_macos_sdk_ver)"
 fi
 SDK_VER="$v"
 if [ -z "${SDK_VERSION:-}" ]; then
  export SDK_VERSION="$v"
 fi
 printf %s "$v"
}

install_sdk_tarball() {
 local repo_dir="$1"
 local tarballs="$repo_dir/tarballs"
 mkdir -p "$tarballs"

 local v=""
 v="$(resolve_sdk_ver)"

 if ls "$tarballs/MacOSX${v}.sdk.tar."* >/dev/null 2>&1; then return 0; fi

 : "${XCODE_XIP:=}"
 : "${SDK_TARBALL_URL:=}"

 if [ -n "$SDK_TARBALL_URL" ]; then
  curl -fL -o "$tarballs/MacOSX${v}.sdk.tar.xz" "$SDK_TARBALL_URL" && return 0 || true
 fi

 if [ -n "$XCODE_XIP" ] && [ -f "$XCODE_XIP" ]; then
  if [ -f "$repo_dir/tools/gen_sdk_package_pbzx.sh" ]; then
   (cd "$repo_dir" && ./tools/gen_sdk_package_pbzx.sh "$XCODE_XIP")
  elif [ -f "$repo_dir/tools/gen_sdk_package.sh" ]; then
   (cd "$repo_dir" && ./tools/gen_sdk_package.sh "$XCODE_XIP")
  fi
  mv "$repo_dir"/MacOSX*.sdk.tar.* "$tarballs/" 2>/dev/null || true
 fi

 if ls "$tarballs/MacOSX${v}.sdk.tar."* >/dev/null 2>&1; then return 0; fi

 local ext=""
 local out=""
 local u=""
 local ok=""

 for ext in tar.xz tar.zst tar.gz tar.bz2; do
  out="$tarballs/MacOSX${v}.sdk.$ext"
  u="https://github.com/joseluisq/macosx-sdks/releases/download/${v}/MacOSX${v}.sdk.$ext"
  curl -fL -o "$out" "$u" && { ok=1; break; } || true
 done

 [ -n "$ok" ] && ls "$tarballs/MacOSX${v}.sdk.tar."* >/dev/null 2>&1 && return 0

 die "SDK tarball not found.
Provide XCODE_XIP or SDK_TARBALL_URL or pre-place MacOSX${v}.sdk.tar.* in $tarballs/"
}

ensure_llvm_prebuilt() {
 : "${OSX_ROOT:=/opt/osx}"
 : "${LLVM_ROOT:=$OSX_ROOT/pkgs/llvm}"
 : "${LLVM_VER:=latest}"

 local arch=""
 arch="$(uname -m)"
 local plat=""
 case "$arch" in
  x86_64|amd64) plat="Linux-X64" ;;
  aarch64|arm64) plat="Linux-ARM64" ;;
  *) die "Unsupported host arch: $arch" ;;
 esac

 local ver="$LLVM_VER"
 if [ -z "$ver" ] || [ "$ver" = latest ]; then
  local eff=""
  eff="$(curl -fsSL -H 'User-Agent: osx-run' -o /dev/null -w '%{url_effective}' https://github.com/llvm/llvm-project/releases/latest || true)"
  eff="${eff%/}"
  ver="${eff##*/}"
  ver="${ver#llvmorg-}"
  [ -n "$ver" ] || die "Failed to resolve latest LLVM version"
 fi

 local dir="$LLVM_ROOT/$ver"
 if [ -x "$dir/bin/ld64.lld" ] && [ -x "$dir/bin/clang" ]; then
  ln -sfn "$dir" "$LLVM_ROOT/current"
  path_prepend_unique "$LLVM_ROOT/current/bin"
  return 0
 fi

 mkdir -p "$LLVM_ROOT"
 local pkg="LLVM-$ver-$plat.tar.xz"
 local url="https://github.com/llvm/llvm-project/releases/download/llvmorg-$ver/$pkg"
 local tmp=""
 tmp="$(mktemp -d)"
 curl -fL "$url" -o "$tmp/$pkg"
 tar -xf "$tmp/$pkg" -C "$tmp"
 local extracted=""
 extracted="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d -name "LLVM-$ver-$plat*" | head -n1 || true)"
 [ -n "$extracted" ] || die "Failed to extract $pkg"
 mkdir -p "$dir"
 rm -rf "$dir"
 mv "$extracted" "$dir"
 rm -rf "$tmp"

 [ -x "$dir/bin/ld64.lld" ] || die "LLVM package does not contain ld64.lld: $dir"
 ln -sfn "$dir" "$LLVM_ROOT/current"
 path_prepend_unique "$LLVM_ROOT/current/bin"
}

osxcross_repo_dir() {
 : "${OSX_ROOT:=/opt/osx}"
 : "${OSXCROSS_ROOT:=$OSX_ROOT/pkgs/osxcross}"
 printf %s "$OSXCROSS_ROOT/osxcross"
}

osxcross_target_dir() {
 : "${OSX_ROOT:=/opt/osx}"
 : "${OSXCROSS_ROOT:=$OSX_ROOT/pkgs/osxcross}"
 printf %s "$OSXCROSS_ROOT/target"
}

write_activate() {
 local repo_dir="$1"
 local tgt_dir="$2"
 local desired_sdk="$3"

 local osxcross_root=""
 osxcross_root="$(cd "$(dirname "$repo_dir")" >/dev/null 2>&1 && pwd -P)"

 local env_dir="$osxcross_root/env"
 local toolchains_dir="$osxcross_root/toolchains"
 local activate="$env_dir/activate"
 local toolchain="$toolchains_dir/darwin-arm64.cmake"

 mkdir -p "$env_dir" "$toolchains_dir"

 cat > "$activate" <<EOF
case ":\$PATH:" in
 *":$tgt_dir/bin:"*) ;;
 *) export PATH="$tgt_dir/bin:\$PATH" ;;
esac

export SDK_VERSION="$desired_sdk"
export SDKROOT="$tgt_dir/SDK/MacOSX\${SDK_VERSION}.sdk"
export MACOSX_DEPLOYMENT_TARGET="\${MACOSX_DEPLOYMENT_TARGET:-${DEPLOY_MIN:-11.0}}"

export CC="xcrun clang"
export CXX="xcrun clang++"

export CFLAGS="\${CFLAGS:-} -mmacos-version-min=\$MACOSX_DEPLOYMENT_TARGET"
export CXXFLAGS="\${CXXFLAGS:-} -stdlib=libc++ -mmacos-version-min=\$MACOSX_DEPLOYMENT_TARGET"
export LDFLAGS="\${LDFLAGS:-} -stdlib=libc++"
EOF

 cat > "$toolchain" <<'EOF'
set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_PROCESSOR arm64)
set(CMAKE_OSX_ARCHITECTURES arm64)
set(CMAKE_OSX_DEPLOYMENT_TARGET $ENV{MACOSX_DEPLOYMENT_TARGET})
set(CMAKE_OSX_SYSROOT $ENV{SDKROOT})
set(CMAKE_C_COMPILER xcrun)
set(CMAKE_C_COMPILER_ARG1 clang)
set(CMAKE_CXX_COMPILER xcrun)
set(CMAKE_CXX_COMPILER_ARG1 clang++)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
EOF

 for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [ -f "$rc" ] || continue
  grep -q "$activate" "$rc" || printf "%s\n" "test -f $activate && . $activate" >> "$rc"
 done
}

ensure_sdk_extracted() {
 local repo_dir="$1"
 local tgt_dir="$2"

 local v=""
 v="$(resolve_sdk_ver)"

 local tarballs="$repo_dir/tarballs"
 local sdk_root="$tgt_dir/SDK"
 local tb=""

 tb="$(ls -1 "$tarballs/MacOSX${v}.sdk.tar."* 2>/dev/null | head -n1 || true)"
 [ -n "$tb" ] || die "SDK tarball is missing for version '$v' in $tarballs/"

 mkdir -p "$sdk_root"

 if [ "${OSX_RUN_FORCE:-0}" = 0 ] && [ -d "$sdk_root/MacOSX${v}.sdk" ]; then return 0; fi
 if [ "${OSX_RUN_FORCE:-0}" != 0 ]; then
  rm -rf "$sdk_root/MacOSX${v}.sdk" 2>/dev/null || true
 fi

 case "$tb" in
  *.tar.zst)
   if tar --help 2>/dev/null | grep -q -- '--zstd'; then
    tar --zstd -xf "$tb" -C "$sdk_root"
   else
    zstd -dc "$tb" | tar -xf - -C "$sdk_root"
   fi
   ;;
  *)
   tar -xf "$tb" -C "$sdk_root"
   ;;
 esac

 if [ ! -d "$sdk_root/MacOSX${v}.sdk" ]; then
  local p=""
  p="$(ls -1d "$sdk_root"/MacOSX*.sdk 2>/dev/null | sort -Vr | head -n1 || true)"
  [ -n "$p" ] || die "SDK extraction failed: no MacOSX*.sdk found under $sdk_root/"
 fi
}

install_xcrun_bootstrap() {
 local tgt_dir="$1"
 mkdir -p "$tgt_dir/bin"

 cat > "$tgt_dir/bin/xcrun" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

tgt_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd -P)"

pick_sdk() {
 local p=""
 p="$(ls -1d "$tgt_dir/SDK"/MacOSX*.sdk 2>/dev/null | sort -Vr | head -n1 || true)"
 [ -n "$p" ] || return 1
 printf %s "$p"
}

sdk_path=""
sdk_path="$(pick_sdk 2>/dev/null || true)"

sdk_ver=""
if [ -n "$sdk_path" ]; then
 sdk_ver="$(printf %s "$sdk_path" | sed -E 's|.*/MacOSX([0-9.]+)[.]sdk$|\1|')"
fi

resolve_sdkroot() {
 local p="${SDKROOT:-}"
 if [ -n "$p" ] && [ -d "$p" ]; then
  printf %s "$p"
  return 0
 fi
 [ -n "$sdk_path" ] && [ -d "$sdk_path" ] || return 1
 printf %s "$sdk_path"
}

args=("$@")
i=0
while [ $i -lt ${#args[@]} ]; do
 case "${args[$i]}" in
  -sdk|--sdk)
   if [ $((i+1)) -lt ${#args[@]} ]; then
    i=$((i+2))
    continue
   fi
   ;;
  --show-sdk-path)
   resolve_sdkroot || exit 1
   exit 0
   ;;
  --show-sdk-version)
   [ -n "$sdk_ver" ] || exit 1
   printf %s "$sdk_ver"
   exit 0
   ;;
  --show-sdk-platform-path)
   resolve_sdkroot >/dev/null 2>&1 || exit 1
   printf %s "$tgt_dir/SDK"
   exit 0
   ;;
  -find|--find|-f)
   if [ $((i+1)) -lt ${#args[@]} ]; then
    tool="${args[$((i+1))]}"
    if [ -x "$tgt_dir/bin/$tool" ]; then
     printf %s "$tgt_dir/bin/$tool"
     exit 0
    fi
    command -v "$tool" >/dev/null 2>&1 && { command -v "$tool"; exit 0; }
    exit 1
   fi
   ;;
 esac
 break
done

tool="${args[$i]:-}"
[ -n "$tool" ] || exit 1
rest=("${args[@]:$((i+1))}")

arch=""
for ((j=0;j<${#rest[@]};j++)); do
 if [ "${rest[$j]}" = "-arch" ] && [ $((j+1)) -lt ${#rest[@]} ]; then
  arch="${rest[$((j+1))]}"
  break
 fi
done

has_target=""
has_isysroot=""
for ((j=0;j<${#rest[@]};j++)); do
 case "${rest[$j]}" in
  --target=*|-target|--target) has_target=1 ;;
  -isysroot) has_isysroot=1 ;;
 esac
done

min_ver="${MACOSX_DEPLOYMENT_TARGET:-${OSX_VERSION_MIN:-}}"

if [ "$tool" = clang ] || [ "$tool" = clang++ ]; then
 if [ -n "$arch" ]; then
  prefix="oa64"
  if [ "$arch" = x86_64 ]; then prefix="o64"; fi
  if [ -x "$tgt_dir/bin/${prefix}-${tool}" ]; then
   exec "$tgt_dir/bin/${prefix}-${tool}" "${rest[@]}"
  fi
 fi

 if [ -n "$arch" ] || [ -n "$has_target" ] || [ -n "$has_isysroot" ]; then
  sdkroot=""
  sdkroot="$(resolve_sdkroot 2>/dev/null || true)"
  extra=()
  if [ -n "$arch" ] && [ -z "$has_target" ]; then
   triple="arm64-apple-darwin"
   if [ "$arch" = x86_64 ]; then triple="x86_64-apple-darwin"; fi
   extra+=( "--target=$triple" )
  fi
  if [ -n "$sdkroot" ] && [ -d "$sdkroot" ] && [ -z "$has_isysroot" ]; then
   extra+=( "-isysroot" "$sdkroot" )
  fi
  [ -n "$min_ver" ] && extra+=( "-mmacos-version-min=$min_ver" )
  command -v ld64.lld >/dev/null 2>&1 && extra+=( "-fuse-ld=lld" )
  exec "$tool" "${extra[@]}" "${rest[@]}"
 fi

 exec "$tool" "${rest[@]}"
fi

if [ -x "$tgt_dir/bin/$tool" ]; then
 exec "$tgt_dir/bin/$tool" "${rest[@]}"
fi

exec "$tool" "${rest[@]}"
EOF

 chmod +x "$tgt_dir/bin/xcrun"
}

ensure_xcrun() {
 local repo_dir="$1"
 local tgt_dir="$2"

 mkdir -p "$tgt_dir/bin"
 path_prepend_unique "$tgt_dir/bin"

 if [ ! -x "$tgt_dir/bin/xcrun" ] || [ "${OSX_RUN_FORCE:-0}" != 0 ]; then
  install_xcrun_bootstrap "$tgt_dir"
 fi

 [ -x "$tgt_dir/bin/xcrun" ] || die "Required dependency 'xcrun' is not installed"

 local p=""
 p="$(xcrun --show-sdk-path 2>/dev/null || true)"
 [ -n "$p" ] && [ -d "$p" ] || die "xcrun exists but can't locate SDK. Expected $tgt_dir/SDK/MacOSX*.sdk"

 local c=""
 local rel=""
 for c in "${candidates[@]}"; do
  [ -f "$c" ] || continue
  rel="${c#"$repo_dir/"}"
  if [ "$rel" != "$c" ]; then
   (cd "$repo_dir" && UNATTENDED=1 TARGET_DIR="$tgt_dir" TARGETDIR="$tgt_dir" bash "./$rel") || true
  else
   (cd "$repo_dir" && UNATTENDED=1 TARGET_DIR="$tgt_dir" TARGETDIR="$tgt_dir" bash "$c") || true
  fi
 done

 [ -x "$tgt_dir/bin/xcrun" ] || die "Required dependency 'xcrun' is not installed"

 local p=""
 p="$(xcrun --show-sdk-path 2>/dev/null || true)"
 [ -n "$p" ] && [ -d "$p" ] || die "xcrun exists but can't locate SDK. Expected $tgt_dir/SDK/MacOSX*.sdk"
}

install_osxcross() {
 local sd=""
 sd="$(script_dir)"

 : "${OSX_ROOT:=/opt/osx}"
 : "${OSXCROSS_ROOT:=$OSX_ROOT/pkgs/osxcross}"
 : "${OSXCROSS_BRANCH:=2.0-llvm-based}"
 : "${OSXCROSS_REPO:=https://github.com/tpoechtrager/osxcross.git}"
 : "${DEPLOY_MIN:=26.0}"
 : "${ARCHES:=arm64}"
 : "${OSX_RUN_SKIP_SHELL:=1}"

 ensure_apt_deps
 ensure_ld64_lld

 run_sudo mkdir -p "$OSXCROSS_ROOT"
 run_sudo chown "$(id -u):$(id -g)" "$OSXCROSS_ROOT"

 local repo_dir=""
 repo_dir="$(osxcross_repo_dir)"

 local tgt_dir=""
 tgt_dir="$(osxcross_target_dir)"

 if [ ! -d "$repo_dir/.git" ]; then
  rm -rf "$repo_dir"
  git clone --depth 1 --branch "$OSXCROSS_BRANCH" "$OSXCROSS_REPO" "$repo_dir"
 else
  git -C "$repo_dir" fetch --depth 1 origin "$OSXCROSS_BRANCH"
  git -C "$repo_dir" checkout -f "$OSXCROSS_BRANCH"
  git -C "$repo_dir" reset --hard "origin/$OSXCROSS_BRANCH"
 fi

 mkdir -p "$repo_dir/tarballs"

 local desired_sdk="$(resolve_sdk_ver "$repo_dir")"
 export SDK_VERSION="$desired_sdk"

 local tool_ok=""
 if [ -x "$tgt_dir/bin/xcrun" ] && [ -x "$tgt_dir/bin/oa64-clang" ] && [ -x "$tgt_dir/bin/o64-clang" ]; then
  tool_ok=1
 fi

 local sdk_ok=""
 if [ -d "$tgt_dir/SDK/MacOSX${desired_sdk}.sdk" ]; then
  sdk_ok=1
 fi

if [ -n "$tool_ok" ] && [ -n "$sdk_ok" ] && [ "${OSX_RUN_FORCE:-0}" = 0 ]; then
 write_activate "$repo_dir" "$tgt_dir" "$desired_sdk"
 return 0
fi

install_sdk_tarball "$repo_dir"
ensure_sdk_extracted "$repo_dir" "$tgt_dir"
ensure_xcrun "$repo_dir" "$tgt_dir"

cd "$repo_dir"
 UNATTENDED=1 ENABLE_ARCHS="$ARCHES" SUPPORTED_ARCHS="$ARCHES" SDK_VERSION="$desired_sdk" TARGET_DIR="$tgt_dir" TARGETDIR="$tgt_dir" OSX_VERSION_MIN="$DEPLOY_MIN" ./build.sh

 write_activate "$repo_dir" "$tgt_dir" "$desired_sdk"

 local t="$tgt_dir/.osxrun_test"
 rm -rf "$t"
 mkdir -p "$t"
 printf '%s\n' 'int main(){return 0;}' > "$t/t.c"
 SDKROOT="$tgt_dir/SDK/MacOSX${desired_sdk}.sdk" xcrun clang -arch "$ARCHES" -mmacos-version-min="$DEPLOY_MIN" -o "$t/t" "$t/t.c" >/dev/null 2>&1 || true
}

pick_latest_dir() {
 local b="$1"
 [ -d "$b" ] || { echo ""; return 0; }
 find "$b" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort -Vr | head -n1
}

install_python() {
 : "${OSX_ROOT:=/opt/osx}"
 local ver="${1:-3.11}"
 local fv="$ver"
 local lst=""
 lst="$(curl -fsL https://www.python.org/ftp/python/ || true)"

 case "$ver" in
  *.*.*) fv="$ver" ;;
  *.*)
   fv=""
   local cand=""
   for cand in $(printf '%s\n' "$lst" | grep -o "${ver}[.][0-9][0-9]*" | sort -Vr); do
    curl -fsI "https://www.python.org/ftp/python/$cand/python-$cand-macos11.pkg" >/dev/null 2>&1 && { fv="$cand"; break; }
   done
   [ -n "$fv" ] || fv="$ver.0"
   ;;
  *)
   fv=""
   local mv=""
   for mv in $(printf '%s\n' "$lst" | grep -o "${ver}[.][0-9][0-9]*" | sort -Vr); do
    local cand=""
    for cand in $(printf '%s\n' "$lst" | grep -o "${mv}[.][0-9][0-9]*" | sort -Vr); do
     curl -fsI "https://www.python.org/ftp/python/$cand/python-$cand-macos11.pkg" >/dev/null 2>&1 && { fv="$cand"; break 2; }
    done
   done
   [ -n "$fv" ] || fv="$ver.0"
   ;;
 esac

 local dir="$OSX_ROOT/pkgs/python/$fv"
 if [ ! -x "$dir/bin/python3" ]; then
  command -v 7z >/dev/null 2>&1 || run_sudo apt-get install -y p7zip-full
  command -v bsdtar >/dev/null 2>&1 || run_sudo apt-get install -y libarchive-tools

  mkdir -p "$(dirname "$dir")"

  local tmp=""
  tmp="$(mktemp -d)"

  curl -fL "https://www.python.org/ftp/python/$fv/python-$fv-macos11.pkg" -o "$tmp/pkg"
  7z x "$tmp/pkg" -o"$tmp" >/dev/null
  rm -rf "$tmp/Resources"
  bsdtar -xf "$tmp/Python_Framework.pkg/Payload" -C "$tmp"
  mv "$tmp/Versions/${fv%.*}" "$dir"
  ln -sf "$dir/bin/python3" "$dir/bin/python"
  rm -rf "$tmp"
 fi

 ln -sfn "$dir" "$OSX_ROOT/pkgs/python/current"
}

install_node() {
 : "${OSX_ROOT:=/opt/osx}"
 : "${DEFAULT_ARCH:=arm64}"
 local ver="${1:-22}"

 local fv=""
 fv="$(curl -fsL https://nodejs.org/dist/index.json | grep -o "v${ver}[0-9.]*" | head -n1 | tr -d v || true)"
 [ -n "$fv" ] || die "Failed to resolve Node.js version for major '$ver'"

 local dir="$OSX_ROOT/pkgs/node/$fv"
 if [ ! -x "$dir/bin/node" ]; then
  mkdir -p "$dir"

  local tmp=""
  tmp="$(mktemp -d)"

  curl -fL "https://nodejs.org/dist/v$fv/node-v$fv-darwin-$DEFAULT_ARCH.tar.gz" -o "$tmp/node.tar.gz"
  tar -xzf "$tmp/node.tar.gz" -C "$dir" --strip-components 1
  rm -rf "$tmp"
 fi

 ln -sfn "$dir" "$OSX_ROOT/pkgs/node/current"
}

main() {
 if [ "${1:-}" = install ] && [ "${2:-}" = osxcross ]; then
  install_osxcross
  exit 0
 fi

 if [ "${1:-}" = install ] && [ "${2:-}" = python ]; then
  install_python "${3:-3.11}"
  exit 0
 fi

 if [ "${1:-}" = install ] && [ "${2:-}" = node ]; then
  install_node "${3:-22}"
  exit 0
 fi

 : "${OSX_ROOT:=/opt/osx}"
 : "${DEFAULT_ARCH:=arm64}"
 : "${DEFAULT_DEPLOY_MIN:=11.0}"

 local osxcross_tgt="$OSX_ROOT/pkgs/osxcross/target"
 local sdk_guess=""
 if [ -d "$osxcross_tgt/SDK" ]; then
  sdk_guess="$(ls -1d "$osxcross_tgt/SDK"/MacOSX*.sdk 2>/dev/null | sed -E 's|.*/MacOSX([0-9.]+)[.]sdk$|\1|' | sort -Vr | head -n1 || true)"
 fi
 : "${DEFAULT_SDK_VER:=${sdk_guess:-26.1}}"

 local sdk_major="${DEFAULT_SDK_VER%%.*}"
 local platform="macosx_${sdk_major}_0_${DEFAULT_ARCH}"
 local wheelhouse="$OSX_ROOT/wheelhouse/$platform"
 local sitedir="$OSX_ROOT/site-$platform"
 export WHEELHOUSE="$wheelhouse"

 local py_home=""
 if [ -L "$OSX_ROOT/pkgs/python/current" ]; then
  py_home="$OSX_ROOT/pkgs/python/current"
 else
  local pv=""
  pv="$(pick_latest_dir "$OSX_ROOT/pkgs/python")"
  [ -n "$pv" ] && py_home="$OSX_ROOT/pkgs/python/$pv"
 fi

 local node_home=""
 if [ -L "$OSX_ROOT/pkgs/node/current" ]; then
  node_home="$OSX_ROOT/pkgs/node/current"
 else
  local nv=""
  nv="$(pick_latest_dir "$OSX_ROOT/pkgs/node")"
  [ -n "$nv" ] && node_home="$OSX_ROOT/pkgs/node/$nv"
 fi

 [ -d "$osxcross_tgt/bin" ] && path_prepend_unique "$osxcross_tgt/bin"
 [ -n "$node_home" ] && path_prepend_unique "$node_home/bin"
 [ -n "$py_home" ] && path_prepend_unique "$py_home/bin"
 path_prepend_unique "$OSX_ROOT/bin"

 export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-$DEFAULT_DEPLOY_MIN}"
 if command -v xcrun >/dev/null 2>&1; then
  local sdkroot_val=""
  sdkroot_val="$(xcrun --show-sdk-path 2>/dev/null || true)"
  [ -n "$sdkroot_val" ] && export SDKROOT="$sdkroot_val"
 fi

 if [ -n "$py_home" ]; then
  if [ -f "$OSX_ROOT/env/pip-macos.conf" ]; then
   export PIP_CONFIG_FILE="$OSX_ROOT/env/pip-macos.conf"
  fi
  export PYTHONNOUSERSITE=1
  export PYTHONPATH="$sitedir${PYTHONPATH:+:$PYTHONPATH}"
 fi

 if [ -n "$node_home" ]; then
  export npm_config_platform=darwin
  export npm_config_arch="$DEFAULT_ARCH"
  export npm_config_target_arch="$DEFAULT_ARCH"
  [ -n "$py_home" ] && export npm_config_python="$py_home/bin/python"
 fi

 export CC="${CC:-xcrun clang}"
 export CXX="${CXX:-xcrun clang++}"
 flag_append_unique CFLAGS "-mmacos-version-min=$MACOSX_DEPLOYMENT_TARGET"
 flag_append_unique CXXFLAGS "-stdlib=libc++"
 flag_append_unique CXXFLAGS "-mmacos-version-min=$MACOSX_DEPLOYMENT_TARGET"
 flag_append_unique LDFLAGS "-stdlib=libc++"

 if [ "$#" -eq 0 ]; then
  local d=""
  d="$(script_dir)"
  case ":$PATH:" in
   *":$d:"*) ;;
   *)
    PATH="$d:$PATH"
    export PATH
    local rc=""
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
     grep -q "export PATH=\"$d:\$PATH\"" "$rc" 2>/dev/null || printf "export PATH=\"%s:\$PATH\"\n" "$d" >> "$rc"
    done
    ;;
  esac
  hash -r || true
  exit 0
 fi

 hash -r || true
 exec "$@"
}

main "$@"