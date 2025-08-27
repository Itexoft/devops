#!/usr/bin/env bash
set -e

OSX_ROOT="${OSX_ROOT:-/opt/osx}"
DEFAULT_ARCH="${DEFAULT_ARCH:-arm64}"
DEFAULT_SDK_VER="${DEFAULT_SDK_VER:-15.5}"
DEFAULT_DEPLOY_MIN="${DEFAULT_DEPLOY_MIN:-11.0}"
OSXCROSS_REPO="${OSXCROSS_REPO:-https://github.com/tpoechtrager/osxcross.git}"
OSXCROSS_BRANCH="${OSXCROSS_BRANCH:-2.0-llvm-based}"
NODE_BASE_URL="${NODE_BASE_URL:-https://nodejs.org/dist}"
PYENV_REPO="${PYENV_REPO:-https://github.com/pyenv/pyenv.git}"
APT_OSXCROSS="${APT_OSXCROSS:-build-essential clang lld cmake git patch python3 python3-venv xz-utils curl libssl-dev liblzma-dev libxml2-dev bzip2 cpio zlib1g-dev uuid-dev ninja-build pkg-config ca-certificates file}"
APT_PYBUILD="${APT_PYBUILD:-build-essential make gcc libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev libffi-dev uuid-dev liblzma-dev tk-dev xz-utils curl ca-certificates}"
LLD_CANDIDATES="${LLD_CANDIDATES:-$(command -v ld64.lld || true) /usr/bin/ld64.lld-* /usr/lib/llvm-*/bin/ld64.lld /usr/bin/ld.lld /usr/lib/llvm-*/bin/ld.lld}"

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd -P || pwd -P)}"
cd "$SCRIPT_DIR"
CACHE_DIR="$SCRIPT_DIR/cache"
mkdir -p "$CACHE_DIR"

ensure_dirs() {
  /usr/bin/sudo mkdir -p "$OSX_ROOT"
  /usr/bin/sudo chown "$(id -u)":"$(id -g)" "$OSX_ROOT"
  mkdir -p "$OSX_ROOT/bin" "$OSX_ROOT/env" "$OSX_ROOT/shims" "$OSX_ROOT/pkgs" "$OSX_ROOT/cache"
}

write_config() {
  cat > "$OSX_ROOT/env/config.sh" <<EOF
OSX_ROOT="$OSX_ROOT"
DEFAULT_ARCH="$DEFAULT_ARCH"
DEFAULT_SDK_VER="$DEFAULT_SDK_VER"
DEFAULT_DEPLOY_MIN="$DEFAULT_DEPLOY_MIN"
OSXCROSS_REPO="$OSXCROSS_REPO"
OSXCROSS_BRANCH="$OSXCROSS_BRANCH"
NODE_BASE_URL="$NODE_BASE_URL"
PYENV_REPO="$PYENV_REPO"
EOF
}

write_pathrc() {
  cat > "$OSX_ROOT/env/pathrc.sh" <<'EOF'
osx_path_prepend_unique() {
  p="$1"
  case ":$PATH:" in *":$p:"*) PATH="$(printf "%s" "$PATH" | awk -v RS=: -v ORS=: -v keep="$p" '!seen[$0]++ && $0!=keep{out=out $0 ":"} END{print keep ":" out}' | sed 's/:$//')" ;; *) PATH="$p:$PATH" ;; esac
  export PATH
}
osx_path_prepend_unique "$OSX_ROOT/bin"
EOF
}

write_cnf_hooks() {
  cat > "$OSX_ROOT/env/cnf.bash" <<'EOF'
command_not_found_handle() {
  case "$1" in
    osx-*) if [ -x "$OSX_ROOT/shims/osx-shimgen" ]; then "$OSX_ROOT/shims/osx-shimgen" "${1#osx-}" >/dev/null 2>&1 && exec "$@"; fi ;;
  esac
  return 127
}
EOF
  cat > "$OSX_ROOT/env/cnf.zsh" <<'EOF'
