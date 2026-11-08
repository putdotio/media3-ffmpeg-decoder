#!/usr/bin/env bash
set -euo pipefail

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ffmpeg_dir="$1"
objects_dir="$2"
notice_file="$3"
ndk_path="$4"
report="$5"
llvm_ar=("$ndk_path"/toolchains/llvm/prebuilt/*/bin/llvm-ar)
llvm_ar="${llvm_ar[0]}"

fail() {
  echo "check-ffmpeg-licenses: $1" >&2
  exit 1
}

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

perl -e 'local $/; my @texts = map { open my $fh, "<", $_ or die; my $t = <$fh>; $t =~ s/\s+/ /g; $t =~ s/^ | $//g; $t } @ARGV; exit(index($texts[1], $texts[0]) >= 0 ? 0 : 1)' "$ffmpeg_dir/LICENSE.md" "$notice_file" ||
  fail "NOTICE is missing FFmpeg's LICENSE.md"

wrapper_grant="$("$scripts_dir/classify-license.pl" "$(dirname "$ffmpeg_dir")" <<<ffmpeg_jni.cc | cut -f1)"
[[ "$wrapper_grant" != gpl ]] || fail "GPL source compiled into every ABI: ffmpeg_jni.cc"

: >"$report"
for abi in arm64-v8a armeabi-v7a x86_64 x86; do
  [[ -d "$objects_dir/$abi" ]] || fail "no recorded objects for $abi"
  listing="$work_dir/$abi.listing"
  "$scripts_dir/list-compiled-sources.pl" "$ffmpeg_dir" "$objects_dir/$abi" >"$listing" 2>"$work_dir/error" ||
    fail "$(cat "$work_dir/error")"

  awk -F'\t' '$1 == "object" { n = split($2, parts, "/"); print parts[n] }' "$listing" | sort -u >"$work_dir/recorded"
  for library in avcodec avutil swresample; do
    archive="$ffmpeg_dir/android-libs/$abi/lib$library.a"
    [[ -f "$archive" ]] || fail "no static library $archive"
    "$llvm_ar" t "$archive"
  done | grep -F .o | sort -u >"$work_dir/members"
  unrecorded="$(comm -23 "$work_dir/members" "$work_dir/recorded")"
  [[ -z "$unrecorded" ]] || fail "$abi archive members have no recorded object: $unrecorded"

  awk -F'\t' '$1 != "object" { print $2 }' "$listing" |
    "$scripts_dir/classify-license.pl" "$ffmpeg_dir" "$notice_file" >"$work_dir/$abi.classes"

  gpl_sources="$(awk -F'\t' '$1 == "gpl" { print $3 }' "$work_dir/$abi.classes")"
  [[ -z "$gpl_sources" ]] || fail "GPL source compiled into $abi: $gpl_sources"

  awk -F'\t' -v abi="$abi" '$1 != "lgpl" || $2 != "-" { print abi "\t" $1 "\t" $2 "\t" $3 }' \
    "$work_dir/$abi.classes" >>"$report"

  missing_notices="$(awk -F'\t' '$4 == "missing-notice" { print $3 }' "$work_dir/$abi.classes")"
  [[ -z "$missing_notices" ]] || fail "NOTICE is missing notices for $abi: $missing_notices"
done

echo "check-ffmpeg-licenses: ok, no GPL source in any ABI, $(wc -l <"$report" | tr -d ' ') non-LGPL entries"
