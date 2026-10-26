#!/bin/bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
version=0.65.1
archive_sha256=c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0
tool_directory="$repo_root/cache/swiftlint/$version"
binary="$tool_directory/swiftlint"

if [[ "$(uname -s)" != Darwin ]]; then
    echo 'SwiftLint for Contact requires macOS and Xcode.' >&2
    exit 1
fi

if [[ ! -x "$binary" ]]; then
    mkdir -p "$tool_directory"
    temporary="$(mktemp -d "$tool_directory/download.XXXXXX")"
    trap 'rm -rf -- "$temporary"' EXIT
    echo "Downloading SwiftLint $version..." >&2
    curl --fail --location --retry 2 \
        --output "$temporary/swiftlint.zip" \
        "https://github.com/realm/SwiftLint/releases/download/$version/portable_swiftlint.zip"
    printf '%s  %s\n' "$archive_sha256" "$temporary/swiftlint.zip" | shasum -a 256 --check --status
    unzip -q "$temporary/swiftlint.zip" -d "$temporary/unpacked"
    install -m 755 "$temporary/unpacked/swiftlint" "$temporary/swiftlint"
    mv -f "$temporary/swiftlint" "$binary"
    rm -rf -- "$temporary"
    trap - EXIT
fi

if [[ "$("$binary" version)" != "$version" ]]; then
    echo "Unexpected SwiftLint version in $tool_directory; remove that cache directory and retry." >&2
    exit 1
fi

cd "$repo_root"
exec "$binary" "$@"
