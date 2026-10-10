# VolumeBoot Guest Tools v2 — Component Specification

**Release:** 0.16.0  
**Status:** Implemented at source level; macOS host, guest, Xcode, launchd runtime validation outstanding.

## Goals

Provide usable host/guest collaboration over the opt-in VirtioFS `Exchange` share without enabling arbitrary guest/host command execution. Keep NAT as the default networking mode; Guest Tools works even when the guest NIC is disconnected, because the transport is a VM-shared directory, not a socket or LAN service.

### New operations

| Capability | Host | Guest | Consent/safety |
|---|---|---|---|
| Plain-text clipboard offer | UI or `clipboard-send [text]` | `clipboard-send [text]` | Explicit action; receiver explicitly imports |
| Read clipboard offer | UI / `clipboard-peek` | `clipboard-peek` | No automatic OS clipboard observation |
| Import clipboard text | UI / `clipboard-import` | `clipboard-import` | Explicit user operation; no image/password-manager syncing |
| Pairing | `pair-init`, `pair-code` | `pair <hex>` | Manual out-of-band transfer, key stored outside Exchange |
| Authenticated request | `ping`, `request-status` | `serve` / `poll-once` | Allowlist **ping and status only**; no shell, script or file execution |
| Authenticated reply | `replies` | Created by agent | HMAC-SHA256, timestamp check, matching UUID |
| Chunked file staging | `push <file>` | `push <file>` | <=64 MiB, streaming progress, SHA-256 receipt |
| Network diagnosis | `diagnose` / panel | `status`/`serve` | Mode + heartbeat + authenticated response; **not** a DHCP or internet test |
| Login installation | N/A | `install-guest-agent.sh install` | Explicit per-user LaunchAgent, no root required |

## Transport schema

The host owns `<VM Bundle>/Exchange`. It is mounted to macOS guests as `/Volumes/My Shared Files/Exchange` by Virtualization.framework, when Guest Tools is enabled. Existing v1 directories remain:

```
Exchange/
  host-to-guest/       # simple message JSON (v1)
  guest-to-host/       # simple message JSON (v1)
  host-files/          # completed uploads and transfer receipts
  guest-files/         # completed uploads and transfer receipts
  heartbeat.json
  host-clipboard/      # timestamped text offers
  guest-clipboard/
  requests/            # signed restricted requests
  replies/             # signed restricted replies
```

Files under `requests` and `replies` use UUID `.json` names and a protocol-version field (`2`). Request MAC input is the UTF-8 string `request|2|<UUID>|<milliseconds>|<action>`. Reply MAC input is `reply|2|<UUID>|<milliseconds>|<base64(detail)>`. HMAC-SHA256 is verified using constant-time byte comparison. Requests must be within ±120 seconds of the receiving clock, and replies must correspond to a verified request. Guest agent keeps a per-process `seen` set to suppress reprocessing. Restarting the agent can reprocess a request during the TTL; all allowed actions are read-only/idempotent. No commands other than `ping` and `status` are allowed by the typed decoder.

**Secrets:** Host key: `<VM Bundle>/.guesttools-pairing-key`; guest key: `~/.config/VolumeBoot/guesttools-pairing-key`. Each is 32 random bytes created/stored with owner-only permissions. Neither lives inside the VirtioFS exchange, though access to the VM bundle by other host users remains governed by host filesystem permissions. Displayed pairing codes and command-line history are sensitive. The `pair` command intentionally refuses to overwrite an existing guest key; pair-reset requires explicit local deletion or a future revoke/rekey workflow.

**Important scope statement:** Authentication applies **only** to the restricted ping/status request and reply records. Legacy messages, file receipts, clipboard offers and heartbeat records are **not authenticated**. The exchange is not safe to mount into an adversarial guest as a privileged host IPC interface. The pairing secret does not grant filesystem access or additional host privileges.

## File transfers

The maximum file size is 64 MiB. A source must be a regular non-symlink file. Transfers use 128 KiB chunks with progress callbacks; the source is written to an ephemeral UUID `.partial` file and renamed into a UUID final name only after all expected bytes have been written and flushed. A companion `<UUID>.transfer.json` includes original display name, transferred byte count, and SHA-256 hash. The manifest is published after the data. The receiving side should verify the final file's byte count and SHA-256 before treating it as completed.

Receipts detect accidental modification; they are **not** authenticated and therefore provide no security against a guest able to alter both bytes and receipt. MIME/content type should not be trusted. Never auto-open or execute staged files. Progress does not imply the receiving application consumed the file. Current implementation is still subject to filesystem TOCTOU and symlink races in a guest-writable directory; hardened `openat` + ownership model is future work.

## UI behavior

- The `Network & Guest Integration` panel exposes manual clipboard send/receive and the latest exchange/status information.
- `Show pairing code` is a sensitive operation that makes the key visible onscreen; treat screenshots as sensitive.
- `Send authenticated ping` queues a request but does not imply a reply. Press `Refresh` after guest agent polls it.
- File staging runs off the main actor with a progress bar, and only one UI transfer is active at a time.
- VM NIC setting changes require the VM to restart; guest tools data operations do not.

## Guest installation / uninstall

1. Build agent on macOS host: `./Scripts/build-guest-agent.sh`.
2. Transfer binary (and installer script) to a **trusted** macOS guest, e.g. via the VM's `Workspace` share. The `Exchange` share is not necessarily suitable for first-run binary installation.
3. Inside the guest, explicitly run `./Scripts/install-guest-agent.sh install /path/to/volumeboot-guest-agent`.
4. Optionally pair: on host `volumeboot-host '<VM>' pair-init`; inside guest run `volumeboot-guest-agent pair <hex-from-host>`. Be aware terminal history may retain secrets.
5. `./Scripts/install-guest-agent.sh status` / `uninstall` works **inside the guest**. Uninstall retains the pairing secret; delete it manually if you are retiring the VM.

The installer is per-user only, does not use sudo, adds no login item to the host, does not change host network/firewall settings, and uses a KeepAlive user LaunchAgent.

## Limits / security review blockers

- No arbitrary command execution, remote shell, guest access to host passwords, disk passthrough, credential distribution, or unattended clipboard sync.
- No resumable multi-gigabyte transfers, compression, transfer cancel UI, live network RTT probe, IP/DHCP discovery, or first-run binary authenticity verification.
- No mutual session key rotation, persistent replay ledger, hardened directory-FD based IO, or cross-machine code-signing attestation in Guest Tools v2.
- Source-level tests on Linux cannot establish actual macOS guest VirtioFS mounting, AppKit clipboard semantics, LaunchAgent load, Xcode compatibility, or network reachability.

## Code locations

- `Core/GuestToolsProtocol.swift`: SHA/HMAC, keys, requests, replies, clipboard, file receipts, transfer.
- `Tools/HostTool/HostCLI.swift`: host CLI commands.
- `Tools/GuestAgent/main.swift`: guest agent commands and polling.
- `Scripts/install-guest-agent.sh`: guest user LaunchAgent deployment.
- `App/AppModel.swift`, `App/DashboardView.swift`: main UI integrations.
- `Tests/GuestToolsProtocolTests.swift`, `Scripts/test-guest-tools-v2.sh`, `Scripts/test-guest-host-e2e.sh`: regression tests.
