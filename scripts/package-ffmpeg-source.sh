#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="$1"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
package_dir="$work_dir/ffmpeg-source"

"$repo_root/scripts/stage-ffmpeg-source.sh" "$package_dir"
mkdir -p "$package_dir/scripts/record-objects" "$package_dir/patches"
cp "$repo_root/patches/ffmpeg-lgpl-only.patch" "$package_dir/patches/"
cp \
  "$repo_root/scripts/build-ffmpeg.sh" \
  "$repo_root/scripts/stage-ffmpeg-source.sh" \
  "$repo_root/scripts/apply-ffmpeg-patch.sh" \
  "$repo_root/scripts/ffmpeg-gpl-files.sh" \
  "$repo_root/scripts/classify-license.pl" \
  "$repo_root/scripts/list-compiled-sources.pl" \
  "$repo_root/scripts/check-ffmpeg-licenses.sh" \
  "$package_dir/scripts/"
cp "$repo_root/scripts/record-objects/make" "$package_dir/scripts/record-objects/"
cp "$repo_root/LICENSE" "$repo_root/NOTICE" "$repo_root/gradle.properties" "$package_dir/"
cat >"$package_dir/BUILD.txt" <<'INFO'
Corresponding source for the FFmpeg libraries linked into libffmpegJNI.so.

jni/ffmpeg                      FFmpeg at the pinned tag, modified as below,
                                with a VERSION file naming the tag
patches/ffmpeg-lgpl-only.patch  the change to FFmpeg, already applied in jni/ffmpeg
jni/build_ffmpeg.sh             AndroidX Media3's FFmpeg build script
jni/CMakeLists.txt              the release's link of libffmpegJNI.so
jni/ffmpeg_jni.cc               the JNI wrapper, Apache-2.0
gradle.properties               NDK version, minimum SDK and decoder list of this release
scripts/                        how the release stages this tree and records its build

jni/ffmpeg differs from FFmpeg's tag in two ways. The patch is applied. Every
source file whose header grants the GPL is deleted. NOTICE names the changes.

Set these from this directory. Pick the NDK version in gradle.properties:

  NDK=/path/to/ndk
  host=linux-x86_64        # or darwin-x86_64
  abi=arm64-v8a            # or armeabi-v7a, x86_64, x86
  min_sdk="$(sed -n 's/^ffmpegMinSdk=//p' gradle.properties)"

Rebuild the FFmpeg static libraries. The script builds every ABI and writes
each one to jni/ffmpeg/android-libs/<abi>:

  jni/build_ffmpeg.sh "$PWD" "$NDK" "$host" "$min_sdk" \
    $(sed -n 's/^ffmpegDecoders=//p' gradle.properties)

Relink libffmpegJNI.so for $abi with the NDK toolchain:

  rm -f jni/ffmpeg/VERSION
  case "$abi" in
    arm64-v8a) target=aarch64-linux-android; extra=-Wl,-Bsymbolic ;;
    armeabi-v7a) target=armv7a-linux-androideabi; extra= ;;
    x86_64) target=x86_64-linux-android; extra= ;;
    x86) target=i686-linux-android; extra= ;;
  esac
  mkdir -p "relink/$abi"
  "$NDK/toolchains/llvm/prebuilt/$host/bin/$target$min_sdk-clang++" \
    -std=c++11 -O2 -fPIC -shared -fvisibility=hidden -fvisibility-inlines-hidden \
    -Ijni/ffmpeg jni/ffmpeg_jni.cc -o "relink/$abi/libffmpegJNI.so" \
    "-Ljni/ffmpeg/android-libs/$abi" -lswresample -lavcodec -lavutil -landroid -llog \
    -static-libstdc++ -Wl,--no-undefined -Wl,-z,max-page-size=16384 $extra

Delete VERSION only after the FFmpeg build: FFmpeg reads it, and on a
case-insensitive file system it shadows the C++ <version> header.

Replace libffmpegJNI.so for that ABI in your app to run the rebuilt code.
INFO

mkdir -p "$(dirname "$output")"
tar -cJf "$output" -C "$work_dir" ffmpeg-source
