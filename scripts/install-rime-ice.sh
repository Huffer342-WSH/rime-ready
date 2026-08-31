#!/usr/bin/env bash
# Install Rime Ice into the current user's Rime directory.
set -euo pipefail

frontend=fcitx5
with_gram=0
start_frontend=1
while (($#)); do
  case $1 in
    --frontend)
      frontend=$2
      shift 2
      ;;
    --with-gram)
      with_gram=1
      shift
      ;;
    --no-start)
      start_frontend=0
      shift
      ;;
    -h | --help)
      cat <<'EOF'
用法：rime-ready-install-ice [--frontend fcitx5|ibus] [--with-gram] [--no-start]

默认安装雾凇拼音到 Fcitx5；--with-gram 同时安装万象语法模型。
EOF
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
case $frontend in
  fcitx5) rime_dir=${XDG_DATA_HOME:-$HOME/.local/share}/fcitx5/rime ;;
  ibus) rime_dir=${XDG_CONFIG_HOME:-$HOME/.config}/ibus/rime ;;
  *)
    echo "不支持前端：$frontend" >&2
    exit 1
    ;;
esac

for command in curl unzip rime_deployer; do
  command -v "$command" >/dev/null || {
    echo "缺少命令：$command" >&2
    exit 1
  }
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ice_url=${RIME_ICE_URL:-https://github.com/iDvel/rime-ice/releases/latest/download/full.zip}
curl -L --fail --retry 3 "$ice_url" -o "$tmp/rime-ice.zip"
unzip -q "$tmp/rime-ice.zip" -d "$tmp/new-rime"

timestamp=$(date +%Y%m%d-%H%M%S)
backup="${rime_dir}-backup-${timestamp}"
if [[ $frontend == fcitx5 ]]; then
  fcitx5-remote -e 2>/dev/null || true
  for _ in $(seq 1 40); do
    pgrep -x fcitx5 >/dev/null || break
    sleep 0.25
  done
else
  ibus exit 2>/dev/null || true
fi

if [[ -d $rime_dir ]]; then
  mv "$rime_dir" "$backup"
fi
mkdir -p "$(dirname "$rime_dir")"
mv "$tmp/new-rime" "$rime_dir"

# Keep the user's learned Rime Ice words when updating an existing installation.
if [[ -d ${backup:-}/rime_ice.userdb ]]; then
  cp -a "$backup/rime_ice.userdb" "$rime_dir/"
fi

cat >"$rime_dir/default.custom.yaml" <<'EOF'
patch:
  schema_list:
    - schema: rime_ice
EOF

if ((with_gram)); then
  model=wanxiang-lts-zh-hans.gram
  if [[ -f ${backup:-}/$model ]]; then
    mv "$backup/$model" "$rime_dir/$model"
  else
    curl -L --fail --retry 3 \
      https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/$model \
      -o "$rime_dir/$model"
  fi
  cat >"$rime_dir/rime_ice.custom.yaml" <<'EOF'
patch:
  grammar:
    language: wanxiang-lts-zh-hans
    collocation_max_length: 6
    collocation_min_length: 3
    collocation_penalty: -14
    non_collocation_penalty: -6
    weak_collocation_penalty: -100
    rear_penalty: -20
  translator/contextual_suggestions: false
  translator/max_homophones: 8
EOF
fi

shared_dir=/usr/share/rime-data
rm -rf "$rime_dir/build"
mkdir -p "$rime_dir/build"
rime_deployer --build "$rime_dir" "$shared_dir" "$rime_dir/build"

cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}
mkdir -p "$cache_dir"
if [[ $frontend == fcitx5 ]]; then
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
    nohup /usr/bin/fcitx5 -d >"$cache_dir/rime-ready-fcitx5.log" 2>&1 &
  fi
elif ((start_frontend)); then
  nohup ibus-daemon -drx >"$cache_dir/rime-ready-ibus.log" 2>&1 &
fi

[[ -f $rime_dir/build/rime_ice.schema.yaml ]] || {
  echo "雾凇拼音部署产物缺失。" >&2
  exit 1
}
printf '雾凇拼音安装完成：%s\n' "$rime_dir"
if [[ -d ${backup:-} ]]; then
  printf '原配置备份：%s\n' "$backup"
fi
