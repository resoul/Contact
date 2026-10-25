# Contact

Contact is a Swift/UIKit messenger prototype for iOS and iPadOS 16.0 and later. It builds for arm64 devices and Apple Silicon simulators. The x86_64 architecture is not supported.

## Requirements

You need macOS, Xcode with the iOS SDK and a simulator runtime, and Bazelisk. The repository pins Bazel 9.3.1 in `.bazelversion`.

```sh
brew install bazelisk
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcodebuild -version
xcrun simctl list devices available
```

Clone the repository and download all pinned library submodules in one step:

```sh
git clone --recurse-submodules https://github.com/resoul/Contact.git
```

If you already cloned the repository without its submodules, initialize and download them from the Contact root directory:

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

Set your `bundle_id` in `BUILD.bazel` and place the corresponding development provisioning profile at `signing/development.mobileprovision`. The build uses `tools/signing/device-entitlements.py` to derive device entitlements from that profile, including the app's Keychain access group and team identity. Install a signing certificate with its private key in Keychain:

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
App/Messenger/               MiniTelegram screens, models, and local fixtures
App/Application/             Account contexts and background storage ownership
App/MetalVFXEngine/          Shared effects and Metal shader sources
App/Support/                 iOS compatibility helpers
App/Messenger/MascotLogin/   Rive login prototype opened from Settings
libraries/                   External dependencies, Bazel rules, and build scripts
libraries/grdb/              GRDB Swift module, pinned upstream archive
submodules/sqlcipher/        Vendored SQLCipher engine and Swift-compatible headers
submodules/AsyncDisplayKit/  Vendored Texture/Core sources and Bazel module
submodules/FFMpegBinding/     Objective-C FFmpeg API for Swift
submodules/WebPBinding/       Objective-C WebP API for Swift
submodules/MozjpegBinding/    JPEG/JPEG XL APIs and stripped thumbnails
submodules/ImageCompression/ Swift image compression helpers
submodules/ContactStorage/   Account databases, Keychain, migrations and observed queries
submodules/ListUI/           Node-based lists, folder paging, and row swipe actions
App/Messenger/Profile/       Profile header, media grid and ListUI attachment panes
cache/                       Ignored Bazel outputs and symlinks
tools/signing/              Device-signing entitlements generation
BUILD.bazel                  App, Swift module, and resources
MODULE.bazel                 Bazel dependencies and build tools
```

The `submodules/` directory contains sources maintained directly in Contact, including vendored AsyncDisplayKit and SQLCipher. The directory name does not imply Git submodule registration. External upstream dependencies and their build rules live in `libraries/`.

Git tracks app sources, bindings, `BUILD` and `.bzl` files, build scripts, `.gitmodules`, and `MODULE.bazel.lock`. Contact stores commit references for upstream libraries; their sources are fetched as git submodules. This README is the project documentation. Upstream documentation and license files stay with their submodules.

## Libraries

### AsyncDisplayKit

`//submodules/AsyncDisplayKit` builds the vendored Texture 3.2.0 Core sources
as the `AsyncDisplayKit` module. Add this target to a consumer's `deps` to use
`import AsyncDisplayKit`. The app does not depend on it yet. Unlike the codec
submodules, these sources are maintained directly in Contact; the original
commit and scope are recorded in
[`submodules/AsyncDisplayKit/UPSTREAM.md`](submodules/AsyncDisplayKit/UPSTREAM.md).
PINRemoteImage, IGListKit and Yoga are not dependencies, and Video, MapKit,
Photos and AssetsLibrary integrations are disabled. Build the module with:

```sh
bazelisk build //submodules/AsyncDisplayKit --config=simulator
```

### Codecs

