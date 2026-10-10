#!/bin/bash
# Run INSIDE the macOS guest as the logged-in user. Never uses sudo.
set -euo pipefail
if [[ "$(uname -s)" != "Darwin" ]]; then echo 'Guest installation requires macOS' >&2; exit 1; fi
LABEL=ca.zensoftware.VolumeBoot.GuestAgent
AGENT_DIR="$HOME/Library/Application Support/VolumeBoot/bin"
AGENT="$AGENT_DIR/volumeboot-guest-agent"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
TARGET="gui/$(id -u)/$LABEL"
case "${1:-}" in
  install)
    if [[ $# -ne 2 || ! -f "$2" ]]; then echo "Usage: $0 install /path/to/volumeboot-guest-agent" >&2; exit 2; fi
    echo 'Installing guest agent for this user (no root privilege, no network listener).'
    mkdir -p "$AGENT_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/VolumeBoot"
    chmod 700 "$AGENT_DIR"
    install -m 700 "$2" "$AGENT"
    [[ ! -e "$PLIST" ]] || launchctl bootout "$TARGET" 2>/dev/null || true
    rm -f -- "$PLIST"
    /usr/bin/plutil -create xml1 "$PLIST"
    /usr/bin/plutil -insert Label -string "$LABEL" "$PLIST"
    /usr/bin/plutil -insert ProgramArguments -xml '<array/>' "$PLIST"
    /usr/bin/plutil -insert ProgramArguments.0 -string "$AGENT" "$PLIST"
    /usr/bin/plutil -insert ProgramArguments.1 -string serve "$PLIST"
    /usr/bin/plutil -insert RunAtLoad -bool YES "$PLIST"
    /usr/bin/plutil -insert KeepAlive -bool YES "$PLIST"
    /usr/bin/plutil -lint "$PLIST"
    chmod 600 "$PLIST"
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    echo "Installed $LABEL (guest user only). To stop: $0 uninstall"
    ;;
  uninstall)
    launchctl bootout "$TARGET" 2>/dev/null || true
    rm -f -- "$PLIST" "$AGENT"
    echo 'Stopped and removed guest agent. Pairing key retained; delete separately if desired.'
    ;;
  status)
    if [[ -f "$AGENT" ]]; then echo "Agent installed: $AGENT"; else echo 'Agent not installed'; fi
    launchctl print "$TARGET" 2>/dev/null || true
    ;;
  *) echo "Usage: $0 install <guest-agent-binary> | uninstall | status" >&2; exit 2;;
esac
