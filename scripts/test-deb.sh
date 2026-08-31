#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
target=${TARGET:-$DEFAULT_TARGET}
load_target "$target"

deb=${1:-}
if [[ -z $deb ]]; then
  deb=$(find "$DIST_DIR" -maxdepth 1 -name 'rime-ready_*.deb' -printf '%T@ %p\n' |
    sort -nr | head -1 | cut -d' ' -f2-)
fi
[[ -f $deb ]] || {
  echo "找不到待测试的 deb：$deb" >&2
  exit 1
}

# The runtime package must not contain or activate per-user configuration tools.
if dpkg-deb --contents "$deb" | grep -q 'rime-ready-install-ice\|configure-input-method'; then
  echo "deb 不应包含用户输入法配置脚本" >&2
  exit 1
fi
if dpkg-deb --field "$deb" Depends | grep -qE 'fcitx|ibus|curl|unzip|python'; then
  echo "deb 不应依赖输入法前端或用户配置工具" >&2
  exit 1
fi

# Install Ubuntu's unmodified frontends first, then verify that they remain ABI
# compatible when the modern librime SONAME in /usr/local takes precedence.
sudo apt-get install -y --no-install-recommends fcitx5-rime ibus-rime
sudo apt-get install -y "$deb"
check_consumer() {
  local binary=$1 output
  output=$(ldd -r "$binary" 2>&1)
  if ! grep -q '/usr/local/lib/librime.so.1' <<<"$output" ||
    grep -qE 'undefined symbol:|not found' <<<"$output"; then
    printf '%s\n' "$output" >&2
    echo "Ubuntu APT 前端与新版 librime 不兼容：$binary" >&2
    exit 1
  fi
  grep '/usr/local/lib/librime.so.1' <<<"$output"
}
check_consumer /usr/lib/x86_64-linux-gnu/fcitx5/rime.so
check_consumer /usr/lib/ibus-rime/ibus-engine-rime
for plugin in lua octagram; do
  if ldd -r "/usr/local/lib/rime-plugins/librime-$plugin.so" 2>&1 |
    grep -qE 'undefined symbol:|not found'; then
    exit 1
  fi
done

test_home=$(mktemp -d)
trap 'rm -rf "$test_home"' EXIT
HOME="$test_home" "$SCRIPT_DIR/install-rime-ice.sh" --no-activate
rime_dir="$test_home/.local/share/fcitx5/rime"
grep -q 'schema_id: rime_ice' "$rime_dir/build/rime_ice.schema.yaml"
grep -q "rime_version: $RIME_VERSION" "$rime_dir/build/rime_ice.schema.yaml"
[[ ! -e $test_home/.config/fcitx5/profile ]]
[[ ! -e $test_home/.xinputrc ]]

g++ -std=c++17 -O2 \
  -I"$LIBRIME_SOURCE/src" \
  "$PROJECT_ROOT/tests/rime-smoke.cc" \
  -L/usr/local/lib -lrime \
  -o "$test_home/rime-smoke"
"$test_home/rime-smoke" /usr/share/rime-data "$rime_dir" |
  tee "$test_home/rime-smoke.out"
grep -q '^candidate\[[0-9]\+\]=你好$' "$test_home/rime-smoke.out"
grep -q '^commit=你好$' "$test_home/rime-smoke.out"

echo "deb、Ubuntu APT 前端 ABI 和 Rime 输入输出检查通过"
