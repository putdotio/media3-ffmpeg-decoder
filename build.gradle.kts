import com.vanniktech.maven.publish.AndroidSingleVariantLibrary
import com.vanniktech.maven.publish.JavadocJar
import com.vanniktech.maven.publish.SourcesJar
import javax.inject.Inject

plugins {
    id("com.android.library") version "9.5.0"
    id("com.vanniktech.maven.publish") version "0.37.0"
}

val media3Version = media3.versions.releaseVersion.get()
val ffmpegMinSdk = providers.gradleProperty("ffmpegMinSdk").get().toInt()
val ffmpegDecoders = providers.gradleProperty("ffmpegDecoders").get().trim().split(Regex("\\s+"))
val upstreamModule = layout.projectDirectory.dir("media/libraries/decoder_ffmpeg")
val stagedModule = layout.buildDirectory.dir("ffmpeg-module")
val stagedCMakeLists = stagedModule.map { it.file("jni/CMakeLists.txt") }
val ffmpegBuildLog = stagedModule.map { it.file("build.log") }
val stagedFfmpeg = stagedModule.map { it.dir("jni/ffmpeg") }
val ffmpegSourceArchive = layout.buildDirectory.file("ffmpeg-source/ffmpeg-source.tar.xz")

group = "io.put"
version = providers.gradleProperty("version").orNull?.takeUnless { it == "unspecified" } ?: "$media3Version-SNAPSHOT"

abstract class RunScript
    @Inject
    constructor(
        private val execOperations: ExecOperations,
    ) : DefaultTask() {
        @get:InputFile
        @get:PathSensitive(PathSensitivity.RELATIVE)
        abstract val script: RegularFileProperty

        @get:Input
        abstract val arguments: ListProperty<String>

        @get:Optional
        @get:OutputDirectory
        abstract val generatedResources: DirectoryProperty

        @TaskAction
        fun run() {
            val command = listOfNotNull(script.get().asFile.path, generatedResources.orNull?.asFile?.path) + arguments.get()
            execOperations.exec { commandLine(command) }
        }
    }

