#!/usr/bin/env bash
# Build and install the system Rime runtime package.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
"$SCRIPT_DIR/package-deb.sh" "$@"
deb=$(find "$SCRIPT_DIR/../dist" -maxdepth 1 -name 'rime-ready_*.deb' -printf '%T@ %p\n' | sort -nr | head -1 | cut -d' ' -f2-)
[[ -n $deb ]] || {
  echo "没有找到构建出的 deb" >&2
  exit 1
}
sudo apt-get install -y "$deb"
printf 'Rime 运行库安装完成；尚未修改或激活输入法。\n'
printf '如需安装雾凇并设置输入法，请运行：scripts/install-rime-ice.sh\n'
