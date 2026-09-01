#!/usr/bin/env bash
# Self-contained installer: suitable for `curl ... | bash`.
set -euo pipefail

mode=apt
preset=ice
frontend=fcitx5
activate=1
start_frontend=1
deb_sources=()
required_packages=(librime1 librime-bin librime-plugin-lua librime-plugin-octagram)

# Pinned versions used by --build and as a fallback for the Rime Ice download.
RIME_VERSION=1.17.0
LIBRIME_REF=33e78140250125871856cdc5b42ddc6a5fcd3cd4
LIBRIME_LUA_REF=ec52e48ea18f11af37717a01c337f853215cf70b
LIBRIME_LUA_THIRDPARTY_REF=fa40fadd8af1e5b1fbd55703ccbd54476956d74c
LIBRIME_OCTAGRAM_REF=57d18b9f58e5284bd891d559f6bdd16cf60341e9
RIME_ICE_RELEASE=2026.06.30
RIME_ICE_SHA256=675d23b070be00e1b800f9a6db033ef98f4493cd5b568ed8aa3b3541769c46ac
PACKAGE_REVISION=1
APT_REPOSITORY_URL=https://huffer342-wsh.github.io/rime-ready
APT_KEY_FINGERPRINT=04DFAF1DECE854F57D04199DE7E0727BD4AEE87A

usage() {
  cat <<'EOF'
用法：
  curl -fsSL https://raw.githubusercontent.com/Huffer342-WSH/rime-ready/main/install.sh | bash -s -- [选项]
  ./install.sh [选项]

运行库来源：
  --apt                 从 rime-ready APT 仓库安装四个标准 deb（默认）
  --download            从最新 GitHub Release 下载四个标准 deb
  --build               在本机从固定源码编译四个标准 deb
  --deb <目录/文件/URL> 安装指定 deb；可重复使用

预设：
  --preset runtime-only 只安装 Rime 运行库和应用
  --preset ice          安装运行库、稳定版雾凇并设置输入法（默认）
  --preset ice-gram     在 ice 基础上安装万象 Gram

输入法：
  --frontend fcitx5|ibus 选择 Ubuntu APT 输入法前端（默认 fcitx5）
  --no-activate          安装方案但不修改当前用户的输入法设置
  --no-start             设置输入法但不立即启动前端
EOF
}

die() {
  echo "[rime-ready] $*" >&2
  exit 1
}

log() {
  echo "[rime-ready] $*"
}

while (($#)); do
  case $1 in
    --apt) mode=apt; deb_sources=(); shift ;;
    --download) mode=download; deb_sources=(); shift ;;
    --build) mode=build; deb_sources=(); shift ;;
    --deb) mode=deb; deb_sources+=("${2:?--deb 缺少目录、文件或 URL}"); shift 2 ;;
    --preset) preset=${2:?--preset 缺少值}; shift 2 ;;
    --frontend) frontend=${2:?--frontend 缺少值}; shift 2 ;;
    --with-gram) preset=ice-gram; shift ;;
    --no-activate) activate=0; shift ;;
    --no-start) start_frontend=0; shift ;;
    -h | --help) usage; exit 0 ;;
    *) die "未知参数：$1" ;;
  esac
done
case $preset in runtime-only | ice | ice-gram) ;; *) die "不支持预设：$preset" ;; esac
case $frontend in fcitx5 | ibus) ;; *) die "不支持前端：$frontend" ;; esac
[[ $EUID -ne 0 ]] || die "请以普通桌面用户运行，不要使用 sudo。"

[[ -r /etc/os-release ]] || die "无法识别当前系统"
# shellcheck disable=SC1091
source /etc/os-release
[[ ${ID:-} == ubuntu && ${VERSION_ID:-} == 22.04 ]] ||
  die "目前只支持 Ubuntu 22.04，检测到 ${PRETTY_NAME:-未知系统}"
