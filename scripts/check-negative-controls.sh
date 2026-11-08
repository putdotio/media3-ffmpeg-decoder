#!/usr/bin/env bash
set -euo pipefail

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(dirname "$scripts_dir")"
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

mirror_for_aar() {
  local mirror="$work_dir/ffmpeg"
  rm -rf "$mirror"
  mkdir -p "$mirror"
  ln -s "$ffmpeg_dir/android-libs" "$mirror/android-libs"
  cp "$ffmpeg_dir/RELEASE" "$mirror/RELEASE"
  cp "$ffmpeg_dir/config_components.h" "$mirror/config_components.h"
}

mutate_config_components() {
  mirror_for_aar
  sed "$1" "$ffmpeg_dir/config_components.h" >"$work_dir/ffmpeg/config_components.h"
}

mutate_release() {
  mirror_for_aar
  printf '%s\n' "$1" >"$work_dir/ffmpeg/RELEASE"
}

drop_classes_entry() {
  local aar_dir="$work_dir/aar"
  local classes_dir="$work_dir/classes"
  rm -rf "$aar_dir" "$classes_dir" "$work_dir/mutated.aar"
  mkdir -p "$aar_dir" "$classes_dir"
  unzip -q "$aar" -d "$aar_dir"
  unzip -q "$aar_dir/classes.jar" -d "$classes_dir"
  rm "$classes_dir/$1" "$aar_dir/classes.jar"
  (cd "$classes_dir" && zip -qr "$aar_dir/classes.jar" .)
  (cd "$aar_dir" && zip -qr "$work_dir/mutated.aar" .)
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

mutate_release "0.0.0"
expect_aar_failure "does not match .gitmodules tag" "$aar" "$work_dir/ffmpeg"

drop_classes_entry META-INF/media3-ffmpeg-decoder/FFMPEG-LICENSE.md
expect_aar_failure "classes.jar is missing META-INF/media3-ffmpeg-decoder/FFMPEG-LICENSE.md" "$work_dir/mutated.aar" "$ffmpeg_dir"

module_dir="$(dirname "$(dirname "$ffmpeg_dir")")"
gate="$work_dir/gate"
gate_report="$work_dir/gate-report"

reset_gate() {
  rm -rf "$gate"
  mkdir -p "$gate/jni"
  cp -R "$ffmpeg_dir" "$gate/jni/ffmpeg"
  cp "$module_dir/jni/ffmpeg_jni.cc" "$gate/jni/ffmpeg_jni.cc"
  cp -R "$module_dir/compiled-objects" "$gate/compiled-objects"
  cp "$repo_root/NOTICE" "$gate/NOTICE"
}

expect_gate_failure() {
  expect_failure "$1" "$scripts_dir/check-ffmpeg-licenses.sh" "$gate/jni/ffmpeg" "$gate/compiled-objects" "$gate/NOTICE" "$ndk_path" "$gate_report"
}

record_compiled_object() {
  local abi="$1" object="$2"
  shift 2
  mkdir -p "$gate/compiled-objects/$abi/$(dirname "$object")"
  printf '%s: %s\n' "$object" "$*" >"$gate/compiled-objects/$abi/${object%.o}.d"
}

restore_pristine() {
  git -C "$repo_root/ffmpeg" show "HEAD:$1" >"$gate/jni/ffmpeg/$1"
}

gate_clean="$("$scripts_dir/check-ffmpeg-licenses.sh" "$ffmpeg_dir" "$module_dir/compiled-objects" "$repo_root/NOTICE" "$ndk_path" "$gate_report")"
grep -q "ok, no GPL source" <<<"$gate_clean" || die "gate did not pass on the real tree: $gate_clean"

reset_gate
restore_pristine libavcodec/aarch64/ac3dsp_neon.S
record_compiled_object arm64-v8a libavcodec/aarch64/ac3dsp_neon.o libavcodec/aarch64/ac3dsp_neon.S
expect_gate_failure "GPL source compiled into arm64-v8a: libavcodec/aarch64/ac3dsp_neon.S"

reset_gate
restore_pristine libavcodec/aarch64/ac3dsp_init_aarch64.c
record_compiled_object armeabi-v7a libavcodec/includer.o libavcodec/ac3dsp.c libavcodec/aarch64/ac3dsp_init_aarch64.c
expect_gate_failure "GPL source compiled into armeabi-v7a: libavcodec/aarch64/ac3dsp_init_aarch64.c"

reset_gate
cat >"$gate/jni/ffmpeg/libavutil/wrapped_gpl.c" <<'SOURCE'
/*
 * This file is free software; you can redistribute it under the terms
 * of the GNU General
 * Public License as published by the Free Software Foundation.
 */
SOURCE
record_compiled_object x86 libavutil/wrapped_gpl.o libavutil/wrapped_gpl.c
expect_gate_failure "GPL source compiled into x86: libavutil/wrapped_gpl.c"

reset_gate
record_compiled_object x86_64 libavcodec/absent.o libavcodec/absent.c
expect_gate_failure "source libavcodec/absent.c is not in the tree"

reset_gate
rm "$gate/compiled-objects/arm64-v8a/libavcodec/ac3dsp.d"
expect_gate_failure "arm64-v8a archive members have no recorded object"

reset_gate
rm -rf "$gate/compiled-objects/x86"
expect_gate_failure "no recorded objects for x86"

reset_gate
perl -0pi -e 's/The following libraries are under GPL/The following libraries are under a tampered license/' "$gate/NOTICE"
expect_gate_failure "NOTICE is missing FFmpeg's LICENSE.md"

reset_gate
sed -i.bak '/avsscanf/d;/Rich Felker/d' "$gate/NOTICE"
expect_gate_failure "NOTICE is missing notices for arm64-v8a:"

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
sed -i.bak 's#</licenses>#<license><name>Apache-2.0</name></license></licenses>#' "$prefix.pom"
expect_publication_failure "POM must declare exactly one combined license entry"

reset_publication
sed -i.bak 's#<name>Apache-2.0 AND LGPL-2.1-or-later</name>#<name>Apache-2.0</name>#' "$prefix.pom"
expect_publication_failure "POM is missing the combined license name"

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
expect_publication_failure "ffmpeg-source differs from the pinned FFmpeg plus the patch"

reset_publication
mutate_ffmpeg_source 'rm jni/ffmpeg/libavcodec/ac3dsp.c'
expect_publication_failure "ffmpeg-source differs from the pinned FFmpeg plus the patch"

reset_publication
mutate_ffmpeg_source 'rm patches/ffmpeg-lgpl-only.patch'
expect_publication_failure "ffmpeg-source is missing patches/ffmpeg-lgpl-only.patch"

reset_publication
mutate_ffmpeg_source 'echo "# changed" >>patches/ffmpeg-lgpl-only.patch'
expect_publication_failure "ffmpeg-source patch differs from patches/ffmpeg-lgpl-only.patch"

reset_publication
mutate_ffmpeg_source "git -C \"$repo_root/ffmpeg\" show HEAD:libavcodec/aarch64/ac3dsp_neon.S >jni/ffmpeg/libavcodec/aarch64/ac3dsp_neon.S"
expect_publication_failure "ffmpeg-source carries GPL file libavcodec/aarch64/ac3dsp_neon.S"

reset_publication
mutate_ffmpeg_source "git -C \"$repo_root/ffmpeg\" show HEAD:libavutil/macos_kperf.c >jni/ffmpeg/libavutil/macos_kperf.c"
expect_publication_failure "ffmpeg-source carries GPL files: libavutil/macos_kperf.c"

if [[ "$signing" == signed ]]; then
  reset_publication
  rm "$prefix-ffmpeg-source.tar.xz.asc"
  expect_publication_failure "missing signature for media3-ffmpeg-decoder-$version-ffmpeg-source.tar.xz"
fi

echo "check-negative-controls: $controls controls failed as expected"
