#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
media3_version="$(sed -n 's/^releaseVersion = "\(.*\)"$/\1/p' "$repo_root/media/gradle/libs.versions.toml")"
if [[ -z "$media3_version" ]]; then
  echo "verify-release-shape: no releaseVersion in the media submodule" >&2
  exit 1
fi

GNUPGHOME="$(mktemp -d)"
export GNUPGHOME
trap 'rm -rf "$GNUPGHOME"' EXIT
gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
  --quick-generate-key 'media3-ffmpeg-decoder verify <devs@put.io>' rsa3072 sign never

ORG_GRADLE_PROJECT_signingInMemoryKey="$(gpg --batch --armor --export-secret-keys)"
export ORG_GRADLE_PROJECT_signingInMemoryKey

cd "$repo_root"
./gradlew verify --no-configuration-cache "-Pversion=$media3_version+1" "$@"
