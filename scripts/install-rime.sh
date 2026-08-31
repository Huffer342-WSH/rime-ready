#!/usr/bin/env bash
# Build and install the standard Ubuntu replacement packages.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
"$SCRIPT_DIR/package-deb.sh" "$@"
mapfile -t debs < <(find "$SCRIPT_DIR/../dist" -maxdepth 1 -name '*.deb' -print | sort)
((${#debs[@]} == 4)) || {
  echo "应生成四个 Rime deb，实际为 ${#debs[@]} 个" >&2
  exit 1
}
sudo apt-get install -y "${debs[@]}"
printf 'Rime 标准替换包安装完成；尚未修改或激活输入法。\n'
printf '如需安装雾凇并设置输入法，请运行：scripts/install-rime-ice.sh\n'
