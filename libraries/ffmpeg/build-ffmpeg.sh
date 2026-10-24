#!/bin/bash
# FFmpeg's configure/Make owns component selection and generated config files.
set -euo pipefail

cpu="$1"
mode="$2"
exec_root="$PWD"
output="$exec_root/$3"
pkgconf="$exec_root/$4"
gas_preprocessor="$exec_root/$5"
shift 5

case "$cpu" in
    ios_arm64) sdk=iphoneos; triple=arm64-apple-ios16.0 ;;
    ios_sim_arm64) sdk=iphonesimulator; triple=arm64-apple-ios16.0-simulator ;;
    darwin_arm64) sdk=macosx; triple=arm64-apple-macosx14.0 ;;
    *) echo "Unsupported FFmpeg target: $cpu" >&2; exit 1 ;;
esac

sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
cc="$(xcrun --sdk "$sdk" --find clang)"
ar="$(xcrun --sdk "$sdk" --find ar)"
ranlib="$(xcrun --sdk "$sdk" --find ranlib)"
strip="$(xcrun --sdk "$sdk" --find strip)"
jobs="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)"
if [ "$jobs" -gt 8 ]; then jobs=8; fi
work="$output/.ffmpeg-work"
rm -rf "$work"
mkdir -p "$work/source" "$work/build" "$work/deps/lib/pkgconfig" "$work/deps/include"
cp -RL "$exec_root/libraries/ffmpeg/ffmpeg/." "$work/source/"
for input in "$@"; do
    case "$input" in
        */include/*) relative="include/${input#*/include/}" ;;
        */lib/*) relative="lib/${input#*/lib/}" ;;
        *) echo "Unexpected FFmpeg dependency input: $input" >&2; exit 1 ;;
    esac
    mkdir -p "$(dirname "$work/deps/$relative")"
    cp "$exec_root/$input" "$work/deps/$relative"
done

export PKG_CONFIG_LIBDIR="$work/deps/lib/pkgconfig"
export PKG_CONFIG_PATH=""
export PKG_CONFIG_SYSROOT_DIR=""
"$pkgconf" --exists 'vpx >= 1.4.0' 'opus >= 1.6.1' 'dav1d >= 1.0.0'
log="$work/build.log"
trap 'result=$?; if [ "$result" -ne 0 ]; then test ! -f "$log" || tail -100 "$log" >&2; test ! -f "$work/build/ffbuild/config.log" || tail -60 "$work/build/ffbuild/config.log" >&2; fi' EXIT

options=(--disable-debug)
if [ "$mode" = dbg ]; then
    options=(--enable-debug --disable-optimizations --disable-stripping)
fi
flags="--target=$triple -isysroot $sdk_path -fPIC -DCONFIG_SAFE_BITSTREAM_READER=1"
echo "Configuring FFmpeg 9.0.2 for $cpu ($mode)"
(
    cd "$work/build"
    "$work/source/configure" \
        --prefix="$output" --target-os=darwin --arch=aarch64 --enable-cross-compile \
        --cc="$cc" --ld="$cc" --ar="$ar" --ranlib="$ranlib" --strip="$strip" \
        --as="/usr/bin/perl $gas_preprocessor -arch aarch64 -as-type apple-clang -- $cc" \
        --extra-cflags="$flags" --extra-objcflags="$flags" \
        --extra-ldflags="--target=$triple -isysroot $sdk_path" \
        --pkg-config="$pkgconf" --pkg-config-flags=--static \
        --disable-all --disable-everything --disable-autodetect \
        --disable-programs --disable-doc --disable-checkasm --disable-network \
        --disable-gpl --disable-nonfree --enable-static --disable-shared --enable-pic \
        --enable-avutil --enable-avcodec --enable-avformat --enable-swresample \
        --enable-pthreads --enable-zlib --enable-bzlib --enable-iconv \
        --enable-audiotoolbox --enable-videotoolbox \
        --enable-libvpx --enable-libopus --enable-libdav1d \
        --enable-decoder=h264,hevc,av1,libvpx_vp9,libopus,flac,pcm_s16le,pcm_s24le,pcm_f32le,libdav1d,mp3,alac_at,gsm_ms_at,aac_at \
        --enable-encoder=libvpx_vp9,aac_at \
        --enable-demuxer=aac,mov,m4v,mp3,ogg,flac,wav,aiff,matroska,mpegts \
        --enable-muxer=mp4,matroska,ogg,mpegts \
        --enable-parser=aac,aac_latm,h264,hevc,mpegaudio,opus,av1 \
        --enable-bsf=aac_adtstoasc,vp9_superframe,h264_mp4toannexb \
        --enable-protocol=file \
        --enable-hwaccel=h264_videotoolbox,hevc_videotoolbox,av1_videotoolbox \
        --fatal-warnings "${options[@]}"
    make -j"$jobs"
    make install
) >"$log" 2>&1

/usr/bin/python3 - "$output" "$work" "$cpu" "$mode" <<'PY'
from pathlib import Path
import re
import sys
out, work = map(Path, sys.argv[1:3])
config = (work / 'build/config_components.h').read_text()
required = ['H264_DECODER', 'HEVC_DECODER', 'LIBVPX_VP9_DECODER', 'LIBVPX_VP9_ENCODER',
            'LIBOPUS_DECODER', 'LIBDAV1D_DECODER', 'AAC_AT_DECODER', 'AAC_AT_ENCODER',
            'MOV_DEMUXER', 'MATROSKA_DEMUXER', 'OGG_DEMUXER', 'MP4_MUXER', 'FILE_PROTOCOL',
            'H264_VIDEOTOOLBOX_HWACCEL', 'HEVC_VIDEOTOOLBOX_HWACCEL', 'AV1_VIDEOTOOLBOX_HWACCEL']
for component in required:
    assert f'#define CONFIG_{component} 1' in config, component
for pc in (out / 'lib/pkgconfig').glob('*.pc'):
    text = pc.read_text().replace(str(work / 'deps'), '${prefix}')
    values = {'prefix': '${pcfiledir}/../..', 'libdir': '${prefix}/lib', 'includedir': '${prefix}/include'}
    lines = text.splitlines()
    text = '\n'.join(k + '=' + values[k] if (k := line.split('=', 1)[0]) in values else line for line in lines) + '\n'
    pc.write_text(text)
assert '9.0.2' in (out / 'include/libavutil/ffversion.h').read_text()
enabled = sorted(re.findall(r'^#define CONFIG_(\w+) 1$', config, re.M))
(out / 'build-info.txt').write_text('FFmpeg 9.0.2\nTarget: ' + sys.argv[3] + '\nMode: ' + sys.argv[4] +
    '\nLicense: LGPL (GPL/nonfree disabled)\n\nEnabled components:\n' + '\n'.join(enabled) + '\n')
PY
echo "Built FFmpeg 9.0.2: $cpu, $mode"
rm -rf "$work"