| Library | Pinned version / commit | Bazel dependency |
| --- | --- | --- |
| libwebp | `1844042d1ca751e62e61df7617dba19c98588339` | `//libraries/webp:webp` |
| FFmpeg | 9.0.2 / `946fcce07b6dcd0331c8cc609192aeff5e1924f8` | `//libraries/ffmpeg` |
| libvpx | 1.17.0 / `6df3ec34557879fff673706f4a1d9fbd0f3a6f0e` | `//libraries/libvpx:vpx` |
| Opus | 1.6.1 / `22244de5a79bd1d6d623c32e72bf1954b56235be` | `//libraries/opus:opus` |
| dav1d | 1.5.4 / `54706fc6bc0cdecab7e9593974a4039cc038fca7` | `//libraries/dav1d:dav1d` |
| mozjpeg | 4.1.5 / `6c9f0897afa1c2738d7222a0a9ab49e8b536a267` | `//libraries/mozjpeg` |
| libjxl | 0.12.0 / `a7a9c787341cf703dede03c2009fa460cae5e5df` | `//libraries/libjxl` |

WebP is built directly with `cc_library` and ARM NEON. FFmpeg and libvpx use their upstream configure/Make builds; Opus and dav1d use Meson. Build scripts work with source copies inside Bazel actions, leaving submodule checkouts untouched. Device and simulator builds produce separate outputs. The default compilation mode is `dbg`; use `-c opt` for release optimization.

Meson 1.6.0, Ninja 1.12.1, pkgconf 2.5.1, gas-preprocessor, and the generated Opus models are pinned in `MODULE.bazel` with SHA-256 checksums. Global Meson, Ninja, or pkgconf installations are not required. mozjpeg and libjxl use upstream CMake with pinned CMake 4.1.2 and Ninja. libjxl uses the Brotli, Highway, and skcms commits pinned by its 0.12.0 release. The local source repository stages libjxl without its upstream Bazel BUILD files, so CMake inputs remain tracked without modifying the submodule. Only those three nested submodules are needed for this build:

```sh
git -C libraries/libjxl/libjxl submodule update --init third_party/brotli third_party/highway third_party/skcms
```

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

## Messenger

### Chat list

The Chats tab uses `App/Messenger/ChatList/ChatListPage.swift`, backed by
ListUI. The former table controller has been removed. The story header, UIKit
row, swipe button and preview now live in separate files in the same directory:
`StoriesHeader.swift`, `ChatCell.swift`, `SwipeButton.swift` and
`ChatPeek.swift`.

The controller embeds `ListPagerNode` and preserves the current story
header, liquid folder selector and 76 pt UIKit row visuals. `ChatListItemNode`
hosts the existing row; this is a list-engine migration, not a rewrite of its
UIKit drawing. Real account snapshots and committed actions still come from
`AccountSession`; tapping a row opens the existing `ChatViewController`.

Without custom folders there is one All list with the original swipe actions.
Creating a custom folder enables the existing built-in filters plus the custom
folder pages, reveals the liquid folder strip and enables full-width paging.
Row swipe gestures are disabled in folder mode. Holding a row opens the same
preview with all five actions: Read/Unread, Pin/Unpin, Mute/Unmute, Delete and
Archive. Story pull thresholds and the original spring-driven avatars
are retained, and each folder has its own scroll position. The dialog screen,
profile navigation, bottom tabs and database schema are unchanged.

### Temporary chat folders

Settings → Chat Folders opens folder management. Create Folder and the
Add Folder menu shown by holding the bottom Chats tab share the same name
prompt. Blank or whitespace-only names cannot be submitted. Folder names are
trimmed, assigned stable UUIDs, and appear immediately in the horizontally
scrollable folder strip above the current chat table. New folders are empty;
chat assignment is deferred. Existing All / Personal / Channels / Bots filters
continue to work.

`App/Messenger/Folders/FolderSessionStore.swift` keeps names only in process
memory, separately for each account and shared across scenes. Account switching
and backgrounding preserve them; terminating and relaunching Contact resets
custom folders. They are not written to UserDefaults, ContactStorage or SQLite.
The Chats tab exposes Add Folder as an accessibility action as well.

### Profile and shared list UI

The profile opened from a chat avatar uses `//submodules/ListUI` for a single
vertical scroll across its photo, information header and selected attachment
pane. The existing liquid Media / Files / Links / Voice selector pins beneath
the navigation bar and follows horizontal paging. Each page retains its scroll
position. The media grid preserves pinch-driven column changes and the profile
photo still expands into a gallery. Files, links and voice rows currently use
local demonstration data.

