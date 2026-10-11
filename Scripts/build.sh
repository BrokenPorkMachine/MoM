#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project MacOnMac.xcodeproj -scheme MacOnMac -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
