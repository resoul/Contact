#!/bin/bash
# Build into Bazel's action directory; never modify the checked-out submodule.
set -euo pipefail

codec="$1"
cpu="$2"
mode="$3"
source_subdir="$4"
version="$5"
exec_root="$PWD"
output="$exec_root/$6"
meson="$exec_root/$7"
ninja="$exec_root/$8"
models="$exec_root/$9"
minimum_ios=16.0

case "$cpu" in
    ios_arm64)
        sdk=iphoneos
        triple="arm64-apple-ios${minimum_ios}"
        min_option=miphoneos-version-min
        subsystem=ios
        vpx_target=arm64-darwin-gcc
        ;;
    ios_sim_arm64)
        sdk=iphonesimulator
        triple="arm64-apple-ios${minimum_ios}-simulator"
        min_option=mios-simulator-version-min
        subsystem=ios
        vpx_target=arm64-iphonesimulator-gcc
        ;;
    darwin_arm64)
        # Native builds support local codec checks, without an iOS runtime.
        sdk=macosx
        triple=arm64-apple-macosx14.0
        min_option=mmacosx-version-min
        subsystem=macos
        vpx_target=arm64-darwin25-gcc
        ;;
    *) echo "Unsupported codec target: $cpu" >&2; exit 1 ;;
esac

sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
cc="$(xcrun --sdk "$sdk" --find clang)"
ar="$(xcrun --sdk "$sdk" --find ar)"
strip="$(xcrun --sdk "$sdk" --find strip)"
jobs="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)"
if [ "$jobs" -gt 8 ]; then jobs=8; fi
work="$output/.$codec-work"
rm -rf "$work"
mkdir -p "$work/source" "$work/build" "$output/include" "$output/lib/pkgconfig"
cp -RL "$exec_root/$source_subdir/." "$work/source/"
log="$work/build.log"
trap 'result=$?; if [ "$result" -ne 0 ] && [ -f "$log" ]; then tail -100 "$log" >&2; fi' EXIT

if [ "$codec" = vpx ]; then
    if [ "$sdk" != macosx ]; then
        # Upstream's arm64-darwin target selects iPhoneOS unconditionally.
        # Adapt only the staged copy, with exact matches so updates fail loudly.
        /usr/bin/python3 - "$work/source" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
p = root / 'configure'
s = p.read_text()
needle = 'all_platforms="${all_platforms} arm64-darwin-gcc"'
assert s.count(needle) == 1
p.write_text(s.replace(needle, needle + '\nall_platforms="${all_platforms} arm64-iphonesimulator-gcc"'))
p = root / 'build/make/configure.sh'
s = p.read_text()
replacements = {
    '        darwin)\n          if ! enabled external_build; then': '        darwin|iphonesimulator)\n          if ! enabled external_build; then',
    'XCRUN_FIND="xcrun --sdk iphoneos --find"': 'XCRUN_FIND="xcrun --sdk ${VPX_APPLE_SDK} --find"',
    'AS="$(${XCRUN_FIND} as)"': 'AS="${CC} -c"',
    'ASFLAGS="-arch ${tgt_isa} -g"': 'ASFLAGS="${VPX_APPLE_FLAGS} -g"',
}
for old, new in replacements.items():
    assert s.count(old) == 1, old
    s = s.replace(old, new)
assert 'IOS_VERSION_MIN="7.0"' in s and 'IOS_VERSION_MIN="8.0"' in s
s = s.replace('IOS_VERSION_MIN="7.0"', 'IOS_VERSION_MIN="16.0"')
s = s.replace('IOS_VERSION_MIN="8.0"', 'IOS_VERSION_MIN="16.0"')
s = s.replace('show_darwin_sdk_path iphoneos', 'show_darwin_sdk_path "${VPX_APPLE_SDK}"')
s = s.replace('-miphoneos-version-min=', '-${VPX_MINIMUM_OPTION}=')
p.write_text(s)
PY
    fi
    export VPX_APPLE_SDK="$sdk" VPX_MINIMUM_OPTION="$min_option"
    export VPX_APPLE_FLAGS="--target=$triple -isysroot $sdk_path"
    export LDFLAGS="$VPX_APPLE_FLAGS"
    options=()
    if [ "$mode" = dbg ]; then options+=(--enable-debug --disable-optimizations); fi
    echo "Configuring libvpx $version for $cpu ($mode)"
    (
        cd "$work/build"
        "$work/source/configure" --target="$vpx_target" --prefix="$output" \
            --enable-static --disable-shared --enable-pic \
            --disable-docs --disable-examples --disable-tools --disable-unit-tests \
            --disable-webm-io --disable-postproc --disable-vp9-postproc \
            --disable-vp9-highbitdepth --disable-vp9-temporal-denoising \
            --enable-realtime-only --enable-multi-res-encoding --size-limit=8192x8192 \
            --extra-cflags="--target=$triple -isysroot $sdk_path" \
            "${options[@]}"
        make -j"$jobs"
        make install
    ) >"$log" 2>&1
    cp "$work/build/vpx_version.h" "$output/include/vpx/vpx_version.h"
else
    # Avoid package-version queries through .git (not an input to Bazel).
    if [ "$codec" = opus ]; then
        tar -xzf "$models" -C "$work/source"
        printf 'PACKAGE_VERSION="%s"\n' "$version" > "$work/source/package_version"
    fi
    cat > "$work/apple.ini" <<EOF
[binaries]
c = '$cc'
ar = '$ar'
strip = '$strip'
pkg-config = '/usr/bin/false'

[built-in options]
c_args = ['--target=$triple', '-isysroot', '$sdk_path', '-fPIC']
c_link_args = ['--target=$triple', '-isysroot', '$sdk_path']

[properties]
needs_exe_wrapper = true

[host_machine]
system = 'darwin'
subsystem = '$subsystem'
kernel = 'xnu'
cpu_family = 'aarch64'
cpu = 'arm64'
endian = 'little'
EOF
    buildtype=release
    if [ "$mode" = dbg ]; then buildtype=debug; fi
    if [ "$codec" = opus ]; then
        options=(-Dextra-programs=disabled -Dtests=disabled -Ddocs=disabled -Dasm=disabled -Dintrinsics=enabled)
    else
        options=(-Denable_tools=false -Denable_tests=false -Denable_examples=false -Denable_docs=false)
    fi
    echo "Configuring $codec $version for $cpu ($mode)"
    export NINJA="$ninja" PYTHONDONTWRITEBYTECODE=1
    /usr/bin/python3 "$meson" setup "$work/build" "$work/source" \
        --cross-file="$work/apple.ini" --buildtype="$buildtype" \
        --default-library=static --prefix="$output" --libdir=lib \
        --wrap-mode=nodownload "${options[@]}" >"$log" 2>&1
    "$ninja" -C "$work/build" -j"$jobs" >>"$log" 2>&1
    "$ninja" -C "$work/build" install >>"$log" 2>&1
fi

# FFmpeg can stage this distribution elsewhere and use real pkg-config version
# checks without retaining paths from a previous Bazel sandbox.
/usr/bin/python3 - "$output/lib/pkgconfig/$codec.pc" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
lines = p.read_text().splitlines()
values = {'prefix': '${pcfiledir}/../..', 'libdir': '${prefix}/lib', 'includedir': '${prefix}/include'}
p.write_text('\n'.join(k + '=' + values[k] if (k := line.split('=', 1)[0]) in values else line for line in lines) + '\n')
PY
echo "Built $codec $version: $cpu, $mode"
rm -rf "$work"