[[ $(dpkg --print-architecture) == amd64 ]] || die "目前只支持 amd64 架构"

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
    [[ -n ${found[$required]:-} ]] || die "缺少标准包：$required"
  done
  ((${#found[@]} == 4)) || die "deb 集合中包含非预期软件包"
  debs=()
  for required in "${required_packages[@]}"; do debs+=("${found[$required]}"); done
}

clone_at_ref() {
  local url=$1 dir=$2 ref=$3
  git clone --filter=blob:none --no-checkout "$url" "$dir"
  git -C "$dir" fetch --depth=1 origin "$ref"
  git -C "$dir" checkout --detach --force FETCH_HEAD
}

build_debs() {
  local source_root=$tmp/build/source
  local librime_source=$source_root/librime stage_root=$tmp/build/stage
  local package_root=$tmp/build/package-root dist_dir=$tmp/dist
  local multiarch stage_libdir package_version file_version source_date_epoch changelog_date
  local common_depends core bin plugin package root output tool
  local build_packages=(ca-certificates curl git build-essential cmake pkg-config python3
    libboost1.74-dev libboost-regex1.74-dev libicu-dev unzip dpkg-dev fakeroot)

  log "安装 Ubuntu 22.04 构建依赖"
  sudo apt-get update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${build_packages[@]}"
  mkdir -p "$source_root" "$dist_dir"

  log "获取固定版本的上游源码"
  clone_at_ref https://github.com/rime/librime.git "$librime_source" "$LIBRIME_REF"
  git -C "$librime_source" submodule update --init --depth=1
  rm -rf "$librime_source/plugins/lua" "$librime_source/plugins/octagram"
  clone_at_ref https://github.com/hchunhui/librime-lua.git "$librime_source/plugins/lua" "$LIBRIME_LUA_REF"
  clone_at_ref https://github.com/lotem/librime-octagram.git "$librime_source/plugins/octagram" "$LIBRIME_OCTAGRAM_REF"
  rm -rf "$librime_source/plugins/lua/thirdparty"
  clone_at_ref https://github.com/hchunhui/librime-lua.git \
    "$librime_source/plugins/lua/thirdparty" "$LIBRIME_LUA_THIRDPARTY_REF"

  python3 - "$librime_source/deps.mk" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
marker = '-DCMAKE_BUILD_TYPE:STRING="Release" \\\n'
if text.count(marker) < 5:
    raise SystemExit("deps.mk layout changed")
text = text.replace(marker, '-DCMAKE_POSITION_INDEPENDENT_CODE:BOOL=ON \\\n' + marker)
if '-DWITH_UNWIND=none' not in text:
    needle = '-DWITH_GFLAGS:BOOL=OFF \\\n'
    if needle not in text:
        raise SystemExit("deps.mk layout changed: glog flags not found")
    text = text.replace(needle, needle + '-DWITH_UNWIND=none \\\n', 1)
path.write_text(text)
PY
  make -C "$librime_source" deps

  log "编译 Rime $RIME_VERSION、Lua 和 Octagram"
  multiarch=$(dpkg-architecture -qDEB_HOST_MULTIARCH)
  cmake -S "$librime_source" -B "$librime_source/build" \
    -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR="lib/$multiarch" \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_TEST=ON -DBUILD_MERGED_PLUGINS=OFF \
    -DENABLE_EXTERNAL_PLUGINS=ON -DLINUX=ON -DBOOST_ROOT=/usr \
    -DCMAKE_PREFIX_PATH="$librime_source;/usr" \
    -DCMAKE_INCLUDE_PATH="$librime_source/include;/usr/include" \
    -DCMAKE_LIBRARY_PATH="$librime_source/lib;/usr/lib/$multiarch"
  cmake --build "$librime_source/build" --parallel "$(nproc)"
  DESTDIR="$stage_root" cmake --install "$librime_source/build"
  rm -rf "$stage_root/usr/include" "$stage_root/usr/lib/$multiarch/pkgconfig" \
    "$stage_root/usr/lib/$multiarch/cmake" "$stage_root/usr/share/cmake"
  for plugin in lua octagram; do
    mv "$stage_root/usr/lib/$multiarch/rime-plugins/librime-$plugin.so" \
      "$stage_root/usr/lib/$multiarch/rime-plugins/librime-$plugin.so.$RIME_VERSION"
  done
  install -d "$stage_root/usr/share/rime-ready"
  cat >"$stage_root/usr/share/rime-ready/build-info" <<EOF
RIME_ICE_RELEASE=$RIME_ICE_RELEASE
RIME_ICE_SHA256=$RIME_ICE_SHA256
EOF

  stage_libdir="$stage_root/usr/lib/$multiarch"
  package_version="$RIME_VERSION-$PACKAGE_REVISION~ubuntu22.04"
  file_version=${package_version//\~/.}
  source_date_epoch=$(git -C "$librime_source" show -s --format=%ct "$LIBRIME_REF")
  changelog_date=$(date --utc --date="@$source_date_epoch" --rfc-email)
  common_depends='libboost-regex1.74.0, libicu70, libc6 (>= 2.35), libgcc-s1, libstdc++6'
  mkdir -p "$package_root" "$dist_dir"

  write_control() {
    local control_root=$1 control_package=$2 section=$3 depends=$4 description=$5 multi_arch=${6:-}
    mkdir -p "$control_root/DEBIAN" "$control_root/usr/share/doc/$control_package"
    cat >"$control_root/DEBIAN/control" <<EOF
Package: $control_package
Version: $package_version
Architecture: amd64
Maintainer: rime-ready maintainers <noreply@github.com>
${multi_arch:+Multi-Arch: $multi_arch
}Depends: $depends
Section: $section
Priority: optional
Homepage: https://github.com/Huffer342-WSH/rime-ready
Description: $description
 Rebuilt from pinned upstream Rime sources for Ubuntu 22.04.
EOF
    printf 'rime-ready (%s) jammy; urgency=medium\n\n  * Rebuild pinned modern Rime runtime for Ubuntu 22.04.\n\n -- rime-ready maintainers <noreply@github.com>  %s\n' \
      "$package_version" "$changelog_date" | gzip -9n >"$control_root/usr/share/doc/$control_package/changelog.Debian.gz"
  }

  core="$package_root/librime1"
  write_control "$core" librime1 libs "$common_depends" 'Rime Input Method Engine - core library' same
  mkdir -p "$core/usr/lib/$multiarch"
  install -m 0644 "$stage_libdir/librime.so.$RIME_VERSION" "$core/usr/lib/$multiarch/"
  strip --strip-unneeded --remove-section=.comment "$core/usr/lib/$multiarch/librime.so.$RIME_VERSION"
  ln -s "librime.so.$RIME_VERSION" "$core/usr/lib/$multiarch/librime.so.1"
  echo "librime 1 librime1 (>= $package_version)" >"$core/DEBIAN/shlibs"
  echo 'activate-noawait ldconfig' >"$core/DEBIAN/triggers"

  bin="$package_root/librime-bin"
  write_control "$bin" librime-bin utils "librime1 (= $package_version), $common_depends" \
    'Rime Input Method Engine - utilities'
  mkdir -p "$bin/usr/bin" "$bin/usr/share/man/man1"
  for tool in rime_deployer rime_dict_manager rime_patch rime_table_decompiler; do
    install -m 0755 "$stage_root/usr/bin/$tool" "$bin/usr/bin/$tool"
    strip --strip-unneeded --remove-section=.comment "$bin/usr/bin/$tool"
  done
  cat >"$bin/usr/bin/debian-rime-processor" <<'SH'
#!/bin/sh
set -e
RIME_DATA_DIR=/usr/share/rime-data
case ${1:-} in
  '') ;;
  default)
    for file in "$RIME_DATA_DIR"/*.*; do [ ! -f "$file" ] || ln -sf "$file" .; done
    for schema in ./*.schema.yaml; do [ ! -f "$schema" ] || rime_deployer --compile "$schema"; done
    find . -maxdepth 1 -type l -delete ;;
  *) echo "用法：debian-rime-processor [default]" >&2; exit 1 ;;
esac
SH
  chmod 0755 "$bin/usr/bin/debian-rime-processor"

  for plugin in lua octagram; do
    package="librime-plugin-$plugin"
    root="$package_root/$package"
    write_control "$root" "$package" libs "librime1 (= $package_version), $common_depends" \
      "Rime Input Method Engine - ${plugin^} plugin" same
    mkdir -p "$root/usr/lib/$multiarch/rime-plugins"
    install -m 0644 "$stage_libdir/rime-plugins/librime-$plugin.so.$RIME_VERSION" \
      "$root/usr/lib/$multiarch/rime-plugins/librime-$plugin.so"
    strip --strip-unneeded --remove-section=.comment "$root/usr/lib/$multiarch/rime-plugins/librime-$plugin.so"
  done

  for package in "${required_packages[@]}"; do
    (cd "$package_root/$package" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
    output="$dist_dir/${package}_${file_version}_amd64.deb"
    dpkg-deb --root-owner-group --build "$package_root/$package" "$output"
    debs+=("$output")
  done
  verify_debs
  sudo apt-get install -y "${debs[@]}"
}

install_apt_repository_debs() {
  local key_file=$tmp/rime-ready-archive-keyring.gpg
  local source_file=$tmp/rime-ready.list actual_fingerprint
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl gnupg
  curl -fsSL "$APT_REPOSITORY_URL/keys/rime-ready-archive-keyring.gpg" -o "$key_file" ||
    die "无法下载 rime-ready APT 仓库公钥"
  actual_fingerprint=$(gpg --batch --show-keys --with-colons "$key_file" |
    awk -F: '$1 == "fpr" {print $10; exit}')
  [[ $actual_fingerprint == "$APT_KEY_FINGERPRINT" ]] ||
    die "APT 仓库公钥指纹不匹配：$actual_fingerprint"
  sudo install -m 0644 "$key_file" /usr/share/keyrings/rime-ready-archive-keyring.gpg
  cat >"$source_file" <<EOF
deb [arch=amd64 signed-by=/usr/share/keyrings/rime-ready-archive-keyring.gpg] $APT_REPOSITORY_URL/apt/ubuntu jammy main
EOF
  sudo install -m 0644 "$source_file" /etc/apt/sources.list.d/rime-ready.list
  sudo apt-get update
  sudo apt-get install -y "${required_packages[@]}"
}

download_release_debs() {
  local arch latest_url tag sums_url url deb expected
  local -a urls
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl python3
  arch=$(dpkg --print-architecture)
  latest_url=$(curl -fsSL -o /dev/null -w '%{url_effective}' \
    https://github.com/Huffer342-WSH/rime-ready/releases/latest) ||
    die "无法查询最新 GitHub Release"
  tag=${latest_url##*/}
  [[ -n $tag && $tag != latest ]] || die "当前还没有可下载的 GitHub Release"
  curl -fsSL \
    "https://github.com/Huffer342-WSH/rime-ready/releases/expanded_assets/$tag" \
    -o "$tmp/release-assets.html" || die "无法读取 GitHub Release 资源列表"
  python3 - "$arch" "$tag" "$tmp/release-assets.html" >"$tmp/release-urls" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import sys

arch, tag, page = sys.argv[1:]
prefix = f"/Huffer342-WSH/rime-ready/releases/download/{tag}/"
names = {"librime1", "librime-bin", "librime-plugin-lua", "librime-plugin-octagram"}

class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.hrefs = []

    def handle_starttag(self, _tag, attrs):
        href = dict(attrs).get("href", "")
        if href.startswith(prefix):
            self.hrefs.append(href)

links = Links()
links.feed(Path(page).read_text())
debs = [href for href in links.hrefs
        if href.endswith(f"_{arch}.deb")
        and href.removeprefix(prefix).split("_", 1)[0] in names]
sums = [href for href in links.hrefs
        if href.removeprefix(prefix) == "SHA256SUMS-ubuntu-22.04"]
if len(debs) != 4 or len(sums) != 1:
    raise SystemExit(f"expected 4 deb assets and one checksum, got {len(debs)} and {len(sums)}")
for href in debs + sums:
    print(f"https://github.com{href}")
PY
  mapfile -t urls <"$tmp/release-urls"
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
    [[ -n $expected ]] || die "校验文件中找不到 $(basename "$deb")"
    echo "$expected  $deb" | sha256sum --check --status || die "deb SHA-256 校验失败"
  done
  verify_debs
  sudo apt-get install -y "${debs[@]}"
}

