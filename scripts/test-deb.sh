#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$PROJECT_ROOT/versions.env"
deb=${1:-}
if [[ -z $deb ]]; then
  deb=$(find "$PROJECT_ROOT/dist" -maxdepth 1 -name 'rime-ready_*.deb' -printf '%T@ %p\n' |
    sort -nr | head -1 | cut -d' ' -f2-)
fi
[[ -f $deb ]] || {
  echo "找不到待测试的 deb：$deb" >&2
  exit 1
}

sudo apt-get install -y "$deb"
ldd /usr/lib/x86_64-linux-gnu/fcitx5/rime.so | grep -q '/usr/local/lib/librime.so.1'
for plugin in lua octagram; do
  if ldd "/usr/local/lib/rime-plugins/librime-$plugin.so" | grep -q 'not found'; then
    exit 1
  fi
done

test_home=$(mktemp -d)
trap 'rm -rf "$test_home"' EXIT
HOME="$test_home" rime-ready-install-ice --no-start
grep -q 'schema_id: rime_ice' \
  "$test_home/.local/share/fcitx5/rime/build/rime_ice.schema.yaml"
grep -q "rime_version: $RIME_VERSION" \
  "$test_home/.local/share/fcitx5/rime/build/rime_ice.schema.yaml"

echo "deb 和雾凇拼音安装检查通过"
