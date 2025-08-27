#!/usr/bin/env bash
set -Eeuo pipefail

OSX_ROOT="${OSX_ROOT:-/opt/osx}"
DEFAULT_ARCH="${DEFAULT_ARCH:-arm64}"
DEFAULT_SDK_VER="${DEFAULT_SDK_VER:-15.5}"
DEFAULT_DEPLOY_MIN="${DEFAULT_DEPLOY_MIN:-11.0}"

SDK_MAJOR="${DEFAULT_SDK_VER%%.*}"
PLATFORM="macosx_${SDK_MAJOR}_0_${DEFAULT_ARCH}"
WHEELHOUSE="$OSX_ROOT/wheelhouse/$PLATFORM"
SITEDIR="$OSX_ROOT/site-$PLATFORM"
export WHEELHOUSE

path_prepend_unique() {
  d="$1"
  [ -n "$d" ] && [ -d "$d" ] || return 0
  case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH" ;; esac
}

pick_latest_dir() {
  b="$1"
  [ -d "$b" ] || { echo ""; return 0; }
  find "$b" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort -Vr | head -n1
}

PY_HOME=""
if [ -L "$OSX_ROOT/pkgs/python/current" ]; then
  PY_HOME="$OSX_ROOT/pkgs/python/current"
else
  pv="$(pick_latest_dir "$OSX_ROOT/pkgs/python")"
  if [ -n "$pv" ]; then
    PY_HOME="$OSX_ROOT/pkgs/python/$pv"
  fi
fi

NODE_HOME=""
if [ -L "$OSX_ROOT/pkgs/node/current" ]; then
  NODE_HOME="$OSX_ROOT/pkgs/node/current"
else
  nv="$(pick_latest_dir "$OSX_ROOT/pkgs/node")"
  if [ -n "$nv" ]; then
    NODE_HOME="$OSX_ROOT/pkgs/node/$nv"
  fi
fi

OSXCROSS_TGT="$OSX_ROOT/pkgs/osxcross/target"
[ -d "$OSXCROSS_TGT/bin" ] && path_prepend_unique "$OSXCROSS_TGT/bin"

[ -n "$NODE_HOME" ] && path_prepend_unique "$NODE_HOME/bin"
[ -n "$PY_HOME" ] && path_prepend_unique "$PY_HOME/bin"
path_prepend_unique "$OSX_ROOT/bin"

export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-$DEFAULT_DEPLOY_MIN}"

if command -v xcrun >/dev/null 2>&1; then
  SDKROOT_VAL="$(xcrun --show-sdk-path 2>/dev/null || true)"
  if [ -n "$SDKROOT_VAL" ]; then
    export SDKROOT="$SDKROOT_VAL"
  fi
fi

if [ -n "$PY_HOME" ]; then
  if [ -f "$OSX_ROOT/env/pip-macos.conf" ]; then
    export PIP_CONFIG_FILE="$OSX_ROOT/env/pip-macos.conf"
  fi
  export PYTHONNOUSERSITE=1
  export PYTHONPATH="$SITEDIR${PYTHONPATH:+:$PYTHONPATH}"
fi

if [ -n "$NODE_HOME" ]; then
  export npm_config_platform=darwin
  export npm_config_arch="$DEFAULT_ARCH"
  export npm_config_target_arch="$DEFAULT_ARCH"
  if [ -n "$PY_HOME" ]; then
    export npm_config_python="$PY_HOME/bin/python"
  fi
fi

export CC="${CC:-xcrun clang}"
export CXX="${CXX:-xcrun clang++}"
export CFLAGS="${CFLAGS:-} -mmacos-version-min=$MACOSX_DEPLOYMENT_TARGET"
export CXXFLAGS="${CXXFLAGS:-} -stdlib=libc++ -mmacos-version-min=$MACOSX_DEPLOYMENT_TARGET"
export LDFLAGS="${LDFLAGS:-} -stdlib=libc++"

hash -r || true

if [ "$#" -gt 0 ]; then
  exec "$@"
else
  SHELL_BIN="${SHELL:-/bin/bash}"
  exec "$SHELL_BIN" -i
fi
