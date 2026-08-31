#!/usr/bin/env bash
# Build librime, librime-lua and librime-octagram for one platform target.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

target=$DEFAULT_TARGET
install_deps=1
clean=0
while (($#)); do
  case $1 in
    --target)
      target=$2
      shift 2
      ;;
    --skip-deps)
      install_deps=0
      shift
      ;;
    --clean)
      clean=1
      shift
      ;;
    -h | --help)
      echo "用法：$0 [--target ubuntu-22.04] [--skip-deps] [--clean]"
      exit 0
      ;;
    *) die "未知参数：$1" ;;
  esac
done

load_target "$target"
require_ubuntu_target

if ((install_deps)); then
  log "安装 $PLATFORM_NAME 构建依赖"
  mapfile -t packages < <(grep -Ev '^\s*(#|$)' "$PROJECT_ROOT/platforms/$TARGET/build-packages.txt")
  run_as_root apt-get update
  run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"
fi

if ((clean)); then
  rm -rf "$BUILD_ROOT"
fi
mkdir -p "$SOURCE_ROOT" "$DIST_DIR"

clone_at_ref() {
  local url=$1 dir=$2 ref=$3
  if [[ ! -d $dir/.git ]]; then
    git clone --filter=blob:none "$url" "$dir"
  fi
  git -C "$dir" fetch --depth=1 origin "$ref"
  git -C "$dir" checkout --detach --force FETCH_HEAD
}

log "获取固定版本的上游源码"
clone_at_ref https://github.com/rime/librime.git "$LIBRIME_SOURCE" "$LIBRIME_REF"
git -C "$LIBRIME_SOURCE" submodule update --init --depth=1
clone_at_ref https://github.com/hchunhui/librime-lua.git "$LIBRIME_SOURCE/plugins/lua" "$LIBRIME_LUA_REF"
clone_at_ref https://github.com/lotem/librime-octagram.git "$LIBRIME_SOURCE/plugins/octagram" "$LIBRIME_OCTAGRAM_REF"
clone_at_ref https://github.com/hchunhui/librime-lua.git \
  "$LIBRIME_SOURCE/plugins/lua/thirdparty" "$LIBRIME_LUA_THIRDPARTY_REF"

# Ubuntu 22.04 has CMake 3.22 and static dependency packages are not new enough.
# Build the pinned dependency submodules with PIC; disable glog's optional
# libunwind backend so its static archive does not leak undeclared symbols.
log "准备适合共享库链接的静态基础依赖"
python3 - "$LIBRIME_SOURCE/deps.mk" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
marker = '-DCMAKE_BUILD_TYPE:STRING="Release" \\\n'
pic = '-DCMAKE_POSITION_INDEPENDENT_CODE:BOOL=ON \\\n' + marker
count = text.count(marker)
if count < 5:
    raise SystemExit(f"deps.mk layout changed: found only {count} build-type markers")
text = text.replace(marker, pic)
if '-DWITH_UNWIND=none' not in text:
    needle = '-DWITH_GFLAGS:BOOL=OFF \\\n'
    if needle not in text:
        raise SystemExit("deps.mk layout changed: glog flags not found")
    text = text.replace(needle, needle + '-DWITH_UNWIND=none \\\n', 1)
path.write_text(text)
PY

make -C "$LIBRIME_SOURCE" deps

log "编译 Rime $RIME_VERSION、Lua 和 Octagram"
rm -rf "$LIBRIME_SOURCE/build" "$STAGE_ROOT"
cmake -S "$LIBRIME_SOURCE" -B "$LIBRIME_SOURCE/build" \
  -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TEST=ON \
  -DBUILD_MERGED_PLUGINS=OFF \
  -DENABLE_EXTERNAL_PLUGINS=ON \
  -DLINUX="$CMAKE_LINUX_FLAG" \
  -DBOOST_ROOT=/usr \
  -DCMAKE_PREFIX_PATH="$LIBRIME_SOURCE;/usr" \
  -DCMAKE_INCLUDE_PATH="$LIBRIME_SOURCE/include;/usr/include" \
  -DCMAKE_LIBRARY_PATH="$LIBRIME_SOURCE/lib;/usr/lib/x86_64-linux-gnu"
cmake --build "$LIBRIME_SOURCE/build" --parallel "$(nproc)"
DESTDIR="$STAGE_ROOT" cmake --install "$LIBRIME_SOURCE/build"
# The release package is a runtime package, not an SDK.
rm -rf \
  "$STAGE_ROOT/usr/local/include" \
  "$STAGE_ROOT/usr/local/lib/pkgconfig" \
  "$STAGE_ROOT/usr/local/share/cmake"

plugin_dir="$STAGE_ROOT/usr/local/lib/rime-plugins"
for plugin in lua octagram; do
  mv "$plugin_dir/librime-$plugin.so" "$plugin_dir/librime-$plugin.so.$RIME_VERSION"
  ln -s "librime-$plugin.so.$RIME_VERSION" "$plugin_dir/librime-$plugin.so"
done

install -d "$STAGE_ROOT/usr/local/share/rime-ready"
cat >"$STAGE_ROOT/usr/local/share/rime-ready/build-info" <<EOF
platform=$PLATFORM_ID
rime_version=$RIME_VERSION
librime_ref=$LIBRIME_REF
librime_lua_ref=$LIBRIME_LUA_REF
librime_octagram_ref=$LIBRIME_OCTAGRAM_REF
RIME_ICE_RELEASE=$RIME_ICE_RELEASE
RIME_ICE_ASSET_ID=$RIME_ICE_ASSET_ID
RIME_ICE_SHA256=$RIME_ICE_SHA256
EOF

log "构建完成：$STAGE_ROOT"
