#!/usr/bin/env bash
# Explicitly select Rime as the current user's Fcitx5 or IBus input method.
set -euo pipefail

frontend=fcitx5
start_frontend=1
while (($#)); do
  case $1 in
    --frontend)
      frontend=$2
      shift 2
      ;;
    --no-start)
      start_frontend=0
      shift
      ;;
    -h | --help)
      echo "用法：$0 [--frontend fcitx5|ibus] [--no-start]"
      exit 0
      ;;
    *)
      echo "未知参数：$1" >&2
      exit 1
      ;;
  esac
done
[[ $EUID -ne 0 ]] || {
  echo "请以普通桌面用户运行，不要使用 sudo。" >&2
  exit 1
}

cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}
mkdir -p "$cache_dir"
case $frontend in
  fcitx5)
    profile=${XDG_CONFIG_HOME:-$HOME/.config}/fcitx5/profile
    mkdir -p "$(dirname "$profile")"
    python3 - "$profile" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
if not path.exists():
    text = """[Groups/0]\nName=Default\nDefault Layout=us\nDefaultIM=rime\n\n[Groups/0/Items/0]\nName=keyboard-us\nLayout=\n\n[Groups/0/Items/1]\nName=rime\nLayout=\n\n[GroupOrder]\n0=Default\n"""
else:
    text = path.read_text()
    if re.search(r"(?m)^DefaultIM=", text):
        text = re.sub(r"(?m)^DefaultIM=.*$", "DefaultIM=rime", text, count=1)
    else:
        text = text.replace("[Groups/0]", "[Groups/0]\nDefaultIM=rime", 1)
    if not re.search(r"(?m)^Name=rime$", text):
        indexes = [int(x) for x in re.findall(r"\[Groups/0/Items/(\d+)\]", text)]
        item = max(indexes, default=-1) + 1
        block = f"[Groups/0/Items/{item}]\nName=rime\nLayout=\n\n"
        text = text.replace("[GroupOrder]", block + "[GroupOrder]", 1)
path.write_text(text)
PY
    if command -v im-config >/dev/null; then
      im-config -n fcitx5 || true
    fi
    if ((start_frontend)); then
      fcitx5-remote -e 2>/dev/null || true
      nohup /usr/bin/fcitx5 -d >"$cache_dir/rime-ready-fcitx5.log" 2>&1 &
    fi
    ;;
  ibus)
    if command -v im-config >/dev/null; then
      im-config -n ibus || true
    fi
    if ((start_frontend)); then
      ibus exit 2>/dev/null || true
      nohup ibus-daemon -drx >"$cache_dir/rime-ready-ibus.log" 2>&1 &
    fi
    ;;
  *)
    echo "不支持前端：$frontend" >&2
    exit 1
    ;;
esac
printf '已为当前用户设置 %s Rime 输入法。\n' "$frontend"
