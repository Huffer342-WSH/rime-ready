#!/usr/bin/env bash
# One command: build/install modern Rime, then install Rime Ice for this user.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
with_gram=()
if [[ ${1:-} == --with-gram ]]; then
  with_gram=(--with-gram)
elif (($#)); then
  echo "用法：$0 [--with-gram]" >&2
  exit 1
fi
"$ROOT/scripts/install-rime.sh"
/usr/local/bin/rime-ready-install-ice "${with_gram[@]}"
