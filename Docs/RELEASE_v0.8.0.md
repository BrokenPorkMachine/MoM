# VolumeBoot v0.8.0 — XPC Transport and Safety Gate

## Implemented
- Application-scoped XPC service accepts diagnostic-only requests with explicit protocol methods.
- XPC client wrapper with interruption/invalidation error handling, surfaced in UI.
- Device name validation at the service boundary.
- Read-only advisory physical disk preflight retained.
- Physical lease issuance explicitly disabled; no device descriptors transferred.

## Blocking issues before *operational* physical passthrough
1. Implement a launchd/SMAppService privileged helper with correct signing and deployment.
2. Verify the caller through the connection audit token and enforce designated signing requirements, not a PID-only or bundle-ID check.
3. Re-resolve disk identity immediately before open using IOKit/DiskArbitration, rejecting disk-number reuse.
4. Reject host-root backing stores, mounted descendants, overlapping APFS containers, ambiguous topology, and internal devices.
5. Open via O_RDONLY with O_CLOEXEC and verify the returned FD; implement authenticated NSXPC file-handle transfer.
6. Track a per-VM exclusive read lease, revoke on disconnect, cancellation and VM teardown.
7. Exercise all invariants on disposable storage on the intended macOS host.

**This is not a functioning privileged disk broker.** The current XPC service is intentionally unprivileged and cannot safely issue handles. No direct physical boot support is claimed.

## Build validation
Linux Swift parser, plist checks, ZIP integrity, and Xcode source reference checks can run in CI. Xcode compilation, codesign, launchd registration and runtime validation require macOS.
