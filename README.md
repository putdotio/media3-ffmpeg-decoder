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
./gradlew verify
./gradlew publishToMavenLocal -Pversion=1.11.1+1
```

`./gradlew verify` builds FFmpeg with Media3's own `build_ffmpeg.sh`, then [check-aar.sh](./scripts/check-aar.sh) fails the build on a non-LGPL FFmpeg, a 64-bit library not aligned to 16 KB, a missing ABI or a missing renderer class.

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

## Release

```bash
git tag 'v1.11.1+1'
git push origin 'v1.11.1+1'
```

Pushing a `v*` tag publishes the AAR, sources and POM, signed, from the [release job](./.github/workflows/ci.yml). The tag must be on `main`. The version must be the current Media3 version plus `+<build>`. Central rejects a re-upload, so never delete or re-push a tag: bump the build number instead.

The job reads `MAVEN_CENTRAL_USERNAME`, `MAVEN_CENTRAL_PASSWORD`, `SIGNING_KEY_ID`, `SIGNING_KEY` and `SIGNING_PASSWORD` from the protected `release` environment.

## License

This project is [Apache-2.0](./LICENSE), the license of Media3's module.

The AAR bundles FFmpeg, which is LGPL-2.1-or-later. FFmpeg is built without `--enable-gpl`, `--enable-nonfree` and `--enable-version3`. Each AAR carries the exact FFmpeg commit, configure string and LGPL text under `META-INF/media3-ffmpeg-decoder/`, and the corresponding source is the `ffmpeg` submodule at the release tag. See [NOTICE](./NOTICE).
