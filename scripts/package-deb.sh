#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

target=$DEFAULT_TARGET
reuse=0
while (($#)); do
  case $1 in
    --target)
      target=$2
      shift 2
      ;;
    --reuse-build)
      reuse=1
      shift
      ;;
    *) die "未知参数：$1" ;;
  esac
done
load_target "$target"

if ((!reuse)) || [[ ! -f $STAGE_ROOT/usr/local/lib/librime.so.$RIME_VERSION ]]; then
  "$SCRIPT_DIR/build.sh" --target "$TARGET"
fi

arch=$(dpkg --print-architecture)
package_version="$RIME_VERSION-$PACKAGE_REVISION~$DEB_VERSION_SUFFIX"
package_name=rime-ready
package_root="$BUILD_ROOT/package-root"
rm -rf "$package_root"
mkdir -p "$package_root/DEBIAN" "$DIST_DIR"
cp -a "$STAGE_ROOT"/. "$package_root"/
install -m 0755 "$SCRIPT_DIR/install-rime-ice.sh" \
  "$package_root/usr/local/bin/rime-ready-install-ice"
mkdir -p "$package_root/usr/local/share/rime-ready"
cat >"$package_root/usr/local/share/rime-ready/build-info" <<EOF
rime_version=$RIME_VERSION
librime_ref=$LIBRIME_REF
librime_lua_ref=$LIBRIME_LUA_REF
librime_octagram_ref=$LIBRIME_OCTAGRAM_REF
RIME_ICE_RELEASE=$RIME_ICE_RELEASE
RIME_ICE_ASSET_ID=$RIME_ICE_ASSET_ID
RIME_ICE_SHA256=$RIME_ICE_SHA256
EOF

cat >"$package_root/DEBIAN/control" <<EOF
Package: $package_name
Version: $package_version
Architecture: $arch
Maintainer: rime-ready maintainers
Depends: fcitx5-rime, libboost-regex1.74.0, libicu70, libc6 (>= 2.35), libgcc-s1, libstdc++6, curl, unzip, python3
Section: utils
Priority: optional
Homepage: https://github.com/Huffer342-WSH/rime-ready
Description: Modern Rime runtime for Ubuntu 22.04
 Installs a pinned modern librime, librime-lua and librime-octagram under
 /usr/local, plus matching command-line tools and a per-user Rime Ice installer.
EOF
cat >"$package_root/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
ldconfig
EOF
cat >"$package_root/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
ldconfig
EOF
chmod 0755 "$package_root/DEBIAN/postinst" "$package_root/DEBIAN/postrm"

output="$DIST_DIR/${package_name}_${package_version}_${arch}.deb"
dpkg-deb --root-owner-group --build "$package_root" "$output"

tarball="$DIST_DIR/${package_name}_${package_version}_${arch}.tar.gz"
tar -C "$package_root" -czf "$tarball" usr/local
sha256sum "$output" "$tarball" >"$DIST_DIR/SHA256SUMS-$TARGET"
log "软件包已生成：$output"