command_not_found_handler() {
  case "$1" in
    osx-*) if [ -x "$OSX_ROOT/shims/osx-shimgen" ]; then "$OSX_ROOT/shims/osx-shimgen" "${1#osx-}" >/dev/null 2>&1 && exec "$@"; fi ;;
  esac
  return 127
}
EOF
}

inject_shell_rc() {
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] || continue
    grep -qF "$OSX_ROOT/env/pathrc.sh" "$rc" || printf '%s\n' '[ -f "'"$OSX_ROOT"'/env/pathrc.sh" ] && . "'"$OSX_ROOT"'/env/pathrc.sh"' >> "$rc"
    case "$rc" in
      *bashrc) grep -qF "$OSX_ROOT/env/cnf.bash" "$rc" || printf '%s\n' '[ -f "'"$OSX_ROOT"'/env/cnf.bash" ] && . "'"$OSX_ROOT"'/env/cnf.bash"' >> "$rc" ;;
      *zshrc) grep -qF "$OSX_ROOT/env/cnf.zsh" "$rc" || printf '%s\n' '[ -f "'"$OSX_ROOT"'/env/cnf.zsh" ] && . "'"$OSX_ROOT"'/env/cnf.zsh"' >> "$rc" ;;
    esac
  done
}

platform_vars() {
  SDK_MAJOR="${DEFAULT_SDK_VER%%.*}"
  PLATFORM="macosx_${SDK_MAJOR}_0_${DEFAULT_ARCH}"
  WHEELHOUSE="$OSX_ROOT/wheelhouse/$PLATFORM"
  SITEDIR="$OSX_ROOT/site-$PLATFORM"
  mkdir -p "$WHEELHOUSE" "$SITEDIR"
  cat > "$OSX_ROOT/env/pip-macos.conf" <<EOF
[global]
no-index = true
find-links = $WHEELHOUSE
target = $SITEDIR
EOF
}

