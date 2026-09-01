#!/usr/bin/env bash
# Add one platform's tested debs to the signed, multi-distribution APT repository.
set -euo pipefail
umask 022

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

target=$DEFAULT_TARGET
repository_root=
dist_dir=
signing_key=
while (($#)); do
  case $1 in
    --target) target=${2:?--target 缺少值}; shift 2 ;;
    --repository-root) repository_root=${2:?--repository-root 缺少值}; shift 2 ;;
    --dist-dir) dist_dir=${2:?--dist-dir 缺少值}; shift 2 ;;
    --signing-key) signing_key=${2:?--signing-key 缺少值}; shift 2 ;;
    -h | --help)
      echo "用法：$0 --repository-root <目录> [--target ubuntu-22.04] [--dist-dir <目录>] [--signing-key <指纹>]"
      exit 0
      ;;
    *) die "未知参数：$1" ;;
  esac
done

[[ -n $repository_root ]] || die "必须指定 --repository-root"
load_target "$target"
: "${APT_REPOSITORY_FAMILY:?平台缺少 APT_REPOSITORY_FAMILY}"
: "${APT_SUITE:?平台缺少 APT_SUITE}"
: "${APT_COMPONENT:?平台缺少 APT_COMPONENT}"
: "${APT_ARCHITECTURE:?平台缺少 APT_ARCHITECTURE}"
dist_dir=${dist_dir:-$DIST_DIR}
repository_root=$(realpath -m "$repository_root")

for command in apt-ftparchive dpkg-deb dpkg-scanpackages gzip xz; do
  command -v "$command" >/dev/null || die "缺少命令：$command"
done
if [[ -n $signing_key ]]; then
  command -v gpg >/dev/null || die "缺少命令：gpg"
  gpg --batch --list-secret-keys "$signing_key" >/dev/null 2>&1 || die "找不到 APT 签名私钥：$signing_key"
fi

mapfile -t debs < <(find "$dist_dir" -maxdepth 1 -type f -name '*.deb' -print | sort)
((${#debs[@]} > 0)) || die "$dist_dir 中没有 deb"

base="$repository_root/apt/$APT_REPOSITORY_FAMILY"
pool="pool/$APT_SUITE/$APT_COMPONENT"
binary_dir="dists/$APT_SUITE/$APT_COMPONENT/binary-$APT_ARCHITECTURE"
mkdir -p "$base/$pool" "$base/$binary_dir" "$repository_root/keys"

for deb in "${debs[@]}"; do
  architecture=$(dpkg-deb --field "$deb" Architecture)
  [[ $architecture == "$APT_ARCHITECTURE" || $architecture == all ]] ||
    die "$(basename "$deb") 架构为 $architecture，目标要求 $APT_ARCHITECTURE"
  install -m 0644 "$deb" "$base/$pool/$(basename "$deb")"
done
install -m 0644 "$PROJECT_ROOT/packaging/apt/rime-ready-archive-keyring.gpg" \
  "$repository_root/keys/rime-ready-archive-keyring.gpg"
touch "$repository_root/.nojekyll"

(
  cd "$base"
  LC_ALL=C dpkg-scanpackages --multiversion "$pool" /dev/null >"$binary_dir/Packages"
  gzip -9fk "$binary_dir/Packages"
  xz -9e -fk "$binary_dir/Packages"
  mkdir -p "$binary_dir/by-hash/SHA256"
  for index in Packages Packages.gz Packages.xz; do
    hash=$(sha256sum "$binary_dir/$index" | awk '{print $1}')
    cp "$binary_dir/$index" "$binary_dir/by-hash/SHA256/$hash"
  done

  rm -f "dists/$APT_SUITE/InRelease" "dists/$APT_SUITE/Release" "dists/$APT_SUITE/Release.gpg"
  apt-ftparchive \
    -o "APT::FTPArchive::Release::Origin=rime-ready" \
    -o "APT::FTPArchive::Release::Label=rime-ready" \
    -o "APT::FTPArchive::Release::Suite=$APT_SUITE" \
    -o "APT::FTPArchive::Release::Codename=$APT_SUITE" \
    -o "APT::FTPArchive::Release::Architectures=$APT_ARCHITECTURE" \
    -o "APT::FTPArchive::Release::Components=$APT_COMPONENT" \
    -o "APT::FTPArchive::Release::Acquire-By-Hash=yes" \
    -o "APT::FTPArchive::Release::Description=Modern Rime packages for $PLATFORM_NAME" \
    release "dists/$APT_SUITE" >"dists/$APT_SUITE/Release"

  if [[ -n $signing_key ]]; then
    gpg --batch --yes --local-user "$signing_key" --clearsign \
      --output "dists/$APT_SUITE/InRelease" "dists/$APT_SUITE/Release"
    gpg --batch --yes --local-user "$signing_key" --armor --detach-sign \
      --output "dists/$APT_SUITE/Release.gpg" "dists/$APT_SUITE/Release"
  fi
)

log "已更新 $PLATFORM_NAME APT 仓库：apt/$APT_REPOSITORY_FAMILY，suite=$APT_SUITE，arch=$APT_ARCHITECTURE"
