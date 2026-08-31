#!/usr/bin/env bash
# Poll upstream versions. With --update, rewrite versions.env when they change.
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
ice_release_json=$(curl -fsSL https://api.github.com/repos/iDvel/rime-ice/releases/latest)
mapfile -t latest_ice < <(python3 -c '
import json, sys
d = json.load(sys.stdin)
a = next(a for a in d["assets"] if a["name"] == "full.zip")
digest = a.get("digest") or ""
print(d["tag_name"])
print(a["id"])
print(digest.removeprefix("sha256:"))
' <<<"$ice_release_json")
[[ -n ${latest_ice[2]} ]] || {
  echo "雾凇 full.zip 没有 SHA-256" >&2
  exit 1
}
resolve_ref() {
  local repo=$1 ref=$2
  local output resolved
  output=$(git ls-remote "https://github.com/$repo.git" \
    "refs/tags/$ref^{}" "refs/tags/$ref" "refs/heads/$ref")
  resolved=$(awk -v ref="$ref" '$2 == "refs/tags/" ref "^{}" {print $1; exit}' <<<"$output")
  if [[ -z $resolved ]]; then
    resolved=$(awk 'NR == 1 {print $1}' <<<"$output")
  fi
  [[ -n $resolved ]] || {
    echo "无法解析 $repo 的 $ref" >&2
    exit 1
  }
  printf '%s\n' "$resolved"
}

new_librime_ref=$(resolve_ref rime/librime "$latest_tag")
new_lua_ref=$(resolve_ref hchunhui/librime-lua master)
new_lua_thirdparty_ref=$(resolve_ref hchunhui/librime-lua thirdparty)
new_octagram_ref=$(resolve_ref lotem/librime-octagram master)

mapfile -t released < <(
  python3 - "$state_file" <<'PY'
import json
import sys
with open(sys.argv[1]) as f:
    u = json.load(f)["upstream"]
print(u["librime"]["release"])
print(u["librime"]["commit"])
print(u["librime_lua"]["commit"])
print(u["librime_lua_thirdparty"]["commit"])
print(u["librime_octagram"]["commit"])
print(u["rime_ice"]["release"])
print(u["rime_ice"]["asset_id"])
print(u["rime_ice"]["sha256"])
PY
)

upstream_changed=false
if [[ $latest_version != "${released[0]}" ||
  $new_librime_ref != "${released[1]}" ||
  $new_lua_ref != "${released[2]}" ||
  $new_lua_thirdparty_ref != "${released[3]}" ||
  $new_octagram_ref != "${released[4]}" ||
  ${latest_ice[0]} != "${released[5]}" ||
  ${latest_ice[1]} != "${released[6]}" ||
  ${latest_ice[2]} != "${released[7]}" ]]; then
  upstream_changed=true
fi

version_file_changed=false
if [[ $latest_version != "$RIME_VERSION" ||
  $new_librime_ref != "$LIBRIME_REF" ||
  $new_lua_ref != "$LIBRIME_LUA_REF" ||
  $new_lua_thirdparty_ref != "$LIBRIME_LUA_THIRDPARTY_REF" ||
  $new_octagram_ref != "$LIBRIME_OCTAGRAM_REF" ||
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
    "$latest_version" "$new_librime_ref" "$new_lua_ref" \
    "$new_lua_thirdparty_ref" "$new_octagram_ref" \
    "${latest_ice[0]}" "${latest_ice[1]}" "${latest_ice[2]}" \
    "$revision" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
keys = {
    "RIME_VERSION": sys.argv[2],
    "LIBRIME_REF": sys.argv[3],
    "LIBRIME_LUA_REF": sys.argv[4],
    "LIBRIME_LUA_THIRDPARTY_REF": sys.argv[5],
    "LIBRIME_OCTAGRAM_REF": sys.argv[6],
    "RIME_ICE_RELEASE": sys.argv[7],
    "RIME_ICE_ASSET_ID": sys.argv[8],
    "RIME_ICE_SHA256": sys.argv[9],
    "PACKAGE_REVISION": sys.argv[10],
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
librime_lua_ref=$new_lua_ref
librime_lua_thirdparty_ref=$new_lua_thirdparty_ref
librime_octagram_ref=$new_octagram_ref
rime_ice_release=${latest_ice[0]}
rime_ice_asset_id=${latest_ice[1]}
rime_ice_sha256=${latest_ice[2]}
package_revision=$revision
EOF
