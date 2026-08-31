#!/usr/bin/env bash
# Install release debs by default; optionally build them, then apply a preset.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mode=download
preset=ice
frontend=fcitx5
activate=1
start_frontend=1
deb_sources=()
required_packages=(librime1 librime-bin librime-plugin-lua librime-plugin-octagram)

usage() {
  cat <<'EOF'
用法：./install.sh [选项]

运行库来源：
  --download            从最新 GitHub Release 下载四个标准 deb（默认）
  --build               在本机从固定源码编译四个标准 deb
  --deb <目录/文件/URL> 安装指定 deb；可重复使用

预设：
  --preset runtime-only  只安装 Rime 运行库和应用
  --preset ice           安装运行库、稳定版雾凇并设置输入法（默认）
  --preset ice-gram      在 ice 基础上安装万象 Gram

输入法：
  --frontend fcitx5|ibus 选择 Ubuntu APT 输入法前端（默认 fcitx5）
  --no-activate          安装方案但不修改当前用户的输入法设置
  --no-start             设置输入法但不立即启动前端
EOF
}

while (($#)); do
  case $1 in
    --download)
      mode=download
      deb_sources=()
      shift
      ;;
    --build)
      mode=build
      deb_sources=()
      shift
      ;;
    --deb)
      mode=deb
      deb_sources+=("${2:?--deb 缺少目录、文件或 URL}")
      shift 2
      ;;
    --preset)
      preset=${2:?--preset 缺少值}
      shift 2
      ;;
    --frontend)
      frontend=${2:?--frontend 缺少值}
      shift 2
      ;;
    --with-gram)
      preset=ice-gram
      shift
      ;;
    --no-activate)
      activate=0
      shift
      ;;
    --no-start)
      start_frontend=0
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数：$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done
case $preset in runtime-only | ice | ice-gram) ;; *)
  echo "不支持预设：$preset" >&2
  exit 1
  ;;
esac
case $frontend in fcitx5 | ibus) ;; *)
  echo "不支持前端：$frontend" >&2
  exit 1
  ;;
esac
[[ $EUID -ne 0 ]] || {
  echo "请以普通桌面用户运行，不要使用 sudo。" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
debs=()
verify_debs() {
  local -A found=()
  local deb package required
  for deb in "${debs[@]}"; do
    package=$(dpkg-deb --field "$deb" Package)
    found["$package"]=$deb
  done
  for required in "${required_packages[@]}"; do
    [[ -n ${found[$required]:-} ]] || {
      echo "缺少标准包：$required" >&2
      exit 1
    }
  done
  ((${#found[@]} == 4)) || {
    echo "deb 集合中包含非预期软件包" >&2
    exit 1
  }
  debs=()
  for required in "${required_packages[@]}"; do debs+=("${found[$required]}"); done
}

case $mode in
  build)
    "$ROOT/scripts/install-rime.sh"
    ;;
  download)
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl python3
    arch=$(dpkg --print-architecture)
    curl -fsSL https://api.github.com/repos/Huffer342-WSH/rime-ready/releases/latest \
      -o "$tmp/release.json" || {
      echo "当前还没有可下载的 GitHub Release" >&2
      exit 1
    }
    mapfile -t urls < <(
      python3 - "$arch" "$tmp/release.json" <<'PY'
import json
import sys

arch = sys.argv[1]
with open(sys.argv[2]) as f:
    data = json.load(f)
names = {"librime1", "librime-bin", "librime-plugin-lua", "librime-plugin-octagram"}
assets = [a for a in data["assets"] if a["name"].endswith(f"_{arch}.deb")
          and a["name"].split("_", 1)[0] in names]
if len(assets) != 4:
    raise SystemExit(f"expected 4 deb assets, got {len(assets)}")
for asset in assets:
    print(asset["browser_download_url"])
sums = next(a for a in data["assets"] if a["name"] == "SHA256SUMS-ubuntu-22.04")
print(sums["browser_download_url"])
PY
    )
    sums_url=${urls[-1]}
    unset 'urls[-1]'
    for url in "${urls[@]}"; do
      deb="$tmp/$(basename "$url")"
      curl -fL --retry 3 "$url" -o "$deb"
      debs+=("$deb")
    done
    curl -fL --retry 3 "$sums_url" -o "$tmp/SHA256SUMS"
    for deb in "${debs[@]}"; do
      expected=$(awk -v name="$(basename "$deb")" '$2 == name || $2 == "dist/" name {print $1}' "$tmp/SHA256SUMS")
      [[ -n $expected ]] || {
        echo "校验文件中找不到 $(basename "$deb")" >&2
        exit 1
      }
      echo "$expected  $deb" | sha256sum --check --status || {
        echo "deb SHA-256 校验失败" >&2
        exit 1
      }
    done
    verify_debs
    sudo apt-get install -y "${debs[@]}"
    ;;
  deb)
    needs_download=0
    for source in "${deb_sources[@]}"; do
      [[ $source =~ ^https?:// ]] && needs_download=1
    done
    if ((needs_download)); then
      sudo apt-get update
      sudo apt-get install -y ca-certificates curl
    fi
    index=0
    for source in "${deb_sources[@]}"; do
      if [[ $source =~ ^https?:// ]]; then
        deb="$tmp/input-$((index++)).deb"
        curl -fL --retry 3 "$source" -o "$deb"
        debs+=("$deb")
      elif [[ -d $source ]]; then
        while IFS= read -r deb; do debs+=("$deb"); done < <(find "$source" -maxdepth 1 -name '*.deb' -print | sort)
      else
        debs+=("$(realpath "$source")")
      fi
    done
    verify_debs
    sudo apt-get install -y "${debs[@]}"
    ;;
esac

if [[ $preset == runtime-only ]]; then
  echo "Rime 运行库和应用安装完成；未安装或激活输入法前端。"
  exit 0
fi

case $frontend in
  fcitx5) frontend_package=fcitx5-rime ;;
  ibus) frontend_package=ibus-rime ;;
esac
sudo apt-get update
sudo apt-get install -y "$frontend_package" curl unzip python3

ice_args=(--frontend "$frontend")
[[ $preset == ice-gram ]] && ice_args+=(--with-gram)
((activate)) || ice_args+=(--no-activate)
((start_frontend)) || ice_args+=(--no-start)
"$ROOT/scripts/install-rime-ice.sh" "${ice_args[@]}"
