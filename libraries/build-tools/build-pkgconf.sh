#!/bin/bash
set -euo pipefail

exec_root="$PWD"
configure="$exec_root/$1"
output="$exec_root/$2"
work="${output}.work"
rm -rf "$work"
mkdir -p "$work/source" "$work/build" "$(dirname "$output")"

cp -pRL "$(dirname "$configure")/." "$work/source/"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
cc="$(xcrun --sdk macosx --find clang)"
log="$work/build.log"
trap 'result=$?; if [ "$result" -ne 0 ] && [ -f "$log" ]; then tail -80 "$log" >&2; fi' EXIT
(
    cd "$work/build"
    CC="$cc" CFLAGS="-O2 --target=arm64-apple-macosx14.0 -isysroot $sdk" \
        "$work/source/configure" --disable-shared --enable-static --disable-dependency-tracking
    make -j4
) >"$log" 2>&1
cp "$work/build/pkgconf" "$output"
chmod +x "$output"
"$output" --version
rm -rf "$work"