`App/Messenger/Profile` contains the profile controller, the media pane adapter,
the pinchable grid and attachment items. The earlier profile controller and the
Settings list demo have been removed after integration into the messenger.

[`submodules/ListUI/README.md`](submodules/ListUI/README.md) describes the public
interfaces, gesture policy, virtualization and initial implementation limits.

### Mascot login prototype

`App/Messenger/MascotLogin/MascotLoginViewController.swift` preserves the login screen
from `demo/view/view/MascotLogin`, including its bundled `login_mascot.riv`.
The submit button uses the Aurora border shader from the demo gallery.
Submission only validates the local fields and triggers the mascot's success
or failure animation; it does not authenticate an account.

Open Settings → Mascot Login, directly below Language, to view the screen.
Its Back button returns to Settings. Contact starts with the messenger.
RiveRuntime 6.28.1 is fetched as the same XCFramework used by the demo's Swift
package, pinned by SHA-256 in `MODULE.bazel`, and linked via `//libraries/rive`.
Aurora animation pauses offscreen and in the background, and becomes static
when Reduce Motion is enabled.

### Metal effects

Settings → Metal Effects opens five effects copied from the local `demo/demo/demo`
project: one lava progress bar, fire, GPU gravity, 2D smoke and an interacting fish
swarm. The screen shows one effect at a time with touch interaction and its own
controls. It contains no engine comparisons, profiler metrics or replicated views.

`App/Messenger/MetalEffects` contains the screen; reusable views and simulation
code live in `App/MetalVFXEngine/Simulations`, with shaders in the existing
`Shaders` directory. Gravity runs only on the GPU. Animation stops when leaving
the screen or when the app becomes inactive, and switching effects releases the
previous view and its simulation resources after in-flight GPU work completes.

### VFX previews and integrations

Settings → VFX opens the visual prototypes from `demo/controller/controller`:
Matrix + Kinetic registration, Photo Feed, Voice Room, Bubble Cluster, Particle
Morph (Pay / AI / VIP / Load), the full Particle Charts gallery, photo-viewer and
post effects, Vanish Mode, and Liquid Toast / Quick Reply. Chat Playground is a
local-only conversation for the three-photo stack, Send effects, wallpaper and
notification interactions.

Holding Send chooses a message effect. Fluid Mesh is available in Chat Theme;
group Call opens the Voice Room design and public demo channel Call opens the
Bubble Cluster broadcast preview. Pulling up beyond the last chat message toggles
Vanish Mode; messages composed in that mode are kept only in memory. Paper Burn
can be previewed on individual messages/posts. Public channel examples expose
translation and community context; the VFX Daily administrator example also
exposes post analytics. Those data-dependent screens are explicitly sample data.

[`App/Messenger/VFX/README.md`](App/Messenger/VFX/README.md) documents the entry
points, fixture permissions, source provenance and message-storage behavior.

### Messenger interface

Contact opens the MiniTelegram interface directly: chats, contacts, calls, settings, profiles, stories, media previews, composer, reactions, and themes. The sources were copied from the current working tree of `demo/controller/controller/MiniTelegram` and its shared `MetalVFXEngine`, including the fluid-reaction implementation. Contact builds independently of that checkout.

`App/Messenger/Models` contains shared chat/account models; `App/Messenger/Fixtures/MessengerData.swift` supplies the prototype's local accounts, people, chats, and stories. Chats and message history are read from ContactStorage. Fixture conversations are inserted once per account in one transaction with a durable seed marker; later launches never recreate deleted fixture data. Sending, editing, reactions, channel stars, forwards, pin/mute/read/archive actions, deletions and channel reading anchors are saved. Random incoming-message timers and fabricated delivery acknowledgements are disabled; new outgoing messages remain in the durable outbox until a future sync engine confirms them. Calls and recording remain UI demonstrations. There is no backend or authentication yet. The sample passcode is `1234` and is a UI demonstration. Media previews are generated locally by `DemoPhotos`.

