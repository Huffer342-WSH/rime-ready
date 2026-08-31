#!/usr/bin/env bash
# Reuse a pre-provisioned Ubuntu 22.04 image for local CT runs.
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
image=${RIME_READY_CT_IMAGE:-rime-ready-ubuntu22-ct:local}
rebuild=0
ct_args=()
while (($#)); do
  case $1 in
    --rebuild-image)
      rebuild=1
      shift
      ;;
    *)
      ct_args+=("$1")
      shift
      ;;
  esac
done

if ((rebuild)) || ! docker image inspect "$image" >/dev/null 2>&1; then
  docker build -t "$image" -f "$PROJECT_ROOT/docker/ubuntu-22.04/Dockerfile" "$PROJECT_ROOT"
fi

run_args=(--rm -v "$PROJECT_ROOT:/work" -w /work)
ice_cache=${RIME_ICE_CACHE:-$HOME/.cache/rime-ice-2026.06.30-full.zip}
if [[ -f $ice_cache ]]; then
  run_args+=(
    -v "$ice_cache:/cache/rime-ice-full.zip:ro"
    -e RIME_ICE_URL=file:///cache/rime-ice-full.zip
  )
fi

docker run "${run_args[@]}" "$image" scripts/ct.sh --skip-deps "${ct_args[@]}"
