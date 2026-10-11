#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swiftc Core/DaemonBrokerContract.swift Core/BrokerAuthorizationPolicy.swift Tests/DaemonContractTests.swift -o "$TMP/daemon-contract"
"$TMP/daemon-contract"
python3 - <<'PYPLIST'
import plistlib
from pathlib import Path
import yaml
p=plistlib.load(open('Resources/LaunchDaemons/ca.zensoftware.MacOnMac.RawDiskBroker.plist','rb'))
assert p['Label']=='ca.zensoftware.MacOnMac.RawDiskBroker'
assert p['BundleProgram']=='Contents/MacOS/VolumeBootRawDiskDaemon'
assert p['MachServices'][p['Label']] is True
assert p['AssociatedBundleIdentifiers']==['ca.zensoftware.MacOnMac']
project=yaml.safe_load(Path('project.yml').read_text())
assert 'MacOnMacRawDiskDaemon' in project['targets']
assert project['targets']['MacOnMacRawDiskDaemon']['type']=='tool'
assert 'MacOnMacRawDiskDaemon' in str(project['targets']['MacOnMac']['postBuildScripts'])
print('Daemon packaging metadata PASS: plist / XcodeGen references')
PYPLIST
