#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
VM="$TEMP/TestVM"
mkdir -p "$VM/Exchange/host-to-guest" "$VM/Exchange/guest-to-host" "$VM/Exchange/host-files" "$VM/Exchange/guest-files"
cat > "$VM/connectivity.json" <<'JSON'
{"version":1,"networkMode":"nat","bridgedInterfaceID":null,"sharedFolderPath":null,"shareReadOnly":true,"guestToolsEnabled":true}
JSON
swiftc Core/HostGuestExchange.swift Core/GuestToolsProtocol.swift Tools/GuestAgent/main.swift -o "$TEMP/guest-agent"
swiftc Core/VMConnectivity.swift Core/HostGuestExchange.swift Core/GuestToolsProtocol.swift Tools/HostTool/HostCLI.swift -o "$TEMP/host-tool"
VOLUMEBOOT_EXCHANGE="$VM/Exchange" "$TEMP/guest-agent" status > "$TEMP/guest.log"
"$TEMP/host-tool" "$VM" status | grep -q 'Guest:'
"$TEMP/host-tool" "$VM" send 'host hello' > /dev/null
VOLUMEBOOT_EXCHANGE="$VM/Exchange" "$TEMP/guest-agent" inbox | grep -q 'host hello'
VOLUMEBOOT_EXCHANGE="$VM/Exchange" "$TEMP/guest-agent" send 'guest hello' > /dev/null
"$TEMP/host-tool" "$VM" inbox | grep -q 'guest hello'
printf 'test transfer\n' > "$TEMP/sample.txt"
"$TEMP/host-tool" "$VM" push "$TEMP/sample.txt" > /dev/null
VOLUMEBOOT_EXCHANGE="$VM/Exchange" "$TEMP/guest-agent" files | grep -q '\.txt'
VOLUMEBOOT_EXCHANGE="$VM/Exchange" "$TEMP/guest-agent" push "$TEMP/sample.txt" > /dev/null
"$TEMP/host-tool" "$VM" guest-files | grep -q '\.txt'
# New protocol exercises authenticated ping and manually accepted clipboard offers.
PAIR_CODE="$("$TEMP/host-tool" "$VM" pair-init | awk '{print $NF}')"
VOLUMEBOOT_GUEST_KEY_FILE="$TEMP/guest-pairing.key" "$TEMP/guest-agent" pair "$PAIR_CODE" > /dev/null
"$TEMP/host-tool" "$VM" ping > /dev/null
VOLUMEBOOT_GUEST_KEY_FILE="$TEMP/guest-pairing.key" VOLUMEBOOT_EXCHANGE="$VM/Exchange" "$TEMP/guest-agent" poll-once > /dev/null
"$TEMP/host-tool" "$VM" replies | grep -q pong
"$TEMP/host-tool" "$VM" clipboard-send 'host clipboard demo' > /dev/null
VOLUMEBOOT_EXCHANGE="$VM/Exchange" "$TEMP/guest-agent" clipboard-peek | grep -q 'host clipboard demo'
VOLUMEBOOT_EXCHANGE="$VM/Exchange" "$TEMP/guest-agent" clipboard-send 'guest clipboard demo' > /dev/null
"$TEMP/host-tool" "$VM" clipboard-peek | grep -q 'guest clipboard demo'
"$TEMP/host-tool" "$VM" diagnose | grep -q 'Authenticated responses: 1'
TRANSFER_RECEIPT="$(find "$VM/Exchange/host-files" -type f -name '*.transfer.json' -print | head -1)"
test -n "$TRANSFER_RECEIPT" && test -f "$TRANSFER_RECEIPT"
echo 'PASS: agent heartbeat, signed request/reply, clipboard offers, messages, staged files and receipts' 
