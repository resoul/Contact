# UIKit, iOS / iPadOS 16+

```sh
brew install bazelisk
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcodebuild -version
xcrun simctl list devices available
bazel --version
```

```sh
make simulator
make device
make build-simulator
make build-device    
make clean           
make clean-all       
make list-simulators
make list-devices
make help
```

```sh
make simulator SIMULATOR="iPhone 17" IOS_VERSION=27.0
make simulator SIMULATOR="iPad (A16)"
make device DEVICE="YOUR_DEVICE_UDID"
```

```sh
bazel run //:HelloBazel --config=simulator
```

Intel Mac:

```sh
bazel run //:HelloBazel --config=simulator_intel
```

```sh
BAZEL_APPLE_PREFER_PERSISTENT_SIMS=1 bazel run //:HelloBazel --config=simulator \
  --@rules_apple//apple/build_settings:ios_simulator_device="<simulator name>" \
  --@rules_apple//apple/build_settings:ios_simulator_version="<version runtime>"
```

```sh
security find-identity -v -p codesigning
```

```text
build:device --@rules_apple//apple/build_settings:signing_certificate_name="Apple Development: Your Name (TEAMID)"
build:device --@rules_apple//apple/build_settings:ios_device=YOUR_DEVICE_UDID
```

```sh
bazel build //:HelloBazel --config=device
```

```sh
xcrun devicectl list devices
bazel run //:HelloBazel --config=device
```

```sh
brew install ios-deploy
ios-deploy --detect
APP_INSTALL_DIR="$(mktemp -d /tmp/hello-bazel.XXXXXX)"
ditto -x -k cache/bazel-bin/HelloBazel.ipa "$APP_INSTALL_DIR"
ios-deploy --id YOUR_DEVICE_UDID \
  --bundle "$APP_INSTALL_DIR/Payload/HelloBazel.app" --debug --justlaunch
```
