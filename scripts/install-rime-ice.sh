#!/usr/bin/env bash
# Install Rime Ice into the current user's Rime directory.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ -f $SCRIPT_DIR/../versions.env ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/../versions.env"
elif [[ -f /usr/share/rime-ready/build-info ]]; then
  # shellcheck disable=SC1091
  source /usr/share/rime-ready/build-info
fi
RIME_ICE_RELEASE=${RIME_ICE_RELEASE:-2026.06.30}
RIME_ICE_SHA256=${RIME_ICE_SHA256:-}

frontend=fcitx5
with_gram=0
activate_frontend=1
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
    --no-activate)
      activate_frontend=0
      start_frontend=0
      shift
      ;;
    --no-start)
      start_frontend=0
      shift
      ;;
    -h | --help)
      cat <<'EOF'
用法：scripts/install-rime-ice.sh [--frontend fcitx5|ibus] [--with-gram] [--no-activate] [--no-start]

安装稳定版雾凇拼音。默认显式设置并启动对应输入法；--no-activate 只安装方案。
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
ice_url=${RIME_ICE_URL:-https://github.com/iDvel/rime-ice/releases/download/$RIME_ICE_RELEASE/full.zip}
curl -L --fail --retry 3 "$ice_url" -o "$tmp/rime-ice.zip"
if [[ -n $RIME_ICE_SHA256 ]]; then
  echo "$RIME_ICE_SHA256  $tmp/rime-ice.zip" | sha256sum --check --status || {
    echo "雾凇拼音压缩包校验失败。" >&2
    exit 1
  }
fi
unzip -q "$tmp/rime-ice.zip" -d "$tmp/new-rime"

timestamp=$(date +%Y%m%d-%H%M%S)
backup="${rime_dir}-backup-${timestamp}"
if ((activate_frontend)); then
  if [[ $frontend == fcitx5 ]]; then
    fcitx5-remote -e 2>/dev/null || true
    for _ in $(seq 1 40); do
      pgrep -x fcitx5 >/dev/null || break
      sleep 0.25
    done
  else
    ibus exit 2>/dev/null || true
  fi
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

if ((activate_frontend)); then
  configure_args=(--frontend "$frontend")
  ((start_frontend)) || configure_args+=(--no-start)
  "$SCRIPT_DIR/configure-input-method.sh" "${configure_args[@]}"
fi

[[ -f $rime_dir/build/rime_ice.schema.yaml ]] || {
  echo "雾凇拼音部署产物缺失。" >&2
  exit 1
}
printf '雾凇拼音安装完成：%s\n' "$rime_dir"
if [[ -d ${backup:-} ]]; then
  printf '原配置备份：%s\n' "$backup"
fi
