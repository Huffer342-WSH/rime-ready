#!/usr/bin/env bash
# Restore Ubuntu 22.04's official Rime packages without deleting user data.
set -euo pipefail

ubuntu_version=1.7.3+dfsg3-2build2
packages=(librime1 librime-bin librime-plugin-lua librime-plugin-octagram)
if [[ $EUID -ne 0 ]]; then
  exec sudo "$0" "$@"
fi
apt-get update
specs=()
for package in "${packages[@]}"; do specs+=("$package=$ubuntu_version"); done
apt-get install -y --allow-downgrades "${specs[@]}"
printf '已恢复 Ubuntu 22.04 官方 Rime 软件包；用户词库和配置未删除。\n'
