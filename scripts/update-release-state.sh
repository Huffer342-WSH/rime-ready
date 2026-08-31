#!/usr/bin/env bash
# Record the upstream revisions included in a successfully published release.
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$PROJECT_ROOT/versions.env"
tag=${1:?用法：update-release-state.sh <release-tag> [output-file]}
output=${2:-$PROJECT_ROOT/upstream-state.json}

python3 - "$output" "$tag" "$RIME_VERSION" "$LIBRIME_REF" \
  "$LIBRIME_LUA_REF" "$LIBRIME_LUA_THIRDPARTY_REF" \
  "$LIBRIME_OCTAGRAM_REF" "$RIME_ICE_RELEASE" "$RIME_ICE_ASSET_ID" \
  "$RIME_ICE_SHA256" <<'PY'
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

output = Path(sys.argv[1])
data = {
    "schema_version": 1,
    "last_successful_release": {
        "tag": sys.argv[2],
        "published_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
    },
    "upstream": {
        "librime": {"release": sys.argv[3], "commit": sys.argv[4]},
        "librime_lua": {"ref": "master", "commit": sys.argv[5]},
        "librime_lua_thirdparty": {"ref": "thirdparty", "commit": sys.argv[6]},
        "librime_octagram": {"ref": "master", "commit": sys.argv[7]},
        "rime_ice": {
            "release": sys.argv[8],
            "asset_id": int(sys.argv[9]),
            "sha256": sys.argv[10],
        },
    },
}
output.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
PY
