# Contact

Contact is a Swift/UIKit app for iOS and iPadOS 16.0 and later. It builds for arm64 devices and Apple Silicon simulators. The x86_64 architecture is not supported.

## Requirements

You need macOS, Xcode with the iOS SDK and a simulator runtime, and Bazelisk. The repository pins Bazel 9.3.1 in `.bazelversion`.

```sh
brew install bazelisk
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcodebuild -version
xcrun simctl list devices available
```

Clone the repository with `--recurse-submodules`. To fetch the libraries in an existing checkout, run:

```sh
git submodule update --init --recursive
```

## Build and run

Run commands from the Contact root directory.

```sh
make simulator
make simulator SIMULATOR="iPhone 17" IOS_VERSION=27.0
make build-simulator
```

`SIMULATOR` and `IOS_VERSION` must match an installed device and runtime. The app build is written to `cache/bazel-bin/Contact.ipa`.

You can also call Bazel directly:

```sh
bazelisk build //:Contact --config=simulator
BAZEL_APPLE_PREFER_PERSISTENT_SIMS=1 bazelisk run //:Contact --config=simulator \
  --@rules_apple//apple/build_settings:ios_simulator_device="iPhone 17" \
  --@rules_apple//apple/build_settings:ios_simulator_version="27.0"
```

| Command | Description |
| --- | --- |
| `make list-simulators` | List available simulators |
| `make list-devices` | List connected devices |
| `make clean` | Remove build outputs |
| `make clean-all` | Clear Bazel state for this project and stop its server |
| `make help` | List available commands |

### Physical devices

Set your `bundle_id` in `BUILD.bazel` and place the corresponding development provisioning profile at `signing/development.mobileprovision`. Install a signing certificate with its private key in Keychain:

```sh
security find-identity -v -p codesigning
```

If needed, set the signing certificate and device in your local `.bazelrc.local`:

```text
build:device --@rules_apple//apple/build_settings:signing_certificate_name="Apple Development: Your Name (TEAMID)"
build:device --@rules_apple//apple/build_settings:ios_device=YOUR_DEVICE_UDID
```

```sh
make build-device
make device DEVICE="YOUR_DEVICE_UDID"
```

Launching on a device through `devicectl` requires iOS 17 or later; the app itself supports iOS 16 and later. Local settings, profiles, and signing keys are excluded from Git.

## Project layout

```text
App/                         Swift/UIKit app and sample media
libraries/                   Bazel rules, build scripts, and library git submodules
submodules/FFMpegBinding/     Objective-C FFmpeg API for Swift
submodules/WebPBinding/       Objective-C WebP API for Swift
cache/                       Ignored Bazel outputs and symlinks
BUILD.bazel                  App, Swift module, and resources
MODULE.bazel                 Bazel dependencies and build tools
```

Git tracks app sources, bindings, `BUILD` and `.bzl` files, build scripts, `.gitmodules`, and `MODULE.bazel.lock`. Contact stores commit references for upstream libraries; their sources are fetched as git submodules. This README is the project documentation. Upstream documentation and license files stay with their submodules.

## Libraries

| Library | Pinned version / commit | Bazel dependency |
| --- | --- | --- |
| libwebp | `1844042d1ca751e62e61df7617dba19c98588339` | `//libraries/webp:webp` |
| FFmpeg | 9.0.2 / `946fcce07b6dcd0331c8cc609192aeff5e1924f8` | `//libraries/ffmpeg` |
| libvpx | 1.17.0 / `6df3ec34557879fff673706f4a1d9fbd0f3a6f0e` | `//libraries/libvpx:vpx` |
| Opus | 1.6.1 / `22244de5a79bd1d6d623c32e72bf1954b56235be` | `//libraries/opus:opus` |
| dav1d | 1.5.4 / `54706fc6bc0cdecab7e9593974a4039cc038fca7` | `//libraries/dav1d:dav1d` |

WebP is built directly with `cc_library` and ARM NEON. FFmpeg and libvpx use their upstream configure/Make builds; Opus and dav1d use Meson. Build scripts work with source copies inside Bazel actions, leaving submodule checkouts untouched. Device and simulator builds produce separate outputs. The default compilation mode is `dbg`; use `-c opt` for release optimization.

Meson 1.6.0, Ninja 1.12.1, pkgconf 2.5.1, gas-preprocessor, and the generated Opus models are pinned in `MODULE.bazel` with SHA-256 checksums. Global Meson, Ninja, or pkgconf installations are not required.

Build individual distributions:

```sh
bazelisk build //libraries/ffmpeg:distribution --config=simulator
bazelisk build //libraries/libvpx:distribution //libraries/opus:distribution //libraries/dav1d:distribution --config=simulator
```

For iPhone, replace `--config=simulator` with `--config=device`. Distributions contain headers, static `.a` files, and relocatable pkg-config `.pc` files under `cache/bazel-bin/libraries/`. FFmpeg also writes `build-info.txt` with its enabled components. FFmpeg, libvpx, Opus, and dav1d can also be built locally for macOS arm64 (minimum macOS 14.0).

