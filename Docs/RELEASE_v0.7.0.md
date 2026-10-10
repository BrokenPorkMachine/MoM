# VolumeBoot 0.7.0 — Safe Disk Broker Boundary

## Implemented
- Read-only physical disk preflight with strict BSD identifier validation.
- UI status for selected device, including host mount/transport warnings.
- Separate XPC-service source and XcodeGen target, with a deny-all listener.
- Existing `ReadOnlyPhysicalDiskLease` remains the only VM-side file descriptor adapter.
- Existing managed VM and APFS inventory remain present.

## Important limitations
This release **does not** ship a usable privileged broker or transferable file descriptor. An embedded application XPC service is **not root privileged** merely because it is an XPC service. The service is intentionally deny-all. Physical disk passthrough is not yet enabled.

## Critical next engineering work
1. Select SMAppService system daemon or supported privileged-helper installation approach, with user-approved authorization and hardened signing.
2. Authenticate client via security audit token and verify the expected designated code-signing requirement; do not rely solely on PID or bundle ID.
3. Validate parent/descendant DiskArbitration/IOMedia identity and complete APFS boot-system ownership graph *inside* the privileged process.
4. Enforce read-only `open` and revalidate descriptor with `fstat`, `fcntl` and IOKit identity, checking for device reuse/races.
5. Implement XPC file descriptor transport and lease lifetime tied to connection, invalidation and shutdown.
6. Test denial, disconnection, mount races and hot-unplug on expendable media, then enable the UI attach action.
7. Provide a repeatable macOS 27 Xcode build and runtime validation log.

No existing-installation boot support is claimed.
