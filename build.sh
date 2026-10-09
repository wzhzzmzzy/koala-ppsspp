#!/bin/bash
set -euo pipefail
native_root="$(cd "$(dirname "$0")" && pwd)"
ppsspp_repo="${PPSSPP_SOURCE_DIR:-$native_root/vendor/ppsspp}"
export PPSSPP_SOURCE_DIR="$ppsspp_repo"
bash "$native_root/scripts/prepare-engine.sh"
mkdir -p "$native_root/output"
if ! git -C "$ppsspp_repo" apply --reverse --check "$native_root/patches/ppsspp-native.patch" 2>/dev/null; then
  git -C "$ppsspp_repo" apply --check "$native_root/patches/ppsspp-native.patch"
  git -C "$ppsspp_repo" apply "$native_root/patches/ppsspp-native.patch"
fi
cp "$native_root/Sources/KoalaNativeBridge.h" "$ppsspp_repo/UI/KoalaNativeBridge.h"
cp "$native_root/Sources/KoalaMetrics.h" "$ppsspp_repo/UI/KoalaMetrics.h"
cmake -S "$ppsspp_repo" -B "$ppsspp_repo/build" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DUSING_QT_UI=OFF -DUNITTEST=OFF -DHEADLESS=OFF -DUSE_DISCORD=OFF \
  -DUSE_MINIUPNPC=OFF -DUSE_SYSTEM_LIBPNG=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  > "$native_root/output/configure.log" 2>&1
cmake --build "$ppsspp_repo/build" --target PPSSPPSDL -j 8 \
  > "$native_root/output/engine-build.log" 2>&1
python3 "$native_root/scripts/package.py"
