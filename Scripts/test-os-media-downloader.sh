#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -m)" != "arm64" ]]; then
    echo "SKIP: macOS restore-image downloader requires Apple Silicon"
    exit 0
fi
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
swiftc -module-cache-path "$temp/ModuleCache" Core/OSMediaDownloader.swift Tests/OSMediaDownloaderTests.swift -o "$temp/os-media-downloader-tests"
"$temp/os-media-downloader-tests"
