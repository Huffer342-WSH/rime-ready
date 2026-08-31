#!/usr/bin/env bash
# Poll only stable upstream releases; plugin development branches are not tracked.
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$PROJECT_ROOT/versions.env"
state_file="$PROJECT_ROOT/upstream-state.json"
update=0
if [[ ${1:-} == --update ]]; then
  update=1
elif (($#)); then
  echo "用法：$0 [--update]" >&2
  exit 1
fi
[[ -f $state_file ]] || {
  echo "缺少 $state_file" >&2
  exit 1
}

latest_tag=$(curl -fsSL https://api.github.com/repos/rime/librime/releases/latest |
  python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')
latest_version=${latest_tag#v}
resolve_tag() {
  local repo=$1 tag=$2 output resolved
  output=$(git ls-remote "https://github.com/$repo.git" \
    "refs/tags/$tag^{}" "refs/tags/$tag")
  resolved=$(awk -v tag="$tag" '$2 == "refs/tags/" tag "^{}" {print $1; exit}' <<<"$output")
  [[ -n $resolved ]] || resolved=$(awk 'NR == 1 {print $1}' <<<"$output")
  [[ -n $resolved ]] || {
    echo "无法解析 $repo 的 Tag $tag" >&2
    exit 1
  }
  printf '%s\n' "$resolved"
}
new_librime_ref=$(resolve_tag rime/librime "$latest_tag")

# Rime Ice's `latest` endpoint may point to the mutable nightly release. Select
# the newest dated, non-prerelease Release instead.
ice_releases_json=$(curl -fsSL \
  'https://api.github.com/repos/iDvel/rime-ice/releases?per_page=100')
mapfile -t latest_ice < <(python3 -c '
import json, re, sys
releases = json.load(sys.stdin)
stable = [r for r in releases if not r["draft"] and not r["prerelease"]
          and re.fullmatch(r"[0-9]{4}\.[0-9]{2}\.[0-9]{2}", r["tag_name"])]
r = max(stable, key=lambda item: item["tag_name"])
a = next(a for a in r["assets"] if a["name"] == "full.zip")
digest = (a.get("digest") or "").removeprefix("sha256:")
print(r["tag_name"])
print(a["id"])
print(digest)
' <<<"$ice_releases_json")
[[ -n ${latest_ice[2]} ]] || {
  echo "稳定版雾凇 full.zip 没有 SHA-256" >&2
  exit 1
}

mapfile -t released < <(
  python3 - "$state_file" <<'PY'
import json
import sys
with open(sys.argv[1]) as f:
    u = json.load(f)["upstream"]
print(u["librime"]["release"])
print(u["librime"]["commit"])
print(u["rime_ice"]["release"])
print(u["rime_ice"]["asset_id"])
print(u["rime_ice"]["sha256"])
PY
)

upstream_changed=false
if [[ $latest_version != "${released[0]}" ||
  $new_librime_ref != "${released[1]}" ||
  ${latest_ice[0]} != "${released[2]}" ||
  ${latest_ice[1]} != "${released[3]}" ||
  ${latest_ice[2]} != "${released[4]}" ]]; then
  upstream_changed=true
fi

version_file_changed=false
if [[ $latest_version != "$RIME_VERSION" ||
  $new_librime_ref != "$LIBRIME_REF" ||
  ${latest_ice[0]} != "$RIME_ICE_RELEASE" ||
  ${latest_ice[1]} != "$RIME_ICE_ASSET_ID" ||
  ${latest_ice[2]} != "$RIME_ICE_SHA256" ]]; then
  version_file_changed=true
fi

revision=$PACKAGE_REVISION
if [[ $version_file_changed == true && $latest_version != "$RIME_VERSION" ]]; then
  revision=1
elif [[ $version_file_changed == true ]]; then
  revision=$((PACKAGE_REVISION + 1))
fi

if ((update)) && [[ $version_file_changed == true ]]; then
  python3 - "$PROJECT_ROOT/versions.env" \
    "$latest_version" "$new_librime_ref" \
    "${latest_ice[0]}" "${latest_ice[1]}" "${latest_ice[2]}" \
    "$revision" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
keys = {
    "RIME_VERSION": sys.argv[2],
    "LIBRIME_REF": sys.argv[3],
    "RIME_ICE_RELEASE": sys.argv[4],
    "RIME_ICE_ASSET_ID": sys.argv[5],
    "RIME_ICE_SHA256": sys.argv[6],
    "PACKAGE_REVISION": sys.argv[7],
}
text = path.read_text()
for key, value in keys.items():
    text, count = re.subn(rf"(?m)^{key}=.*$", f"{key}={value}", text)
    if count != 1:
        raise SystemExit(f"cannot update {key}")
path.write_text(text)
PY
fi

pending_release=false
if [[ $upstream_changed == true && $version_file_changed == false ]]; then
  pending_release=true
fi

cat <<EOF
changed=$upstream_changed
version_file_changed=$version_file_changed
pending_release=$pending_release
rime_version=$latest_version
librime_ref=$new_librime_ref
rime_ice_release=${latest_ice[0]}
rime_ice_asset_id=${latest_ice[1]}
rime_ice_sha256=${latest_ice[2]}
package_revision=$revision
EOF
