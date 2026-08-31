#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
DEFAULT_TARGET=ubuntu-22.04

log() {
  printf '\033[1;32m[rime-ready]\033[0m %s\n' "$*"
}

die() {
  printf '\033[1;31m[rime-ready]\033[0m %s\n' "$*" >&2
  exit 1
}

load_target() {
  local target=${1:-$DEFAULT_TARGET}
  local platform_file="$PROJECT_ROOT/platforms/$target/platform.env"
  [[ -f $platform_file ]] || die "不支持目标平台：$target"
  # shellcheck disable=SC1090,SC1091
  source "$PROJECT_ROOT/versions.env"
  # shellcheck disable=SC1090
  source "$platform_file"
  TARGET=$target
  BUILD_ROOT="$PROJECT_ROOT/.build/$TARGET"
  SOURCE_ROOT="$BUILD_ROOT/source"
  LIBRIME_SOURCE="$SOURCE_ROOT/librime"
  STAGE_ROOT="$BUILD_ROOT/stage"
  DIST_DIR="$PROJECT_ROOT/dist"
  export TARGET BUILD_ROOT SOURCE_ROOT LIBRIME_SOURCE STAGE_ROOT DIST_DIR
}

require_ubuntu_target() {
  [[ -r /etc/os-release ]] || die "无法识别当前系统"
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ ${ID:-} == "$PLATFORM_OS_ID" && ${VERSION_ID:-} == "$PLATFORM_OS_VERSION" ]] ||
    die "当前构建目标是 $PLATFORM_NAME，检测到 ${PRETTY_NAME:-未知系统}"
}

run_as_root() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}
