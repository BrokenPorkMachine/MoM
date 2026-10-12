# Host / Guest Integration Tools — v0.15.0

## Primary transport: VirtioFS

VolumeBoot exposes **up to two selected shares** through one VirtioFS device using the `macOSGuestAutomountTag`, auto-mounted in macOS 13+ guests at `/Volumes/My Shared Files/`.

| Guest path | Host path | Mode |
|---|---|---|
| `/Volumes/My Shared Files/Workspace` | Host-chosen folder outside VM bundle | Read-only by default; optional read/write |
| `/Volumes/My Shared Files/Exchange` | `<VM Folder>/Exchange` | Opt-in read/write, narrowly scoped message/file area |

The selected workspace directory cannot be an ancestor or descendant of the VM folder, the filesystem root, a device node, or a missing directory. Users must opt in to the exchange separately. The app writes `connectivity.json` on successful save/provision; a VM restart is needed for device changes.

## Exchange layout

```
Exchange/
  host-to-guest/   # UUID-named JSON messages
  guest-to-host/   # UUID-named JSON messages
  host-files/      # authenticated host-staged files (up to 64 MiB each)
  guest-files/     # authenticated guest-staged files (up to 64 MiB each)
  heartbeat.json   # last guest report (untrusted guest data)
```

This is a **data-only** protocol: receiving a message never runs it as a command. Message bodies are capped at 16 KiB, files at 64 MiB, and filenames are randomly generated. File staging and receiving require pairing. File listings verify the authenticated receipt and streamed payload digest; receiving verifies them again while copying. Uploaded files remain untrusted and must not be auto-opened or executed. Each direction retains up to 100 files / 256 MiB for 7 days, 500 messages / 8 MiB for 7 days, and 20 clipboard offers / 1 MiB for 10 minutes. Do not enable for untrusted guests; receipt authentication does not make the shared directory a privileged IPC boundary.

## Build and install companion tools

On macOS host:

```bash
./Scripts/build-host-tool.sh
./Scripts/build-guest-agent.sh
```

The build produces:

- `build/volumeboot-host` — run on host
- `build/volumeboot-guest-agent` — copy into guest via Workspace or Exchange and mark executable

In macOS guest, after enabling Guest Tools, restarting the VM, and copying binary:

```bash
chmod +x ./volumeboot-guest-agent
./volumeboot-guest-agent status
./volumeboot-guest-agent serve
./volumeboot-guest-agent send "Guest desktop online"
./volumeboot-guest-agent inbox
./volumeboot-guest-agent push ~/Desktop/report.txt
./volumeboot-guest-agent files
./volumeboot-guest-agent receive <transfer-id> ~/Downloads
```

The guest agent uses `/Volumes/My Shared Files/Exchange` by default, or `VOLUMEBOOT_EXCHANGE` environment variable for manual testing. `serve` writes a heartbeat every 10 seconds and does not listen on TCP, vsock, or any network port. The sample `Resources/GuestAgent/ca.zensoftware.VolumeBoot.GuestAgent.plist` is an *optional* per-user launch agent: change the executable location if needed, then install under `~/Library/LaunchAgents/` **inside the guest** only with explicit user approval. It is not installed automatically.

On host:

```bash
./build/volumeboot-host "/path/to/InstalledVM" status
./build/volumeboot-host "/path/to/InstalledVM" inbox
./build/volumeboot-host "/path/to/InstalledVM" send "Hello guest"
./build/volumeboot-host "/path/to/InstalledVM" push ~/Documents/example.txt
./build/volumeboot-host "/path/to/InstalledVM" guest-files
./build/volumeboot-host "/path/to/InstalledVM" receive <transfer-id> ~/Downloads
```

The application's **Network & Guest Tools** panel provides profile editing, messaging, staging host files, heartbeat display, viewing guest messages, and opening the exchange in Finder.

## Deliberately excluded from v0.15

Automatic clipboard synchronization, drag/drop, remote shell, arbitrary command execution, guest screen capture, unattended host command dispatch, guest filesystem mounting, direct guest access to host disks, SSH credential distribution, and TCP control servers. These require an independent consent/authentication and transport review. The guest agent does **not** install drivers or additional kernel extensions.

## Validation / known gaps

Portable tests cover configuration policy, persistence, message limits, staging, and CLI type-checking. End-to-end host/guest mounting, app compilation, bridging entitlement signing, bandwidth, VM networking, and the launch-agent startup flow require local macOS verification.

Apple reference: https://developer.apple.com/documentation/virtualization/vzvirtiofilesystemdeviceconfiguration

## v0.16.0 Guest Tools v2

See [GUEST_TOOLS_V2_SPEC.md](GUEST_TOOLS_V2_SPEC.md) for the authentication scope, new CLI syntax, manual clipboard offers, transfer receipts, progress, and opt-in LaunchAgent installer. Legacy file messages are still unauthenticated. Never treat the shared directory as a privileged IPC bus with an untrusted guest.
