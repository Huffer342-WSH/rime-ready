#!/usr/bin/env bash
set -euo pipefail

version=${1:-1.17.0}
if [[ $EUID -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

rm -f \
  "/usr/local/lib/librime.so.$version" \
  /usr/local/lib/librime.so.1 \
  /usr/local/lib/librime.so \
  "/usr/local/lib/rime-plugins/librime-lua.so.$version" \
  /usr/local/lib/rime-plugins/librime-lua.so \
  "/usr/local/lib/rime-plugins/librime-octagram.so.$version" \
  /usr/local/lib/rime-plugins/librime-octagram.so \
  /usr/local/bin/rime_deployer \
  /usr/local/bin/rime_dict_manager \
  /usr/local/bin/rime_patch \
  /usr/local/bin/rime_table_decompiler \
  /usr/local/bin/rime-ready-install-ice
rm -rf /usr/local/share/rime-ready
ldconfig
printf '已移除 rime-ready 系统运行库；用户词库和配置未删除。\n'
