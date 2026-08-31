#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
target=${TARGET:-$DEFAULT_TARGET}
load_target "$target"
multiarch=$(dpkg-architecture -qDEB_HOST_MULTIARCH)
libdir="/usr/lib/$multiarch"
required_packages=(librime1 librime-bin librime-plugin-lua librime-plugin-octagram)

if (($#)); then
  debs=("$@")
else
  mapfile -t debs < <(find "$DIST_DIR" -maxdepth 1 -name '*.deb' -print | sort)
fi
((${#debs[@]} == 4)) || {
  echo "应测试四个标准 deb，实际为 ${#debs[@]} 个" >&2
  exit 1
}

for package in "${required_packages[@]}"; do
  matches=0
  for deb in "${debs[@]}"; do
    [[ $(dpkg-deb --field "$deb" Package) == "$package" ]] && matches=$((matches + 1))
    if dpkg-deb --contents "$deb" | grep -q 'install-rime-ice\|configure-input-method'; then
      echo "$deb 不应包含用户输入法配置脚本" >&2
      exit 1
    fi
  done
  ((matches == 1)) || {
    echo "缺少或重复软件包：$package" >&2
    exit 1
  }
done

# First install Ubuntu's original consumers and packages, then upgrade the four
# Rime packages with local, higher Debian versions.
sudo apt-get install -y --no-install-recommends \
  fcitx5-rime ibus-rime librime-bin librime-plugin-lua librime-plugin-octagram
sudo apt-get install -y "${debs[@]}"
sudo apt-get update -qq
LC_ALL=C apt-get --simulate upgrade >/dev/null

core_version=$(dpkg-query -W -f='${Version}' librime1)
for package in "${required_packages[@]}"; do
  installed=$(dpkg-query -W -f='${Version}' "$package")
  [[ $installed == "$core_version" ]] || {
    echo "$package 版本不一致：$installed" >&2
    exit 1
  }
  dpkg --compare-versions "$installed" gt '1.7.3+dfsg3-2build2' || {
    echo "$package 没有被 APT 识别为 Jammy 软件包的升级版本" >&2
    exit 1
  }
  candidate=$(LC_ALL=C apt-cache policy "$package" | awk '/Candidate:/ {print $2}')
  [[ $candidate == "$installed" ]] || {
    echo "apt candidate 异常：$package installed=$installed candidate=$candidate" >&2
    exit 1
  }
done

# Every installed path must be owned by the corresponding dpkg package.
dpkg-query -S \
  "$libdir/librime.so.1" \
  "$libdir/rime-plugins/librime-lua.so" \
  "$libdir/rime-plugins/librime-octagram.so" \
  /usr/bin/rime_deployer >/dev/null

check_consumer() {
  local binary=$1 output
  output=$(ldd -r "$binary" 2>&1)
  if ! grep -qE '/(usr/)?lib/[^ ]*/librime\.so\.1' <<<"$output" ||
    grep -qE 'undefined symbol:|not found' <<<"$output"; then
    printf '%s\n' "$output" >&2
    echo "Ubuntu APT 前端与新版 librime 不兼容：$binary" >&2
    exit 1
  fi
  grep -E '/(usr/)?lib/[^ ]*/librime\.so\.1' <<<"$output"
}
check_consumer "$libdir/fcitx5/rime.so"
check_consumer /usr/lib/ibus-rime/ibus-engine-rime
for plugin in lua octagram; do
  if ldd -r "$libdir/rime-plugins/librime-$plugin.so" 2>&1 |
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

g++ -std=c++17 -O2 -I"$LIBRIME_SOURCE/src" \
  "$PROJECT_ROOT/tests/rime-smoke.cc" "$libdir/librime.so.1" -o "$test_home/rime-smoke"
"$test_home/rime-smoke" /usr/share/rime-data "$rime_dir" |
  tee "$test_home/rime-smoke.out"
grep -q '^candidate\[[0-9]\+\]=你好$' "$test_home/rime-smoke.out"
grep -q '^commit=你好$' "$test_home/rime-smoke.out"

echo "四个标准 deb、APT 升级语义、前端 ABI 和 Rime 输入输出检查通过"
