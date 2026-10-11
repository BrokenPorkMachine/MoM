#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  print -u2 'UI previews require an Apple Silicon Mac.'
  exit 1
fi
UI_PREVIEW_OUTPUT="${1:-/private/tmp/volumeboot-ui-review}"
UI_PREVIEW_SCRATCH="$(mktemp -d)"
trap 'rm -rf "$UI_PREVIEW_SCRATCH"' EXIT
UI_PREVIEW_SDK="$(xcrun --show-sdk-path)"
# CLI Swift 6.4 lacks the SwiftUI State plugin used by the macOS 27 SDK.
if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk ]]; then
  UI_PREVIEW_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
fi
UI_PREVIEW_SOURCES=(App/*.swift)
UI_PREVIEW_SOURCES=(${UI_PREVIEW_SOURCES:#App/VolumeBootApp.swift})
swiftc -target arm64-apple-macos15.0 -sdk "$UI_PREVIEW_SDK" \
  -module-cache-path "${CLANG_MODULE_CACHE_PATH:-$UI_PREVIEW_SCRATCH/module-cache}" \
  "${UI_PREVIEW_SOURCES[@]}" Core/*.swift Tests/UIRenderProbe.swift -o "$UI_PREVIEW_SCRATCH/ui-preview"
codesign --force --sign - --entitlements Resources/MacOnMac.entitlements "$UI_PREVIEW_SCRATCH/ui-preview"
"$UI_PREVIEW_SCRATCH/ui-preview" "$UI_PREVIEW_OUTPUT"
