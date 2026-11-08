#!/usr/bin/env bash
set -euo pipefail

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tree="$1"

(cd "$tree" && find . -type f | sed 's#^\./##') |
  grep -E '\.(c|S|h|asm|inc|cpp|cc|m|mm|pl|pm|sh|py|mak)$' |
  "$scripts_dir/classify-license.pl" "$tree" |
  awk -F'\t' '$1 == "gpl" { print $3 }'
