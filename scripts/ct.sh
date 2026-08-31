#!/usr/bin/env bash
# Run every check required before publishing a release artifact.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

target=$DEFAULT_TARGET
reuse_build=0
while (($#)); do
  case $1 in
    --target)
      target=$2
      shift 2
      ;;
    --reuse-build)
      reuse_build=1
      shift
      ;;
    -h | --help)
      echo "用法：$0 [--target ubuntu-22.04] [--reuse-build]"
      exit 0
      ;;
    *) die "未知参数：$1" ;;
  esac
done

if ((!reuse_build)); then
  "$SCRIPT_DIR/build.sh" --target "$target"
fi

log "检查 Shell 脚本"
shellcheck "$PROJECT_ROOT/install.sh" "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR/lib"/*.sh

log "运行 Rime 单元测试和产物测试"
"$SCRIPT_DIR/test-build.sh" "$target"

log "生成并安装测试 deb"
"$SCRIPT_DIR/package-deb.sh" --target "$target" --reuse-build
"$SCRIPT_DIR/test-deb.sh"

log "$target CT 全部通过"