write_dispatch() {
  cat > "$OSX_ROOT/shims/osx-dispatch" <<'EOF'
#!/usr/bin/env bash
set -e
OSX_ROOT="${OSX_ROOT:-/opt/osx}"
[ -f "$OSX_ROOT/env/config.sh" ] && . "$OSX_ROOT/env/config.sh"
SDK_MAJOR="${DEFAULT_SDK_VER%%.*}"
PLATFORM="macosx_${SDK_MAJOR}_0_${DEFAULT_ARCH}"
WHEELHOUSE="$OSX_ROOT/wheelhouse/$PLATFORM"
SITEDIR="$OSX_ROOT/site-$PLATFORM"
cmd="$(basename "$0")"
sub="${cmd#osx-}"
[ "$sub" != "$cmd" ] || { echo "$cmd: bad invoke"; exit 127; }
osx_env() {
  [ -f "$OSX_ROOT/env/osxcross-activate.sh" ] && . "$OSX_ROOT/env/osxcross-activate.sh"
}
pick_latest_dir() {
  b="$1"
  [ -d "$b" ] || { echo ""; return 0; }
  find "$b" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort -Vr | head -n1
}
py_root() {
  if [ -L "$OSX_ROOT/pkgs/python/current" ]; then echo "$OSX_ROOT/pkgs/python/current"; return 0; fi
  v="$(pick_latest_dir "$OSX_ROOT/pkgs/python")"
  [ -n "$v" ] && echo "$OSX_ROOT/pkgs/python/$v" || echo ""
}
node_root() {
  if [ -L "$OSX_ROOT/pkgs/node/current" ]; then echo "$OSX_ROOT/pkgs/node/current"; return 0; fi
  v="$(pick_latest_dir "$OSX_ROOT/pkgs/node")"
  [ -n "$v" ] && echo "$OSX_ROOT/pkgs/node/$v" || echo ""
}
run_python() {
  osx_env
  PYDIR="$(py_root)"
  [ -n "$PYDIR" ] || { echo "python not installed"; exit 127; }
  export PIP_CONFIG_FILE="$OSX_ROOT/env/pip-macos.conf"
  export PYTHONNOUSERSITE=1
  export PYTHONPATH="$SITEDIR${PYTHONPATH:+:$PYTHONPATH}"
  exec "$PYDIR/bin/python" "$@"
}
run_pip() {
  osx_env
  PYDIR="$(py_root)"
  [ -n "$PYDIR" ] || { echo "python not installed"; exit 127; }
  export PIP_CONFIG_FILE="$OSX_ROOT/env/pip-macos.conf"
  export PYTHONNOUSERSITE=1
  exec "$PYDIR/bin/pip" "$@"
}
run_node() {
  osx_env
  NDIR="$(node_root)"
  [ -n "$NDIR" ] || { echo "node not installed"; exit 127; }
  export npm_config_platform=darwin
  export npm_config_arch="$DEFAULT_ARCH"
  export npm_config_target_arch="$DEFAULT_ARCH"
  export npm_config_os=darwin
  PYDIR="$(py_root)"
  [ -n "$PYDIR" ] && export npm_config_python="$PYDIR/bin/python"
  case "$sub" in
    node|npm|npx|corepack) exec "$NDIR/bin/$sub" "$@" ;;
  esac
}
osx_env
case "$sub" in
  python|python3) run_python "$@" ;;
  pip|pip3) run_pip "$@" ;;
  node|npm|npx|corepack) run_node "$@" ;;
  *) if command -v xcrun >/dev/null 2>&1 && xcrun -find "$sub" >/dev/null 2>&1; then exec xcrun "$sub" "$@"; fi
     t="$(ls "$OSX_ROOT/pkgs/osxcross/target/bin"/*-clang 2>/dev/null | head -n1 | xargs -r -n1 basename | sed 's/-clang$//')"
     if [ -n "$t" ] && [ -x "$OSX_ROOT/pkgs/osxcross/target/bin/$t-$sub" ]; then exec "$OSX_ROOT/pkgs/osxcross/target/bin/$t-$sub" "$@"; fi
     if [ -L "$OSX_ROOT/pkgs/python/current" ] && [ -x "$OSX_ROOT/pkgs/python/current/bin/$sub" ]; then exec "$OSX_ROOT/pkgs/python/current/bin/$sub" "$@"; fi
     if [ -L "$OSX_ROOT/pkgs/node/current" ] && [ -x "$OSX_ROOT/pkgs/node/current/bin/$sub" ]; then exec "$OSX_ROOT/pkgs/node/current/bin/$sub" "$@"; fi
     echo "osx-$sub: not found"; exit 127 ;;
esac
EOF
  chmod +x "$OSX_ROOT/shims/osx-dispatch"
}

write_shimgen() {
  cat > "$OSX_ROOT/shims/osx-shimgen" <<'EOF'
#!/usr/bin/env bash
set -e
OSX_ROOT="${OSX_ROOT:-/opt/osx}"
[ -f "$OSX_ROOT/env/config.sh" ] && . "$OSX_ROOT/env/config.sh"
BIN_DIR="$OSX_ROOT/bin"
dispatch="$OSX_ROOT/shims/osx-dispatch"
mk() { n="$1"; [ -n "$n" ] || exit 0; ln -sf "$dispatch" "$BIN_DIR/osx-$n"; }
if [ "$1" = "--bulk" ]; then
  [ -x "$OSX_ROOT/pkgs/python/current/bin/python" ] && for n in python python3 pip pip3; do mk "$n"; done
  [ -x "$OSX_ROOT/pkgs/node/current/bin/node" ] && for n in node npm npx corepack; do mk "$n"; done
  [ -x "$OSX_ROOT/pkgs/osxcross/target/bin/xcrun" ] && mk xcrun
  exit 0
fi
mk "$1"
EOF
  chmod +x "$OSX_ROOT/shims/osx-shimgen"
}

