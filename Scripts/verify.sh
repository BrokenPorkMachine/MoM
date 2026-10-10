#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
plutil -lint Resources/Info.plist Resources/VolumeBoot.entitlements Resources/LaunchDaemons/ca.zensoftware.VolumeBoot.RawDiskBroker.plist
./Scripts/generate-xcodeproj.sh
./Scripts/test-daemon-contract.sh
./Scripts/test-grant-policy.sh
./Scripts/test-topology-proof.sh
./Scripts/test-connectivity.sh
./Scripts/test-disk-images.sh
./Scripts/test-guest-host-e2e.sh
./Scripts/test-guest-tools-v2.sh
./Scripts/build-claim-lab.sh
xcodebuild -list -project VolumeBoot.xcodeproj
xcodebuild -project VolumeBoot.xcodeproj -scheme VolumeBoot -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
