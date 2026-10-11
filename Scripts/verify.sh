#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
plutil -lint Resources/Info.plist Resources/MacOnMac.entitlements Resources/LaunchDaemons/ca.zensoftware.MacOnMac.RawDiskBroker.plist
plutil -lint MacOnMac.xcodeproj/project.pbxproj
python3 Scripts/check-project-sources.py
python3 Tests/ProjectStructureTests.py
./Scripts/test-daemon-contract.sh
./Scripts/test-grant-policy.sh
./Scripts/test-topology-proof.sh
./Scripts/test-connectivity.sh
./Scripts/test-disk-images.sh
./Scripts/test-arm-guests.sh
./Scripts/test-guest-host-e2e.sh
./Scripts/test-guest-tools-v2.sh
./Scripts/build-claim-lab.sh
xcodebuild -list -project MacOnMac.xcodeproj
xcodebuild -project MacOnMac.xcodeproj -scheme MacOnMac -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
