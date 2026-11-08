#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
module_dir="$1"

upstream_jni="$repo_root/media/libraries/decoder_ffmpeg/src/main/jni"
ffmpeg_tag="$(git -C "$repo_root" config -f .gitmodules submodule.ffmpeg.branch)"

mkdir -p "$module_dir/jni/ffmpeg"
cp "$upstream_jni/build_ffmpeg.sh" "$upstream_jni/CMakeLists.txt" "$upstream_jni/ffmpeg_jni.cc" "$module_dir/jni/"
git -C "$repo_root/ffmpeg" archive HEAD | tar -x -C "$module_dir/jni/ffmpeg"
"$repo_root/scripts/apply-ffmpeg-patch.sh" "$module_dir/jni/ffmpeg"
printf '%s\n' "$ffmpeg_tag" >"$module_dir/jni/ffmpeg/VERSION"