install_given_debs() {
  local needs_download=0 index=0 source deb
  for source in "${deb_sources[@]}"; do [[ $source =~ ^https?:// ]] && needs_download=1; done
  if ((needs_download)); then
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl
  fi
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
}

configure_input_method() {
  local cache_dir profile
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
        text = text.replace("[GroupOrder]", f"[Groups/0/Items/{item}]\nName=rime\nLayout=\n\n[GroupOrder]", 1)
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
  esac
  log "已为当前用户设置 $frontend Rime 输入法。"
}

install_rime_ice() {
  local rime_dir ice_url timestamp backup model shared_dir command
  case $frontend in
    fcitx5) rime_dir=${XDG_DATA_HOME:-$HOME/.local/share}/fcitx5/rime ;;
    ibus) rime_dir=${XDG_CONFIG_HOME:-$HOME/.config}/ibus/rime ;;
  esac
  for command in curl unzip rime_deployer; do command -v "$command" >/dev/null || die "缺少命令：$command"; done

  if [[ -f /usr/share/rime-ready/build-info ]]; then
    # shellcheck disable=SC1091
    source /usr/share/rime-ready/build-info
  fi
  ice_url=${RIME_ICE_URL:-https://github.com/iDvel/rime-ice/releases/download/$RIME_ICE_RELEASE/full.zip}
  curl -L --fail --retry 3 "$ice_url" -o "$tmp/rime-ice.zip"
  if [[ -n ${RIME_ICE_SHA256:-} ]]; then
    echo "$RIME_ICE_SHA256  $tmp/rime-ice.zip" | sha256sum --check --status || die "雾凇拼音压缩包校验失败"
  fi
  unzip -q "$tmp/rime-ice.zip" -d "$tmp/new-rime"

  timestamp=$(date +%Y%m%d-%H%M%S)
  backup="${rime_dir}-backup-${timestamp}"
  if ((activate)); then
    if [[ $frontend == fcitx5 ]]; then
      fcitx5-remote -e 2>/dev/null || true
      for _ in $(seq 1 40); do pgrep -x fcitx5 >/dev/null || break; sleep 0.25; done
    else
      ibus exit 2>/dev/null || true
    fi
  fi
  [[ ! -d $rime_dir ]] || mv "$rime_dir" "$backup"
  mkdir -p "$(dirname "$rime_dir")"
  mv "$tmp/new-rime" "$rime_dir"
  [[ ! -d $backup/rime_ice.userdb ]] || cp -a "$backup/rime_ice.userdb" "$rime_dir/"
  cat >"$rime_dir/default.custom.yaml" <<'EOF'
patch:
  schema_list:
    - schema: rime_ice
EOF

  if [[ $preset == ice-gram ]]; then
    model=wanxiang-lts-zh-hans.gram
    if [[ -f $backup/$model ]]; then
      mv "$backup/$model" "$rime_dir/$model"
    else
      curl -L --fail --retry 3 "https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/$model" -o "$rime_dir/$model"
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
  ((activate)) && configure_input_method
  [[ -f $rime_dir/build/rime_ice.schema.yaml ]] || die "雾凇拼音部署产物缺失"
  log "雾凇拼音安装完成：$rime_dir"
  [[ ! -d $backup ]] || log "原配置备份：$backup"
}

case $mode in
  apt) install_apt_repository_debs ;;
  build) build_debs ;;
  download) download_release_debs ;;
  deb) install_given_debs ;;
esac

if [[ $preset == runtime-only ]]; then
  log "Rime 运行库和应用安装完成；未安装或激活输入法前端。"
  exit 0
fi
case $frontend in fcitx5) frontend_package=fcitx5-rime ;; ibus) frontend_package=ibus-rime ;; esac
sudo apt-get update
sudo apt-get install -y "$frontend_package" curl unzip python3
install_rime_ice
