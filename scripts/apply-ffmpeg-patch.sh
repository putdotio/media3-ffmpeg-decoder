#!/usr/bin/env bash
set -euo pipefail

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tree="$1"

patch -d "$tree" -p1 -N -F 0 -s -i "$scripts_dir/../patches/ffmpeg-lgpl-only.patch"
"$scripts_dir/ffmpeg-gpl-files.sh" "$tree" | while IFS= read -r gpl_file; do
  rm "$tree/$gpl_file"
done
