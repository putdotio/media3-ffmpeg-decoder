#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
published_dir="$1"
version="$2"
signing="$3"

fail() {
  echo "check-publication: $1" >&2
  exit 1
}

prefix="$published_dir/media3-ffmpeg-decoder-$version"
aar="$prefix.aar"
pom="$prefix.pom"
sources_jar="$prefix-sources.jar"
javadoc_jar="$prefix-javadoc.jar"
ffmpeg_source="$prefix-ffmpeg-source.tar.xz"
artifacts=("$aar" "$pom" "$sources_jar" "$javadoc_jar" "$ffmpeg_source")

for artifact in "${artifacts[@]}"; do
  [[ -s "$artifact" ]] || fail "missing $(basename "$artifact")"
done

if [[ "$signing" == signed ]]; then
  for artifact in "${artifacts[@]}"; do
    [[ -s "$artifact.asc" ]] || fail "missing signature for $(basename "$artifact")"
  done
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

pom_text="$(<"$pom")"
for license in Apache-2.0 LGPL-2.1-or-later; do
  grep -qF "<name>$license</name>" <<<"$pom_text" || fail "POM is missing license $license"
done
grep -qF "<version>$version</version>" <<<"$pom_text" || fail "POM does not declare version $version"

aar_listing="$(unzip -l "$aar")" || fail "$(basename "$aar") is not a zip"
grep -q 'jni/arm64-v8a/libffmpegJNI.so' <<<"$aar_listing" || fail "AAR is missing libffmpegJNI.so"

unzip -l "$javadoc_jar" >/dev/null || fail "$(basename "$javadoc_jar") is not a zip"

sources_listing="$(unzip -l "$sources_jar")" || fail "$(basename "$sources_jar") is not a zip"
for entry in androidx/media3/decoder/ffmpeg/FfmpegAudioRenderer.java androidx/media3/decoder/ffmpeg/FfmpegLibrary.java; do
  grep -q "$entry" <<<"$sources_listing" || fail "sources jar is missing $entry"
done

mkdir "$work_dir/extracted"
tar -xJf "$ffmpeg_source" -C "$work_dir/extracted" || fail "$(basename "$ffmpeg_source") is not a tar.xz"
source_root="$work_dir/extracted/ffmpeg-source"
for entry in \
  jni/ffmpeg/configure \
  jni/ffmpeg/COPYING.LGPLv2.1 \
  jni/ffmpeg/VERSION \
  jni/build_ffmpeg.sh \
  jni/CMakeLists.txt \
  jni/ffmpeg_jni.cc \
  scripts/build-ffmpeg.sh \
  gradle.properties \
  BUILD.txt \
  LICENSE \
  NOTICE; do
  [[ -s "$source_root/$entry" ]] || fail "ffmpeg-source is missing $entry"
done

ffmpeg_tag="$(git -C "$repo_root" config -f .gitmodules submodule.ffmpeg.branch)"
[[ "$(<"$source_root/jni/ffmpeg/VERSION")" == "$ffmpeg_tag" ]] ||
  fail "ffmpeg-source VERSION does not name $ffmpeg_tag"

mkdir "$work_dir/pinned"
git -C "$repo_root/ffmpeg" archive HEAD | tar -x -C "$work_dir/pinned"
rm "$source_root/jni/ffmpeg/VERSION"
diff -r "$work_dir/pinned" "$source_root/jni/ffmpeg" >"$work_dir/diff" || {
  head -n 5 "$work_dir/diff" >&2
  fail "ffmpeg-source differs from the pinned FFmpeg commit"
}

echo "check-publication: ok"
