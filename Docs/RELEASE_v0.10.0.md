# VolumeBoot v0.10.0 — Broker Policy Boundary

## Added
- Pure `BrokerAuthorizationPolicy` used by diagnostic XPC and test harness.
- Strict whole-disk identifier validation; XPC preflight rejects partitions, paths and malformed input.
- Explicit read-only and writable grant denials (fail closed).
- Regression tests for request grammar and denial of raw-disk operations.

## Not yet shipped
This is **not** an operational privileged helper. The embedded XPC service is unprivileged; no raw file descriptors or hardware passthrough are provided.

## Required before enabling read-only physical disks
1. Design a signed privileged helper installation with `SMAppService` suitable for macOS 27.
2. Verify caller identity using the connecting process audit token and code-signing requirements, not only a string or PID.
3. Use DiskArbitration/IOKit to bind requests to persistent media identity and to check the complete APFS/partition graph.
4. Safely open the raw *whole disk* `O_RDONLY`, recheck identity post-open, return a restricted descriptor over authenticated XPC.
5. Maintain per-connection device leases and revoke on connection loss, disappearance and VM shutdown.
6. Run mount-conflict, hot-unplug, sleep, stale-BSD-identifier and adversarial tests against disposable devices on the target Mac.
7. Perform end-to-end signed Xcode build and installation tests before enabling GUI attachment.

## Validation
Use `Scripts/test-broker-policy.sh`, `Scripts/test-safety.sh`, and `Scripts/verify.sh` on macOS. Linux Swift syntax checks are not macOS SDK build verification.

## Xcode project caveat
The checked-in historical `.xcodeproj` is application-only and does **not** have the embedded XPC target (despite the project's `project.yml` specification). On macOS, run `Scripts/generate-xcodeproj.sh` to regenerate from `project.yml` before building the broker target. This release updates the checked-in application source references, but cannot validate XcodeGen output on Linux.
