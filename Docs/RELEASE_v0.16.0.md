# VolumeBoot v0.16.0 — Guest Integration & Networking Polish

## Implemented in source

- Opt-in bidirectional **plain-text clipboard offers**: host and guest can explicitly offer text and explicitly import it into the local clipboard. No periodic clipboard monitoring.
- **Authenticated ping/status guest requests**: manually provisioned per-VM/guest pairing key, HMAC-SHA256, protocol v2, timestamp age checks, per-process deduplication, signed replies; only ping/status are accepted. No shell execution.
- **Paired file transfers** with chunked writes, progress callbacks, immutable UUID-based names, HMAC-authenticated receipts, streamed digest checks on listing and receive, and explicit save-to-folder operations.
- **Bounded exchange retention**: per direction, 100 files / 256 MiB for 7 days; 500 messages / 8 MiB for 7 days; 20 clipboard offers / 1 MiB for 10 minutes. Requests and replies expire after 10 minutes and are capped at 200 records / 2 MiB.
- **Networking diagnostics** showing configured VM network mode, age of guest heartbeat, and count/latest signed response. These are integration diagnostics, not independent tests of DHCP, DNS, guest IP, or internet connectivity.
- **Guest login installation script** using a per-user macOS LaunchAgent and an explicit uninstall path; no root or daemon installation.
- SwiftUI guest-tools pane enhancements for clipboard, pairing, signed ping, transfer progress, and diagnostics.
- Portable protocol regression suite plus CLI simulated host/guest round trip. All existing v0.15 networking behavior preserved, including NAT/bridged/disconnected modes and VirtioFS workspace sharing.

## Tests and scope

Run `./Scripts/verify-linux.sh` for portable parser, policy, Xcode source registry and CLI tests. `./Scripts/verify.sh` additionally requires a Mac with a macOS SDK/Xcode and may require updating your signing team. `Scripts/build-host-tool.sh` and `Scripts/build-guest-agent.sh` build standalone utilities using the macOS SDK.

**Not verified in this release environment:** full Xcode macOS app build, complete VM boot, signed privileged daemon deployment, macOS AppKit clipboard functionality, guest launchd installation, live NAT/bridging/DHCP, physical USB/NVMe passthrough.

## Safety

- Guest Tools does not execute messages as code or grant shell access.
- Guest Tools messages and clipboard data remain untrusted; v2 ping/status requests, replies, and file receipts are keyed and authenticated.
- A writable VirtioFS directory is not a hardened hostile-guest isolation boundary. Do not use the feature with untrusted guest operating systems.
- Direct boot from an existing physical macOS installation is still not implemented. APFS disks remain blocked for raw attachment.

Detailed API and threat model: `Docs/GUEST_TOOLS_V2_SPEC.md`.