android {
    namespace = "androidx.media3.decoder.ffmpeg"
    compileSdk = media3.versions.compileSdkVersion.get().toInt()
    ndkVersion = providers.gradleProperty("ndkVersion").get()

    defaultConfig {
        minSdk = ffmpegMinSdk
        consumerProguardFiles(upstreamModule.file("proguard-rules.txt"))
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86")
        }
    }

    sourceSets {
        getByName("main") {
            java.directories.add(upstreamModule.dir("src/main/java").asFile.path)
            manifest.srcFile(upstreamModule.file("src/main/AndroidManifest.xml"))
        }
    }

    externalNativeBuild {
        cmake {
            path = stagedCMakeLists.get().asFile
            version = "3.21.0+"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    lint {
        checkReleaseBuilds = false
    }
}

val gitCommit = { path: String ->
    providers
        .exec {
            workingDir(path)
            commandLine("git", "rev-parse", "HEAD")
        }.standardOutput.asText
        .map(String::trim)
}

val ndkDirectoryPath = androidComponents.sdkComponents.ndkDirectory.map { it.asFile.path }

val buildFfmpeg =
    tasks.register<RunScript>("buildFfmpeg") {
        group = "build"
        description = "Builds LGPL FFmpeg static libraries with Media3's build_ffmpeg.sh"
        script = layout.projectDirectory.file("scripts/build-ffmpeg.sh")
        inputs.property("ffmpegCommit", gitCommit("ffmpeg"))
        inputs.property("media3Commit", gitCommit("media"))
        inputs
            .files("NOTICE", "LICENSE", "scripts/stage-ffmpeg-source.sh")
            .withPathSensitivity(PathSensitivity.RELATIVE)
        outputs.dir(stagedModule)
        arguments.add(ndkDirectoryPath)
        arguments.add(ffmpegMinSdk.toString())
        arguments.add(stagedModule.map { it.asFile.path })
        arguments.addAll(ffmpegDecoders)
    }

val packageFfmpegSource =
    tasks.register<RunScript>("packageFfmpegSource") {
        group = "build"
        description = "Packages the FFmpeg source, JNI wrapper and build scripts for LGPL distribution"
        script = layout.projectDirectory.file("scripts/package-ffmpeg-source.sh")
        inputs.property("ffmpegCommit", gitCommit("ffmpeg"))
        inputs.property("media3Commit", gitCommit("media"))
        inputs
            .files("NOTICE", "LICENSE", "gradle.properties", "scripts/stage-ffmpeg-source.sh", "scripts/build-ffmpeg.sh")
            .withPathSensitivity(PathSensitivity.RELATIVE)
        outputs.file(ffmpegSourceArchive)
        arguments.add(ffmpegSourceArchive.map { it.asFile.path })
    }

androidComponents {
    beforeVariants(selector().withBuildType("debug")) { it.enable = false }
    onVariants { variant ->
        variant.sources.resources?.addGeneratedSourceDirectory(buildFfmpeg, RunScript::generatedResources)
    }
}

tasks.matching { it.name.startsWith("configureCMake") }.configureEach {
    dependsOn(buildFfmpeg)
}

val checkAar =
    tasks.register<RunScript>("checkAar") {
        group = "verification"
        description = "Checks the AAR for 16 KB alignment, ABIs, decoders, FFmpeg's license and the renderer class"
        dependsOn("assembleRelease")
        outputs.upToDateWhen { false }
        script = layout.projectDirectory.file("scripts/check-aar.sh")
        arguments.add(layout.buildDirectory.file("outputs/aar/media3-ffmpeg-decoder-release.aar").map { it.asFile.path })
        arguments.add(ffmpegBuildLog.map { it.asFile.path })
        arguments.add(ndkDirectoryPath)
        arguments.add(stagedFfmpeg.map { it.asFile.path })
    }

val publicationSigning = if (providers.gradleProperty("signingInMemoryKey").isPresent) "signed" else "unsigned"
val publishedVersionDirectory =
    version.toString().let { publishedVersion ->
        providers
            .systemProperty("maven.repo.local")
            .orElse(providers.systemProperty("user.home").map { "$it/.m2/repository" })
            .map { "$it/io/put/media3-ffmpeg-decoder/$publishedVersion" }
    }

val checkPublication =
    tasks.register<RunScript>("checkPublication") {
        group = "verification"
        description = "Checks the publication in Maven Local for everything Maven Central and the LGPL require"
        dependsOn("publishToMavenLocal")
        outputs.upToDateWhen { false }
        script = layout.projectDirectory.file("scripts/check-publication.sh")
        arguments.add(publishedVersionDirectory)
        arguments.add(version.toString())
        arguments.add(publicationSigning)
    }

val checkNegativeControls =
    tasks.register<RunScript>("checkNegativeControls") {
        group = "verification"
        description = "Proves the AAR and publication checks fail on broken input"
        dependsOn(checkAar, checkPublication)
        outputs.upToDateWhen { false }
        script = layout.projectDirectory.file("scripts/check-negative-controls.sh")
        inputs
            .files("scripts/check-aar.sh", "scripts/check-publication.sh")
            .withPathSensitivity(PathSensitivity.RELATIVE)
        arguments.add(layout.buildDirectory.file("outputs/aar/media3-ffmpeg-decoder-release.aar").map { it.asFile.path })
        arguments.add(ffmpegBuildLog.map { it.asFile.path })
        arguments.add(ndkDirectoryPath)
        arguments.add(stagedFfmpeg.map { it.asFile.path })
        arguments.add(publishedVersionDirectory)
        arguments.add(version.toString())
        arguments.add(publicationSigning)
    }

tasks.register("verify") {
    group = "verification"
    description = "Builds the AAR, publishes to Maven Local and enforces the release checks"
    dependsOn(checkAar, checkPublication, checkNegativeControls)
}

dependencies {
    api("androidx.media3:media3-decoder:$media3Version")
    implementation("androidx.media3:media3-exoplayer:$media3Version")
    implementation(media3.androidx.annotation)
    compileOnly(media3.checkerframework.qual)
}

val releaseVersionPattern = Regex("""${Regex.escape(media3Version)}\+[1-9][0-9]*""")
val publishVersion = version.toString()

tasks.matching { it.name.startsWith("publish") && !it.name.endsWith("ToMavenLocal") }.configureEach {
    doFirst {
        check(releaseVersionPattern.matches(publishVersion)) {
            "Remote publishing needs -Pversion=<media3 version>+<build>, got $publishVersion"
        }
    }
}

publishing {
    publications.withType<MavenPublication>().configureEach {
        artifact(ffmpegSourceArchive) {
            builtBy(packageFfmpegSource)
            classifier = "ffmpeg-source"
            extension = "tar.xz"
        }
    }
}

mavenPublishing {
    publishToMavenCentral(automaticRelease = true)
    if (providers.gradleProperty("signingInMemoryKey").isPresent) {
        signAllPublications()
    }
    configure(
        AndroidSingleVariantLibrary(
            variant = "release",
            sourcesJar = SourcesJar.Sources(),
            javadocJar = JavadocJar.Empty(),
        ),
    )
    coordinates(group.toString(), "media3-ffmpeg-decoder", version.toString())

    pom {
        name.set("media3-ffmpeg-decoder")
        description.set("AndroidX Media3's FFmpeg audio decoder built with LGPL FFmpeg. Bundles FFmpeg (LGPL-2.1-or-later).")
        url.set("https://github.com/putdotio/media3-ffmpeg-decoder")
        inceptionYear.set("2026")

        licenses {
            license {
                name.set("Apache-2.0")
                url.set("https://www.apache.org/licenses/LICENSE-2.0.txt")
            }
            license {
                name.set("LGPL-2.1-or-later")
                url.set("https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt")
                comments.set("The FFmpeg libraries statically linked into libffmpegJNI")
            }
        }

        developers {
            developer {
                id.set("putdotio")
                name.set("put.io")
                email.set("devs@put.io")
            }
        }

        scm {
            connection.set("scm:git:https://github.com/putdotio/media3-ffmpeg-decoder.git")
            developerConnection.set("scm:git:ssh://git@github.com/putdotio/media3-ffmpeg-decoder.git")
            url.set("https://github.com/putdotio/media3-ffmpeg-decoder")
        }
    }
}
