# VolumeBoot v0.15.0 — Network & Guest/Host Integration

Based on v0.14.0; direct boot of existing physical installations remains experimental and **not enabled**.

### New
- Per-VM network profiles in `connectivity.json`: NAT, bridged, disconnected.
- Persistent VM MAC address based on the VM's manifest identifier.
- Physical bridge interface enumeration and optional bridged attachment (entitlement required; **not enabled by default signing**).
- Opt-in VirtioFS shared host workspace, read-only default.
- Opt-in guest exchange share and data-only host/guest companion tools.
- SwiftUI Network & Guest Tools tab for settings, file staging, messages, and heartbeats.
- Swift host CLI and macOS guest CLI, optional guest launch-agent template.
- Regression fixtures for profile validation and message/file exchange.

### Build

```
./Scripts/verify-linux.sh     # portable checks; no Xcode validation
./Scripts/build-host-tool.sh  # macOS
./Scripts/build-guest-agent.sh
open VolumeBoot.xcodeproj
```

### Gates not yet passed
- Full Swift type check against macOS 27 Virtualization.framework and SwiftUI.
- Code signing of bridged entitlement and actual bridge network traffic.
- Guest VirtioFS mount and companion binary execution.
- Signed LaunchDaemon and physical disk passthrough runtime testing.

Physical disk grants remain restricted to disposable **blank** external drives as in v0.14.0, and existing macOS APFS installations are inspection-only.
