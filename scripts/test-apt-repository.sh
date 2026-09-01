#!/usr/bin/env bash
# Validate the generated APT repository layout, metadata and public key.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
target=${1:-$DEFAULT_TARGET}
load_target "$target"

repository_root=$(mktemp -d)
trap 'rm -rf "$repository_root"' EXIT
"$SCRIPT_DIR/publish-apt-repository.sh" \
  --target "$target" \
  --dist-dir "$DIST_DIR" \
  --repository-root "$repository_root"

base="$repository_root/apt/$APT_REPOSITORY_FAMILY"
binary_dir="$base/dists/$APT_SUITE/$APT_COMPONENT/binary-$APT_ARCHITECTURE"
packages="$binary_dir/Packages"
release="$base/dists/$APT_SUITE/Release"
[[ -s $packages && -s $release ]]
[[ $(grep -c '^Package: ' "$packages") == 4 ]]
grep -q "^Architectures: $APT_ARCHITECTURE$" "$release"
grep -q "^Codename: $APT_SUITE$" "$release"
grep -q '^Acquire-By-Hash: yes$' "$release"

for index in Packages Packages.gz Packages.xz; do
  hash=$(sha256sum "$binary_dir/$index" | awk '{print $1}')
  cmp "$binary_dir/$index" "$binary_dir/by-hash/SHA256/$hash"
done

expected_fingerprint=$(cat "$PROJECT_ROOT/packaging/apt/signing-key.fingerprint")
actual_fingerprint=$(gpg --batch --show-keys --with-colons \
  "$PROJECT_ROOT/packaging/apt/rime-ready-archive-keyring.gpg" |
  awk -F: '$1 == "fpr" {print $10; exit}')
[[ $actual_fingerprint == "$expected_fingerprint" ]]
grep -q "^APT_KEY_FINGERPRINT=$expected_fingerprint$" "$PROJECT_ROOT/install.sh"

echo "$PLATFORM_NAME APT 仓库目录、索引、By-Hash 和公钥检查通过"