### FFmpeg profile

The build exports static `avformat`, `avcodec`, `avutil`, and `swresample` libraries. Bazel propagates dependencies on libvpx, Opus, and dav1d.

- Video decoding: H.264, HEVC, VP9 through libvpx, AV1 through dav1d, and VideoToolbox paths for H.264/HEVC/AV1.
- Audio decoding: Opus, AAC/ALAC/GSM through AudioToolbox, MP3, FLAC, and selected PCM formats.
- Encoding: VP9 with alpha and AAC through AudioToolbox.
- Input containers: MOV/MP4, AAC/M4V, MP3, Ogg, FLAC, WAV, AIFF, Matroska/WebM, and MPEG-TS.
- Output containers: MP4/MOV, Matroska, Ogg, and MPEG-TS.

Only the local `file` protocol is enabled. Network protocols, the FFmpeg CLI, libavfilter, libswscale, and libavdevice are disabled. GPL and nonfree components are disabled; upstream license texts remain in the submodules.

## Demos and APIs

### FFmpeg

The first tab plays `App/Resources/FFmpeg/demo.mp4`: a four-second H.264/AAC clip at 640×360 and 24 fps, with 96 frames and a 440 Hz audio track. FFmpeg decodes video frames and PCM audio; UIKit displays the frames and `AVAudioPlayer` plays the PCM. The demo supports play/pause, seeking, opening a video from Files, and MP4 remux verification by decoding the output and comparing frames and audio.

The Bazel dependency is `//submodules/FFMpegBinding`:

```swift
import FFMpegBinding

// This call is synchronous; run it on a background queue.
let video = try FFMpegMedia.decodeVideo(path, maxDuration: 8)
let firstPNG = video.frames.first?.pngData
let pcm = video.pcmData // S16LE, 48 kHz, stereo
```

This is a bounded in-memory preview. The demo shows the first eight seconds of a selected video; the API supports up to ten seconds, 30 PNG previews per second, and a maximum image edge of 320 pixels. Core Image preview conversion supports 8-bit YUV420/YUVA420. Longer videos, complex edit lists, and discontinuous timestamps require a streaming player with a full playback timeline.

The low-level API provides format and IO contexts, packets, decoders, frames, PCM resampling, VP9 alpha encoding, MP4/MPEG-TS remuxing, and packet-aligned Opus trimming into Ogg. The MPEG-TS helper preserves video and AAC audio. The binding is adapted from [Telegram-iOS FFMpegBinding](https://github.com/TelegramMessenger/Telegram-iOS/tree/fb0e62ba8a147f0821da6aa63c09da7d79a10111/submodules/FFMpegBinding) for FFmpeg 9, with fixes for EOF handling, IO context ownership, audio buffer sizing, frame durations, and error handling.

The sample clip is generated without third-party media. Recreate it with a host FFmpeg build that includes libx264:

```sh
ffmpeg -f lavfi -i 'testsrc2=size=640x360:rate=24:duration=4' \
  -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=4' \
  -c:v libx264 -profile:v main -pix_fmt yuv420p -g 24 -bf 2 -crf 24 \
  -colorspace bt709 -color_primaries bt709 -color_trc bt709 \
  -c:a aac -b:a 96k -movflags +faststart -shortest App/Resources/FFmpeg/demo.mp4
```

### WebP

The WebP tab compares source JPEG/PNG photos with decoded WebP images and displays file sizes and processing time. It supports quality settings from 0 to 100, lossless encoding, and opening a photo from Files.

The Bazel dependency is `//submodules/WebPBinding`:

```swift
import WebPBinding

let source = UIImage(data: jpegOrPNGData)!
let lossy = try WebP.convert(toWebP: source, quality: 90)
let lossless = try WebP.convert(toLosslessWebP: source)
let image = WebP.convert(fromWebP: lossy)
```

Operations are synchronous; run encoding on a background queue. Quality 100 is still lossy. Alpha is preserved, images are normalized to upright sRGB, and metadata is not copied. Animated WebP is not supported. Encoding reports errors through `WebPErrorDomain`; decoding returns `nil` for invalid data.

## Verification

The iPhone and simulator arm64 builds were checked with a minimum iOS version of 16.0. Simulator checks covered H.264/AAC, HEVC, VP9/Opus, AV1/dav1d, all 96 sample video frames, 768,000 bytes of PCM, MP4 remux with identical frames and audio, MPEG-TS remux, Opus trimming, and twelve VP9 alpha frames. UI checks covered playback, pause, seeking, playback completion, and remux. Hardware decoding on a physical device has not been tested.

Lossless WebP round trips preserved the sRGB pixels in both photos. The following sizes were measured at quality 90:

| Input | Original bytes | Lossy WebP bytes | Lossless WebP bytes |
| --- | ---: | ---: | ---: |
| JPEG, 452×700 | 80,435 | 49,374 | 278,602 |
| PNG, 503×900 | 1,133,080 | 223,822 | 770,856 |

Size and speed depend on the image and build mode. Temporary verification sources and targets were removed; demo photos and video remain app resources.
