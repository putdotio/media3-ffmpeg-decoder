# media3-ffmpeg-decoder

[AndroidX Media3](https://github.com/androidx/media)'s FFmpeg audio decoder, built with an LGPL build of FFmpeg and published to Maven Central.

```kotlin
implementation("io.put:media3-ffmpeg-decoder:1.11.1+1")
```

The version is `<media3 version>+<build>`. It exposes Media3's `FfmpegAudioRenderer` and `FfmpegLibrary`. The Media3 dependency is the same version.

| | |
| --- | --- |
| Decoders | `ffmpegDecoders` in [gradle.properties](./gradle.properties) |
| ABIs | arm64-v8a, armeabi-v7a, x86_64, x86 |
| Min SDK | `ffmpegMinSdk` in [gradle.properties](./gradle.properties) |
| 16 KB pages | 64-bit libraries are aligned to 16 KB |

## Build

Needs Java 21, the NDK in `ndkVersion`, Linux x86_64 or macOS, and shallow submodules.

```bash
git clone --recurse-submodules --shallow-submodules https://github.com/putdotio/media3-ffmpeg-decoder.git
cd media3-ffmpeg-decoder
./gradlew verify
./gradlew publishToMavenLocal -Pversion=1.11.1+1
```

`./gradlew verify` builds FFmpeg with Media3's own `build_ffmpeg.sh`, then publishes to Maven Local and fails the build on what a release must not ship:

- [check-ffmpeg-licenses.sh](./scripts/check-ffmpeg-licenses.sh): any GPL source compiled into any ABI, from the objects each ABI actually built, or a compiled non-LGPL notice missing from [NOTICE](./NOTICE). Runs during `buildFfmpeg`.
- [check-aar.sh](./scripts/check-aar.sh): a non-LGPL FFmpeg, a decoder outside the allowed set, a missing per-ABI configure line, a 64-bit library not aligned to 16 KB, a missing ABI, a missing renderer class, a missing notice file, or a `RELEASE` that disagrees with the pinned tag.
- [check-publication.sh](./scripts/check-publication.sh): a POM without the single combined license entry, a missing sources or javadoc jar, an `ffmpeg-source` archive that differs from the pinned FFmpeg plus [patches/ffmpeg-lgpl-only.patch](./patches/ffmpeg-lgpl-only.patch), or a GPL file in that archive.
- [check-negative-controls.sh](./scripts/check-negative-controls.sh): proves each check fails on broken input.

CI runs [verify-release-shape.sh](./scripts/verify-release-shape.sh), which does the same with a release version and a throwaway signing key.

## Bump Media3

Renovate opens these. By hand:

```bash
git -C media fetch --depth 1 origin tag 1.12.0
git -C media checkout 1.12.0
git config -f .gitmodules submodule.media.branch 1.12.0
git add .gitmodules media
./gradlew verify
```

The artifact and Media3 dependency versions follow from the `media` submodule.

## Bump FFmpeg

Renovate tracks n7.1.x. FFmpeg 8 removed libpostproc, and Media3's `build_ffmpeg.sh` still passes `--disable-postproc`, so a major bump waits for Media3 to change it.

```bash
git -C ffmpeg fetch --depth 1 origin tag n7.1.6
git -C ffmpeg checkout n7.1.6
git config -f .gitmodules submodule.ffmpeg.branch n7.1.6
git add .gitmodules ffmpeg
./gradlew verify
```

[check-ffmpeg-licenses.sh](./scripts/check-ffmpeg-licenses.sh) fails on a new GPL source or a new third-party notice. Remove a GPL source with [patches/ffmpeg-lgpl-only.patch](./patches/ffmpeg-lgpl-only.patch). Add a new notice to [NOTICE](./NOTICE) from `scripts/classify-license.pl --print-notices <ffmpeg tree> <<<path`.

## Release

```bash
git tag 'v1.11.1+1'
git push origin 'v1.11.1+1'
```

Pushing a `v*` tag publishes the AAR, sources, javadoc, `ffmpeg-source` archive and POM, signed, from the [release job](./.github/workflows/ci.yml). The tag must be on `main`. The version must be the current Media3 version plus `+<build>`. Central rejects a re-upload, so never delete or re-push a tag: bump the build number instead.

The job reads `MAVEN_CENTRAL_USERNAME`, `MAVEN_CENTRAL_PASSWORD`, `SIGNING_KEY_ID`, `SIGNING_KEY` and `SIGNING_PASSWORD` from the protected `release` environment.

## License

This project is [Apache-2.0](./LICENSE), the license of Media3's module.

The AAR bundles FFmpeg, which is LGPL-2.1-or-later. FFmpeg is built without `--enable-gpl`, `--enable-nonfree` and `--enable-version3`. On arm64, [patches/ffmpeg-lgpl-only.patch](./patches/ffmpeg-lgpl-only.patch) removes FFmpeg's GPL AC-3 NEON assembly, so the ac3 and eac3 decoders run the C implementation. Each AAR carries the exact FFmpeg commit, per-ABI configure lines, LGPL text, FFmpeg's `LICENSE.md` and the third-party notices under `META-INF/media3-ffmpeg-decoder/`. The corresponding source is published next to the AAR on Maven Central as `media3-ffmpeg-decoder-<version>-ffmpeg-source.tar.xz`: the FFmpeg tree that was built, the patch, the JNI wrapper, the build scripts and a `BUILD.txt` with the commands to rebuild FFmpeg and relink `libffmpegJNI.so`. See [NOTICE](./NOTICE).

## Shipping this in an app

An app that bundles this AAR carries FFmpeg under the LGPL. To stay compliant:

- Keep the notices. Show the contents of `META-INF/media3-ffmpeg-decoder/` (`NOTICE`, `LICENSE`, `COPYING.LGPLv2.1`, `FFMPEG-LICENSE.md`) in your app's licenses screen or docs, or ship them next to it.
- Offer the matching source: the `ffmpeg-source` archive of the exact version you ship, from Maven Central or your own host.
- Do not strip the notices with packaging excludes. `packaging { resources { excludes } }` must not match `META-INF/media3-ffmpeg-decoder/**`, including broad patterns like `META-INF/*` or `META-INF/**`.
- Do not prevent users from replacing `libffmpegJNI.so` with one they rebuilt from that archive. `BUILD.txt` has the commands.
