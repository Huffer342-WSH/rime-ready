#!/usr/bin/env bash
# Build Debian-compatible replacements for Ubuntu 22.04's Rime binary packages.
set -euo pipefail
umask 022

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
multiarch=$(dpkg-architecture -qDEB_HOST_MULTIARCH)
stage_libdir="$STAGE_ROOT/usr/lib/$multiarch"

if ((!reuse)) || [[ ! -f $stage_libdir/librime.so.$RIME_VERSION ]]; then
  "$SCRIPT_DIR/build.sh" --target "$TARGET"
fi

arch=$(dpkg --print-architecture)
package_version="$RIME_VERSION-$PACKAGE_REVISION~$DEB_VERSION_SUFFIX"
SOURCE_DATE_EPOCH=$(git -c safe.directory="$LIBRIME_SOURCE" -C "$LIBRIME_SOURCE" show -s --format=%ct "$LIBRIME_REF")
export SOURCE_DATE_EPOCH
changelog_date=$(date --utc --date="@$SOURCE_DATE_EPOCH" --rfc-email)
package_root="$BUILD_ROOT/package-root"
libdir="usr/lib/$multiarch"
common_depends='libboost-regex1.74.0, libicu70, libc6 (>= 2.35), libgcc-s1, libstdc++6'
rm -rf "$package_root"
mkdir -p "$package_root" "$DIST_DIR"
rm -f "$DIST_DIR"/*.deb "$DIST_DIR"/*.tar.gz "$DIST_DIR"/SHA256SUMS-"$TARGET"

write_control() {
  local root=$1 package=$2 section=$3 depends=$4 description=$5 multi_arch=${6:-}
  mkdir -p "$root/DEBIAN" "$root/usr/share/doc/$package"
  cat >"$root/DEBIAN/control" <<EOF
Package: $package
Version: $package_version
Architecture: $arch
Maintainer: rime-ready maintainers <noreply@github.com>
${multi_arch:+Multi-Arch: $multi_arch
}Depends: $depends
Section: $section
Priority: optional
Homepage: https://github.com/Huffer342-WSH/rime-ready
Description: $description
 Rebuilt from pinned upstream Rime sources for Ubuntu 22.04.
EOF
  cat >"$root/usr/share/doc/$package/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: Rime Input Method Engine
Source: https://github.com/rime/librime

Files: *
Copyright: 2011-2026 Rime Developers
License: BSD-3-clause
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 .
 1. Redistributions of source code must retain the above copyright notice,
    this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright notice,
    this list of conditions and the following disclaimer in the documentation
    and/or other materials provided with the distribution.
 3. Neither the name of the copyright holder nor the names of its contributors
    may be used to endorse or promote products derived from this software
    without specific prior written permission.
 .
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES ARE DISCLAIMED.
EOF
  printf 'rime-ready (%s) jammy; urgency=medium\n\n  * Rebuild pinned modern Rime runtime for Ubuntu 22.04.\n\n -- rime-ready maintainers <noreply@github.com>  %s\n' \
    "$package_version" "$changelog_date" | gzip -n -9n >"$root/usr/share/doc/$package/changelog.Debian.gz"
}

core="$package_root/librime1"
write_control "$core" librime1 libs "$common_depends" \
  'Rime Input Method Engine - core library' same
mkdir -p "$core/$libdir"
install -m 0644 "$stage_libdir/librime.so.$RIME_VERSION" \
  "$core/$libdir/librime.so.$RIME_VERSION"
strip --strip-unneeded --remove-section=.comment "$core/$libdir/librime.so.$RIME_VERSION"
ln -s "librime.so.$RIME_VERSION" "$core/$libdir/librime.so.1"
echo "librime 1 librime1 (>= $package_version)" >"$core/DEBIAN/shlibs"
echo 'activate-noawait ldconfig' >"$core/DEBIAN/triggers"
cat >"$core/usr/share/doc/librime1/build-info" <<EOF
rime_version=$RIME_VERSION
librime_ref=$LIBRIME_REF
librime_lua_ref=$LIBRIME_LUA_REF
librime_octagram_ref=$LIBRIME_OCTAGRAM_REF
EOF

bin="$package_root/librime-bin"
write_control "$bin" librime-bin utils \
  "librime1 (= $package_version), $common_depends" \
  'Rime Input Method Engine - utilities'
mkdir -p "$bin/usr/bin"
for tool in rime_deployer rime_dict_manager rime_patch rime_table_decompiler; do
  install -m 0755 "$STAGE_ROOT/usr/bin/$tool" "$bin/usr/bin/$tool"
  strip --strip-unneeded --remove-section=.comment "$bin/usr/bin/$tool"
done
mkdir -p "$bin/usr/share/man/man1"
for tool in debian-rime-processor rime_deployer rime_dict_manager rime_patch rime_table_decompiler; do
  printf '.TH %s 1 "" "rime-ready" "User Commands"\n.SH NAME\n%s \\- Rime maintenance utility\n.SH DESCRIPTION\nThis command is provided by the version-matched librime-bin package.\n' \
    "$tool" "$tool" | gzip -9n >"$bin/usr/share/man/man1/$tool.1.gz"
done
install -m 0755 "$PROJECT_ROOT/packaging/debian/debian-rime-processor" \
  "$bin/usr/bin/debian-rime-processor"

for plugin in lua octagram; do
  package="librime-plugin-$plugin"
  root="$package_root/$package"
  write_control "$root" "$package" libs \
    "librime1 (= $package_version), $common_depends" \
    "Rime Input Method Engine - ${plugin^} plugin" same
  mkdir -p "$root/$libdir/rime-plugins"
  install -m 0644 \
    "$stage_libdir/rime-plugins/librime-$plugin.so.$RIME_VERSION" \
    "$root/$libdir/rime-plugins/librime-$plugin.so"
  strip --strip-unneeded --remove-section=.comment "$root/$libdir/rime-plugins/librime-$plugin.so"
done

for package in librime1 librime-bin librime-plugin-lua librime-plugin-octagram; do
  (
    cd "$package_root/$package"
    find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums
  )
done

outputs=()
for package in librime1 librime-bin librime-plugin-lua librime-plugin-octagram; do
  output="$DIST_DIR/${package}_${package_version}_${arch}.deb"
  dpkg-deb --root-owner-group --build "$package_root/$package" "$output"
  outputs+=("$output")
done
(
  cd "$DIST_DIR"
  sha256sum "${outputs[@]##*/}" >"SHA256SUMS-$TARGET"
)
log "已生成 Ubuntu APT 兼容包：${outputs[*]}"
