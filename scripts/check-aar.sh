#!/usr/bin/env bash
set -euo pipefail

aar="$1"
ffmpeg_build_log="$2"
ndk_path="$3"
readelf=("$ndk_path"/toolchains/llvm/prebuilt/*/bin/llvm-readelf)
readelf="${readelf[0]}"

fail() {
  echo "check-aar: $1" >&2
  exit 1
}

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
unzip -q "$aar" -d "$work_dir"

for abi in arm64-v8a armeabi-v7a x86_64 x86; do
  [[ -f "$work_dir/jni/$abi/libffmpegJNI.so" ]] || fail "missing libffmpegJNI.so for $abi"
done

for abi in arm64-v8a x86_64; do
  for library in "$work_dir/jni/$abi"/*.so; do
    alignments="$("$readelf" -l -W "$library" | awk '$1 == "LOAD" { print $NF }')"
    [[ -n "$alignments" ]] || fail "no LOAD segments in $abi/$(basename "$library")"
    while read -r alignment; do
      (( alignment >= 16384 && alignment % 16384 == 0 )) ||
        fail "$abi/$(basename "$library") has LOAD alignment $alignment, expected a multiple of 0x4000"
    done <<<"$alignments"
  done
done

license_lines="$(grep -E '^License: ' "$ffmpeg_build_log" || true)"
[[ "$(grep -c . <<<"$license_lines")" -eq 4 ]] ||
  fail "expected 4 configure license lines in $ffmpeg_build_log"
if grep -qvE '^License: LGPL version 2\.1 or later$' <<<"$license_lines"; then
  fail "FFmpeg is not LGPL 2.1: $(sort -u <<<"$license_lines")"
fi

classes_listing="$(unzip -l "$work_dir/classes.jar")"
for entry in \
  androidx/media3/decoder/ffmpeg/FfmpegAudioRenderer.class \
  META-INF/media3-ffmpeg-decoder/NOTICE \
  META-INF/media3-ffmpeg-decoder/COPYING.LGPLv2.1 \
  META-INF/media3-ffmpeg-decoder/ffmpeg-build.txt; do
  grep -q "$entry" <<<"$classes_listing" || fail "classes.jar is missing $entry"
done

echo "check-aar: ok"
