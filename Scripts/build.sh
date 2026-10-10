#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project VolumeBoot.xcodeproj -scheme VolumeBoot -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
