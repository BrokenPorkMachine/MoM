#!/bin/bash
set -euo pipefail
APP="${1:?Usage: $0 /path/to/VolumeBoot.app}"
PLIST="$APP/Contents/Library/LaunchDaemons/ca.zensoftware.VolumeBoot.RawDiskBroker.plist"
DAEMON="$APP/Contents/MacOS/VolumeBootRawDiskDaemon"
[[ -f "$PLIST" && -x "$DAEMON" ]] || { echo 'Missing packaged daemon or launchd plist' >&2; exit 1; }
plutil -lint "$PLIST"
/usr/bin/codesign --verify --strict --verbose=2 "$DAEMON"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
APP_TEAM="$(/usr/bin/codesign -dv --verbose=4 "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
DAEMON_TEAM="$(/usr/bin/codesign -dv --verbose=4 "$DAEMON" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
[[ -n "$APP_TEAM" && "$APP_TEAM" != 'not set' && "$APP_TEAM" == "$DAEMON_TEAM" ]] || {
  echo 'Missing/mismatched Developer Team identifiers; privileged registration must remain disabled' >&2
  exit 1
}
DAEMON_IDENTIFIER="$(/usr/bin/codesign -dv --verbose=4 "$DAEMON" 2>&1 | sed -n 's/^Identifier=//p')"
APP_IDENTIFIER="$(/usr/bin/codesign -dv --verbose=4 "$APP" 2>&1 | sed -n 's/^Identifier=//p')"
[[ "$APP_IDENTIFIER" == 'ca.zensoftware.VolumeBoot' && "$DAEMON_IDENTIFIER" == 'ca.zensoftware.VolumeBoot.RawDiskBroker' ]] || {
  echo "Wrong code-signing identifier: app=$APP_IDENTIFIER daemon=$DAEMON_IDENTIFIER" >&2
  echo "Ensure Xcode is configured to sign the tool with the exact daemon identifier" >&2
  exit 1
}
echo "Verified matching Developer Team, expected code-signing identifiers and nested signatures: $APP_TEAM"