bootstrap() {
  ensure_dirs
  write_config
  write_pathrc
  write_cnf_hooks
  platform_vars
  write_dispatch
  write_shimgen
  "$OSX_ROOT/shims/osx-shimgen" --bulk || true
}

apt_install() {
  /usr/bin/sudo apt-get update
  /usr/bin/sudo apt-get install -y "$@"
}

install_osxcross() {
  apt_install $APT_OSXCROSS
  f=""
  for cand in $LLD_CANDIDATES; do [ -n "$cand" ] && [ -x "$cand" ] && { f="$cand"; break; }; done
  if [ -z "$f" ]; then /usr/bin/sudo apt-get install -y lld || true; for cand in $LLD_CANDIDATES; do [ -n "$cand" ] && [ -x "$cand" ] && { f="$cand"; break; }; done; fi
  [ -n "$f" ] || { echo "ld64.lld not found"; exit 1; }
  SRC="$OSX_ROOT/pkgs/osxcross/src"
  TGT="$OSX_ROOT/pkgs/osxcross/target"
  HBIN="$OSX_ROOT/pkgs/osxcross/host-bin"
  mkdir -p "$SRC" "$TGT" "$HBIN"
  ln -sf "$f" "$HBIN/ld64.lld"
  PATH="$HBIN:$PATH"
  mirror="$CACHE_DIR/osxcross-src"
  if [ ! -d "$mirror" ]; then git clone --depth 1 --branch "$OSXCROSS_BRANCH" "$OSXCROSS_REPO" "$mirror"; fi
  if [ ! -d "$SRC/osxcross" ]; then cp -R "$mirror" "$SRC/osxcross"; fi
  cd "$SRC/osxcross"
  mkdir -p tarballs
  sdk_cached="$CACHE_DIR/MacOSX${DEFAULT_SDK_VER}.sdk.tar.xz"
  if [ -n "${SDK_TARBALL_URL:-}" ]; then [ -f "$sdk_cached" ] || curl -fL -o "$sdk_cached" "$SDK_TARBALL_URL" || true; fi
  if [ ! -f "$sdk_cached" ]; then
    if [ -n "${XCODE_XIP:-}" ] && [ -f "${XCODE_XIP:-}" ]; then ./tools/gen_sdk_package_pbzx.sh "$XCODE_XIP"; mv MacOSX*.sdk.tar.* "$sdk_cached"
    else curl -fL -o "$sdk_cached" "https://github.com/joseluisq/macosx-sdks/releases/download/${DEFAULT_SDK_VER}/MacOSX${DEFAULT_SDK_VER}.sdk.tar.xz" || true
    fi
  fi
  [ -f "$sdk_cached" ] || { echo "SDK tarball not found"; exit 1; }
  cp "$sdk_cached" tarballs/
  (set +e; CC="$(command -v gcc)" CXX="$(command -v g++)" CONFIG_SHELL=/bin/bash UNATTENDED=1 ENABLE_ARCHS="$DEFAULT_ARCH" TARGET_DIR="$TGT" ./build.sh)
  cat > "$OSX_ROOT/env/osxcross-activate.sh" <<EOF
export PATH="$TGT/bin:\$PATH"
export SDKROOT="\$(xcrun --show-sdk-path)"
export MACOSX_DEPLOYMENT_TARGET="\${MACOSX_DEPLOYMENT_TARGET:-$DEFAULT_DEPLOY_MIN}"
export CC="xcrun clang"
export CXX="xcrun clang++"
export CFLAGS="\${CFLAGS:-} -mmacos-version-min=\$MACOSX_DEPLOYMENT_TARGET"
export CXXFLAGS="\${CXXFLAGS:-} -stdlib=libc++ -mmacos-version-min=\$MACOSX_DEPLOYMENT_TARGET"
export LDFLAGS="\${LDFLAGS:-} -stdlib=libc++"
EOF
  "$OSX_ROOT/shims/osx-shimgen" --bulk || true
  cd "$SCRIPT_DIR"
}

