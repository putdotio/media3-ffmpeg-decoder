#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="$1"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
package_dir="$work_dir/ffmpeg-source"

"$repo_root/scripts/stage-ffmpeg-source.sh" "$package_dir"
mkdir -p "$package_dir/scripts"
cp "$repo_root/scripts/build-ffmpeg.sh" "$repo_root/scripts/stage-ffmpeg-source.sh" "$package_dir/scripts/"
cp "$repo_root/LICENSE" "$repo_root/NOTICE" "$repo_root/gradle.properties" "$package_dir/"
cat >"$package_dir/BUILD.txt" <<'INFO'
Corresponding source for the FFmpeg libraries linked into libffmpegJNI.so.

jni/ffmpeg              FFmpeg at the pinned tag, with a VERSION file naming it
jni/build_ffmpeg.sh     AndroidX Media3's FFmpeg build script
jni/CMakeLists.txt      links libffmpegJNI.so from the FFmpeg libraries
jni/ffmpeg_jni.cc       the JNI wrapper, Apache-2.0
gradle.properties       NDK version, minimum SDK and decoder list of this release
scripts/                how the release stages this tree and records its configuration

Rebuild the FFmpeg static libraries for every ABI from this directory, with
host set to linux-x86_64 or darwin-x86_64 and NDK set to the NDK path:

  jni/build_ffmpeg.sh "$PWD" "$NDK" "$host" \
    "$(sed -n 's/^ffmpegMinSdk=//p' gradle.properties)" \
    $(sed -n 's/^ffmpegDecoders=//p' gradle.properties)

The libraries land in jni/ffmpeg/android-libs/<abi>. Delete jni/ffmpeg/VERSION
before you compile jni/ffmpeg_jni.cc: on a case-insensitive file system it
shadows the C++ <version> header.
INFO

mkdir -p "$(dirname "$output")"
tar -cJf "$output" -C "$work_dir" ffmpeg-source