The chat list includes four channel examples: VFX Daily, Motion Lab, Metal Notes, and UI Kitchen. `Fixtures/ChannelData.swift` supplies their posts. Pull up past the last post to reveal the next channel's avatar and progress ring; release after the haptic threshold to switch. Channels follow the current account's list order and wrap around, excluding groups. Switching replaces the current feed so Back returns directly to the chat list. Each account keeps channel posts, reactions and reading positions in its encrypted database. VoiceOver exposes a Next Channel action on the Back button, and Reduce Motion uses a cross-fade.

Channels use the original Telegram Post components: reactions and view counts inside each card, liquid comment sheets, stars that fill and accelerate when held, a long-press reaction picker with an expanding accordion and dust deletion, and forwarding by dragging a post to a contact. Channel reactions retain their original liquid flights and heart effect. Ordinary chats keep their separate emoji-flight reactions and the dedicated 💨 effect; swiping a message to reply now uses the original stretching liquid drop and arrow. Comments, stars, and forwarding remain local UI demonstrations.

All 19 shader sources are compiled with Bazel's `apple_metal_library` into `default.metallib` at the app bundle root, where `VFXGPU` loads it. This includes liquid reactions, emoji bursts, chat wallpaper, spoilers, dust deletion, story rings, and liquid theme transitions. The full shared effect engine remains available for subsequent messenger features.

The app keeps minimum iOS 16. Symbol effects use native iOS 17+ APIs with cross-fade/spring fallbacks on iOS 16. Theme changes update static layer colors on both versions. The root starts in dark mode and supports the original light/dark transition. The header's settings button replaces the demo's exit button; settings display Contact's own About screen. Page dependencies are assigned before loading their views so Settings is populated on first entry. The theme reveal uses wall-clock duration so dropped frames cannot prolong its input-blocking overlay.

## Media APIs

Codec libraries and bindings remain independent Bazel targets. Their demo view controllers and sample photo/video resource bundles have been removed from the application.

```swift
import FFMpegBinding
import WebPBinding
import MozjpegBinding
import ImageCompression

// These calls are synchronous; run them on a background queue.
let video = try FFMpegMedia.decodeVideo(path, maxDuration: 8)
let webp = try WebP.convert(toWebP: image, quality: 90)
let jpeg = try MozJPEG.encode(image, quality: 85, progressive: true, fast: false)
let xl = try MozJPEG.encodeXL(image, quality: 100)
let tiny = compressImageMiniThumbnail(image, type: .image)
let reconstructedJPEG = tiny.flatMap { decodeTinyThumbnail($0) }
```

Consumers add the relevant binding to their Bazel `deps`: `//submodules/FFMpegBinding`, `//submodules/WebPBinding`, `//submodules/MozjpegBinding`, or `//submodules/ImageCompression`. The messenger currently uses its generated fixtures; codec dependencies can be added when real media flows are introduced.

All six Telegram MozjpegBinding entry points remain available, including JPEG XL encoding/decoding. The compatibility JPEG function uses quality 72 and encodes in memory without touching `tempFilePath`. Mini-thumbnails retain Telegram's v1 format. JPEG flattens alpha onto white; JPEG XL preserves alpha, with lossless encoding at quality 100 after sRGB normalization. Images are limited to 32 million pixels; animated JPEG XL is rejected.

## Storage

Contact includes `//libraries/grdb` (GRDB 7.11.1) backed by `//submodules/sqlcipher` (SQLCipher 4.19.0 Community / SQLite 3.53.4), using CommonCrypto. The [storage integration notes](submodules/ContactStorage/README.md) describe the database and UI integration. GRDB's privacy manifest and both libraries' licenses are bundled with the app. [ContactStorage](submodules/ContactStorage/README.md) opens a separate encrypted database and Keychain key per account, with versioned migrations, atomic message/outbox operations and observable queries. The chat list and conversation screens now use committed database snapshots through AccountSession, preserving their existing interaction animations.