ensure_pyenv() {
  mirror="$CACHE_DIR/pyenv"
  if [ ! -d "$mirror" ]; then git clone --depth 1 "$PYENV_REPO" "$mirror"; fi
  if [ ! -d "$OSX_ROOT/pkgs/pyenv" ]; then cp -R "$mirror" "$OSX_ROOT/pkgs/pyenv"; fi
}

install_python() {
  ver="$1"
  [ -n "$ver" ] || { echo "python version required"; exit 1; }
  apt_install $APT_PYBUILD
  ensure_pyenv
  "$OSX_ROOT/pkgs/pyenv/plugins/python-build/install.sh" >/dev/null 2>&1 || true
  prefix="$OSX_ROOT/pkgs/python/$ver"
  mkdir -p "$(dirname "$prefix")"
  if [ ! -x "$prefix/bin/python" ]; then PYTHON_BUILD_CACHE_PATH="$CACHE_DIR/python-build" "$OSX_ROOT/pkgs/pyenv/plugins/python-build/bin/python-build" "$ver" "$prefix"; fi
  "$prefix/bin/python" -m pip install -U "pip>=25.1"
  rm -f "$OSX_ROOT/pkgs/python/current"
  ln -s "$prefix" "$OSX_ROOT/pkgs/python/current"
  "$OSX_ROOT/shims/osx-shimgen" --bulk || true
}

install_node() {
  ver="$1"
  [ -n "$ver" ] || { echo "node version required"; exit 1; }
  arch="$(uname -m)"
  case "$arch" in x86_64) host=x64 ;; aarch64|arm64) host=arm64 ;; *) host=x64 ;; esac
  url="$NODE_BASE_URL/v$ver/node-v$ver-linux-$host.tar.xz"
  tarball="$CACHE_DIR/node-v$ver-linux-$host.tar.xz"
  mkdir -p "$CACHE_DIR" "$OSX_ROOT/pkgs/node"
  [ -f "$tarball" ] || curl -fL -o "$tarball" "$url"
  tmpdir="$(mktemp -d)"
  tar -C "$tmpdir" -xf "$tarball"
  srcdir="$(find "$tmpdir" -maxdepth 1 -type d -name "node-v$ver-linux-$host" -print -quit)"
  [ -n "$srcdir" ] || { echo "node unpack failed"; exit 1; }
  dest="$OSX_ROOT/pkgs/node/$ver"
  rm -rf "$dest"
  mkdir -p "$dest"
  mv "$srcdir"/* "$dest"/
  rm -rf "$tmpdir"
  rm -f "$OSX_ROOT/pkgs/node/current"
  ln -s "$dest" "$OSX_ROOT/pkgs/node/current"
  "$OSX_ROOT/shims/osx-shimgen" --bulk || true
}

usage() {
  echo "usage:"
  echo "  osx-install.sh               bootstrap /opt/osx with defaults"
  echo "  osx-install.sh osxcross      install osxcross"
  echo "  osx-install.sh python <ver>  install python version"
  echo "  osx-install.sh node <ver>    install node version"
  exit 1
}

main() {
  case "${1:-}" in
    "") bootstrap; inject_shell_rc; printf "OK\n" ;;
    osxcross) bootstrap; install_osxcross; printf "OK\n" ;;
    python) shift; [ -n "${1:-}" ] || usage; bootstrap; install_python "$1"; printf "OK\n" ;;
    node) shift; [ -n "${1:-}" ] || usage; bootstrap; install_node "$1"; printf "OK\n" ;;
    *) usage ;;
  esac
}

main "$@"