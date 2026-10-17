#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
find App Core Helpers Privileged Tools/GuestAgent Tools/HostTool -name '*.swift' -exec swiftc -frontend -parse '{}' ';'
python3 - <<'PY2'
import plistlib
from pathlib import Path
for p in [Path('Resources/Info.plist'),Path('Helpers/VolumeBootDiskBroker/Info.plist'),Path('Resources/LaunchDaemons/ca.zensoftware.MacOnMac.RawDiskBroker.plist')]:
    with p.open('rb') as f: plistlib.load(f)
print('Plist validation: OK')
PY2

./Scripts/test-broker-contract.sh
./Scripts/test-broker-policy.sh
./Scripts/test-safety.sh
./Scripts/test-diskutil-process.sh

./Scripts/test-daemon-contract.sh
./Scripts/test-grant-policy.sh

./Scripts/test-topology-proof.sh
python3 Scripts/check-project-sources.py
python3 Tests/ProjectStructureTests.py

./Scripts/test-connectivity.sh
./Scripts/test-disk-images.sh
./Scripts/test-arm-guests.sh

./Scripts/test-guest-host-e2e.sh
./Scripts/test-guest-tools-v2.sh
