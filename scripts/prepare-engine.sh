#!/bin/bash
set -euo pipefail
native_root="$(cd "$(dirname "$0")/.." && pwd)"
ppsspp_repo="${PPSSPP_SOURCE_DIR:-$native_root/vendor/ppsspp}"
upstream_revision="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["revision"])' "$native_root/upstream.json")"
upstream_ref="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["ref"])' "$native_root/upstream.json")"
upstream_url="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["repository"])' "$native_root/upstream.json")"
if [ ! -d "$ppsspp_repo" ]; then
  mkdir -p "$(dirname "$ppsspp_repo")"
  git clone --depth 1 --branch "$upstream_ref" "$upstream_url" "$ppsspp_repo"
fi
actual_revision="$(git -C "$ppsspp_repo" rev-parse HEAD)"
if [ "$actual_revision" != "$upstream_revision" ]; then
  echo "PPSSPP revision mismatch: expected $upstream_revision, got $actual_revision" >&2
  echo "Use a separate checkout at the pinned revision; existing files were not reset." >&2
  exit 1
fi
git -C "$ppsspp_repo" submodule update --init --recursive
printf 'PPSSPP source ready: %s (%s)\n' "$ppsspp_repo" "$upstream_revision"
