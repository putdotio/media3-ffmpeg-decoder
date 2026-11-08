#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resources_dir="$1"
ndk_path="$2"
min_sdk="$3"
module_dir="$4"
shift 4
decoders=("$@")

case "$(uname -s)" in
  Linux) host_platform=linux-x86_64 ;;
  Darwin) host_platform=darwin-x86_64 ;;
  *) echo "unsupported host: $(uname -s)" >&2; exit 1 ;;
esac

upstream_jni="$repo_root/media/libraries/decoder_ffmpeg/src/main/jni"
build_log="$module_dir/build.log"

rm -rf "$module_dir"
mkdir -p "$module_dir/jni/ffmpeg"
cp "$upstream_jni/build_ffmpeg.sh" "$upstream_jni/CMakeLists.txt" "$upstream_jni/ffmpeg_jni.cc" "$module_dir/jni/"
git -C "$repo_root/ffmpeg" archive HEAD | tar -x -C "$module_dir/jni/ffmpeg"

if ! "$module_dir/jni/build_ffmpeg.sh" "$module_dir" "$ndk_path" "$host_platform" "$min_sdk" "${decoders[@]}" >"$build_log" 2>&1; then
  tail -n 80 "$build_log" >&2
  exit 1
fi

ffmpeg_commit="$(git -C "$repo_root/ffmpeg" rev-parse HEAD)"
media3_commit="$(git -C "$repo_root/media" rev-parse HEAD)"
ffmpeg_tag="$(git -C "$repo_root" config -f .gitmodules submodule.ffmpeg.branch)"
media3_tag="$(git -C "$repo_root" config -f .gitmodules submodule.media.branch)"
configuration="$(sed -n 's/^#define FFMPEG_CONFIGURATION "\(.*\)"$/\1/p' "$module_dir/jni/ffmpeg/config.h")"

license_dir="$resources_dir/META-INF/media3-ffmpeg-decoder"
rm -rf "$license_dir"
mkdir -p "$license_dir"
cp "$repo_root/NOTICE" "$license_dir/NOTICE"
cp "$repo_root/ffmpeg/COPYING.LGPLv2.1" "$license_dir/COPYING.LGPLv2.1"
cat >"$license_dir/ffmpeg-build.txt" <<INFO
FFmpeg tag: $ffmpeg_tag
FFmpeg source: https://github.com/FFmpeg/FFmpeg/tree/$ffmpeg_commit
Media3 tag: $media3_tag
Build script: https://github.com/androidx/media/blob/$media3_commit/libraries/decoder_ffmpeg/src/main/jni/build_ffmpeg.sh
Minimum SDK: $min_sdk
Decoders: ${decoders[*]}
Configuration: $configuration
INFO
