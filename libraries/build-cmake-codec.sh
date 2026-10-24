#!/bin/bash
set -euo pipefail
codec="$1"; cpu="$2"; mode="$3"; source_path="$PWD/$4"; version="$5"
if [[ "$source_path" = */CMakeLists.txt ]]; then source_path="$(dirname "$source_path")"; fi
output="$PWD/$6"; cmake="$PWD/$7"; ninja="$PWD/$8"
case "$cpu" in
    ios_arm64) sdk=iphoneos; triple=arm64-apple-ios16.0 ;;
    ios_sim_arm64) sdk=iphonesimulator; triple=arm64-apple-ios16.0-simulator ;;
    darwin_arm64) sdk=macosx; triple=arm64-apple-macosx14.0 ;;
    *) echo "Unsupported target: $cpu" >&2; exit 1 ;;
esac
work="$output/.$codec-work"
rm -rf "$work"
mkdir -p "$work/source" "$work/build" "$output/include" "$output/lib/pkgconfig"
cp -RL "$source_path/." "$work/source/"
log="$work/build.log"
trap 'result=$?; if [ "$result" -ne 0 ]; then tail -100 "$log" >&2; fi' EXIT
buildtype=Release
if [ "$mode" = dbg ]; then buildtype=Debug; fi
sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
cat > "$work/toolchain.cmake" <<TOOLCHAIN
set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_OSX_ARCHITECTURES arm64)
set(CMAKE_OSX_SYSROOT "$sdk_path")
set(CMAKE_C_COMPILER "$(xcrun --sdk "$sdk" --find clang)")
set(CMAKE_CXX_COMPILER "$(xcrun --sdk "$sdk" --find clang++)")
set(CMAKE_C_FLAGS_INIT "--target=$triple")
set(CMAKE_CXX_FLAGS_INIT "--target=$triple")
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
TOOLCHAIN
options=()
if [ "$codec" = mozjpeg ]; then
    options=(-DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_JPEG8=ON -DWITH_SIMD=ON -DREQUIRE_SIMD=ON -DPNG_SUPPORTED=OFF -DWITH_TURBOJPEG=ON -DBUILD=10000)
    targets=(jpeg-static turbojpeg-static)
else
    options=(-DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF -DJPEGXL_STATIC=ON
        -DJPEGXL_ENABLE_TOOLS=OFF -DJPEGXL_ENABLE_DEVTOOLS=OFF -DJPEGXL_ENABLE_BENCHMARK=OFF
        -DJPEGXL_ENABLE_EXAMPLES=OFF -DJPEGXL_ENABLE_FUZZERS=OFF -DJPEGXL_ENABLE_JPEGLI=OFF
        -DJPEGXL_ENABLE_DOXYGEN=OFF -DJPEGXL_ENABLE_MANPAGES=OFF -DJPEGXL_ENABLE_JNI=OFF
        -DJPEGXL_ENABLE_SJPEG=OFF -DJPEGXL_ENABLE_OPENEXR=OFF -DJPEGXL_ENABLE_TRANSCODE_JPEG=OFF
        -DJPEGXL_ENABLE_SKCMS=ON -DJPEGXL_ENABLE_TCMALLOC=OFF -DJPEGXL_BUNDLE_LIBPNG=OFF
        -DJPEGXL_FORCE_SYSTEM_BROTLI=OFF -DJPEGXL_FORCE_SYSTEM_HWY=OFF)
    targets=(jxl jxl_cms)
fi
"$cmake" -S "$work/source" -B "$work/build" -G Ninja \
    -DCMAKE_MAKE_PROGRAM="$ninja" -DCMAKE_TOOLCHAIN_FILE="$work/toolchain.cmake" \
    -DCMAKE_BUILD_TYPE="$buildtype" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 "${options[@]}" >"$log" 2>&1
"$cmake" --build "$work/build" --target "${targets[@]}" --parallel 8 >>"$log" 2>&1
if [ "$codec" = mozjpeg ]; then
    mkdir -p "$output/include/mozjpeg"
    cp "$work/source/"{jpeglib.h,jmorecfg.h,turbojpeg.h} "$output/include/mozjpeg/"
    cp "$work/build/jconfig.h" "$output/include/mozjpeg/"
    cp "$work/build/"{libjpeg.a,libturbojpeg.a} "$output/lib/"
    pc_libs='-ljpeg -lturbojpeg -lm'
else
    mkdir -p "$output/include/jxl"
    cp "$work/build/lib/include/jxl/"*.h "$output/include/jxl/"
    cp "$work/build/lib/"{libjxl.a,libjxl_cms.a} "$output/lib/"
    cp "$work/build/third_party/highway/libhwy.a" "$output/lib/"
    cp "$work/build/third_party/brotli/"{libbrotlicommon.a,libbrotlidec.a,libbrotlienc.a} "$output/lib/"
    pc_libs='-ljxl -ljxl_cms -lhwy -lbrotlienc -lbrotlidec -lbrotlicommon -lc++ -lm'
fi
cat > "$output/lib/pkgconfig/$codec.pc" <<PC
prefix=\${pcfiledir}/../..
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: $codec
Description: Static $codec for Apple arm64
Version: $version
Libs: -L\${libdir} $pc_libs
Cflags: -I\${includedir}
PC
printf '%s\n' "$codec $version" "$cpu $mode" "target=$triple" > "$output/build-info.txt"
rm -rf "$work"
