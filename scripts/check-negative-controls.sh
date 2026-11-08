#!/usr/bin/env bash
set -euo pipefail

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
aar="$1"
build_log="$2"
ndk_path="$3"
ffmpeg_dir="$4"
published_dir="$5"
version="$6"
signing="$7"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
controls=0

die() {
  echo "check-negative-controls: $1" >&2
  exit 1
}

expect_failure() {
  local reason="$1"
  shift
  local output
  if output="$("$@" 2>&1)"; then
    die "check passed but should have failed with: $reason"
  fi
  grep -qF -- "$reason" <<<"$output" || die "wanted '$reason', got: $output"
  controls=$((controls + 1))
}

expect_aar_failure() {
  local reason="$1"
  local mutated_aar="$2"
  local mutated_ffmpeg="$3"
  expect_failure "$reason" "$scripts_dir/check-aar.sh" "$mutated_aar" "$build_log" "$ndk_path" "$mutated_ffmpeg"
}

mutate_build_info() {
  local aar_dir="$work_dir/aar"
  local classes_dir="$work_dir/classes"
  rm -rf "$aar_dir" "$classes_dir" "$work_dir/mutated.aar"
  mkdir -p "$aar_dir" "$classes_dir"
  unzip -q "$aar" -d "$aar_dir"
  unzip -q "$aar_dir/classes.jar" -d "$classes_dir"
  sed -i.bak "$1" "$classes_dir/META-INF/media3-ffmpeg-decoder/ffmpeg-build.txt"
  rm "$classes_dir/META-INF/media3-ffmpeg-decoder/ffmpeg-build.txt.bak" "$aar_dir/classes.jar"
  (cd "$classes_dir" && zip -qr "$aar_dir/classes.jar" .)
  (cd "$aar_dir" && zip -qr "$work_dir/mutated.aar" .)
}

mutate_config_components() {
  local mirror="$work_dir/ffmpeg"
  rm -rf "$mirror"
  mkdir -p "$mirror"
  ln -s "$ffmpeg_dir/android-libs" "$mirror/android-libs"
  sed "$1" "$ffmpeg_dir/config_components.h" >"$mirror/config_components.h"
}

mutate_build_info 's/^Configuration arm64-v8a: .*/Configuration arm64-v8a: /'
expect_aar_failure "empty configuration for arm64-v8a" "$work_dir/mutated.aar" "$ffmpeg_dir"

mutate_build_info '/^Configuration x86: /s/ --enable-decoder=truehd//'
expect_aar_failure "decoders in x86 differ from the allowed set" "$work_dir/mutated.aar" "$ffmpeg_dir"

mutate_build_info 's/^FFmpeg tag: .*/FFmpeg tag: n0.0.0/'
expect_aar_failure "libavutil.a for arm64-v8a does not report n0.0.0" "$work_dir/mutated.aar" "$ffmpeg_dir"

mutate_config_components 's/^#define CONFIG_HEVC_DECODER 0$/#define CONFIG_HEVC_DECODER 1/'
expect_aar_failure "enabled decoders differ from the allowed set" "$aar" "$work_dir/ffmpeg"

mutate_config_components 's/^#define CONFIG_TRUEHD_DECODER 1$/#define CONFIG_TRUEHD_DECODER 0/'
expect_aar_failure "enabled decoders differ from the allowed set" "$aar" "$work_dir/ffmpeg"

publication="$work_dir/publication"
prefix="$publication/media3-ffmpeg-decoder-$version"

reset_publication() {
  rm -rf "$publication"
  cp -R "$published_dir" "$publication"
}

expect_publication_failure() {
  expect_failure "$1" "$scripts_dir/check-publication.sh" "$publication" "$version" "$signing"
}

mutate_ffmpeg_source() {
  local expanded="$work_dir/expanded"
  rm -rf "$expanded"
  mkdir -p "$expanded"
  tar -xJf "$prefix-ffmpeg-source.tar.xz" -C "$expanded"
  (cd "$expanded/ffmpeg-source" && eval "$1")
  XZ_OPT=-0 tar -cJf "$prefix-ffmpeg-source.tar.xz" -C "$expanded" ffmpeg-source
}

for suffix in .aar .pom -sources.jar -javadoc.jar -ffmpeg-source.tar.xz; do
  reset_publication
  rm "$prefix$suffix"
  expect_publication_failure "missing media3-ffmpeg-decoder-$version$suffix"
done

reset_publication
sed -i.bak '/LGPL-2.1-or-later/d' "$prefix.pom"
expect_publication_failure "POM is missing license LGPL-2.1-or-later"

reset_publication
sed -i.bak '/<name>Apache-2.0<\/name>/d' "$prefix.pom"
expect_publication_failure "POM is missing license Apache-2.0"

reset_publication
(cd "$work_dir" && rm -f stub.jar && echo stub >stub.txt && zip -q stub.jar stub.txt && mv stub.jar "$prefix-sources.jar")
expect_publication_failure "sources jar is missing androidx/media3/decoder/ffmpeg/FfmpegAudioRenderer.java"

reset_publication
mutate_ffmpeg_source 'rm jni/ffmpeg/configure'
expect_publication_failure "ffmpeg-source is missing jni/ffmpeg/configure"

reset_publication
mutate_ffmpeg_source 'rm jni/ffmpeg/COPYING.LGPLv2.1'
expect_publication_failure "ffmpeg-source is missing jni/ffmpeg/COPYING.LGPLv2.1"

reset_publication
mutate_ffmpeg_source 'rm jni/ffmpeg_jni.cc'
expect_publication_failure "ffmpeg-source is missing jni/ffmpeg_jni.cc"

reset_publication
mutate_ffmpeg_source 'echo n0.0.0 >jni/ffmpeg/VERSION'
expect_publication_failure "ffmpeg-source VERSION does not name"

reset_publication
mutate_ffmpeg_source 'echo "# patched" >>jni/ffmpeg/configure'
expect_publication_failure "ffmpeg-source differs from the pinned FFmpeg commit"

if [[ "$signing" == signed ]]; then
  reset_publication
  rm "$prefix-ffmpeg-source.tar.xz.asc"
  expect_publication_failure "missing signature for media3-ffmpeg-decoder-$version-ffmpeg-source.tar.xz"
fi

echo "check-negative-controls: $controls controls failed as expected"
