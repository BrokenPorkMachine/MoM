#!/bin/zsh
set -euo pipefail
app="${1:-}"
[[ -n "$app" && -d "$app" ]] || { echo "usage: $0 <MacOnMac.app>" >&2; exit 2; }
/usr/bin/codesign --verify --deep --strict "$app"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" | grep -qx 'ca.zensoftware.MacOnMac'
[[ -x "$app/Contents/MacOS/MacOnMacRawDiskDaemon" ]]
[[ -f "$app/Contents/Library/LaunchDaemons/ca.zensoftware.MacOnMac.RawDiskBroker.plist" ]]
echo "PASS: signed app structure and daemon capability boundary verified"
