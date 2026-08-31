#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
load_target "${1:-$DEFAULT_TARGET}"

lib_dir="$STAGE_ROOT/usr/local/lib"
bin_dir="$STAGE_ROOT/usr/local/bin"
plugin_dir="$lib_dir/rime-plugins"

ctest --test-dir "$LIBRIME_SOURCE/build" --output-on-failure

[[ -f $lib_dir/librime.so.$RIME_VERSION ]]
[[ $(readlink "$lib_dir/librime.so.1") == "librime.so.$RIME_VERSION" ]]
for plugin in lua octagram; do
  [[ -f $plugin_dir/librime-$plugin.so.$RIME_VERSION ]]
  [[ $(readlink "$plugin_dir/librime-$plugin.so") == "librime-$plugin.so.$RIME_VERSION" ]]
done

for file in "$lib_dir/librime.so.1" "$plugin_dir/librime-lua.so" "$plugin_dir/librime-octagram.so"; do
  if LD_LIBRARY_PATH="$lib_dir" ldd "$file" | grep -q 'not found'; then
    LD_LIBRARY_PATH="$lib_dir" ldd "$file" >&2
    die "存在未满足的动态库依赖：$file"
  fi
done

test_rime=$(mktemp -d)
trap 'rm -rf "$test_rime"' EXIT
mkdir -p "$test_rime/user" "$test_rime/build"
cat >"$test_rime/user/default.custom.yaml" <<'EOF'
patch:
  schema_list:
    - schema: luna_pinyin
EOF
LD_LIBRARY_PATH="$lib_dir" "$bin_dir/rime_deployer" --build \
  "$test_rime/user" /usr/share/rime-data "$test_rime/build"
[[ -f $test_rime/build/luna_pinyin.schema.yaml ]]
[[ -f $test_rime/build/luna_pinyin.prism.bin ]]

log "构建产物检查通过"
