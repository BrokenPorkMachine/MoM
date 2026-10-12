# Physical disk attachment security gates

## Release decision

Physical-disk attachment is **excluded from production builds**. The app has no UI or VM-runtime attachment path, the privileged XPC contract has no descriptor request/release methods, and the production daemon target does not include the raw-device opener or grant policy. The daemon may report disk topology for diagnostics only. This is the required fail-closed policy until every gate below is implemented and qualified.

APFS volumes and physical stores, the host boot/root/recovery devices, existing macOS installations, mounted disks, and any device whose complete ancestry cannot be established remain ineligible. Metadata preflight is advisory and never authorizes access. Do not re-enable attachment based on a synthetic backend test or source-level review.

## Required implementation gates before reconsideration

1. **Authenticated request:** receive the caller audit token from trusted XPC transport and verify the exact designated signing requirement against the connected process. Reject missing, stale, mismatched, or self-reported identity.
2. **Explicit consent:** obtain user approval for one stable physical whole-disk identity and read-only use. Revalidate consent against that identity immediately before acquisition.
3. **Stable identity binding:** bind media UUID/serial and IORegistry identity, BSD name, size, and device class. Treat BSD names as transient locators only. Reject replacement media, identity changes, and incomplete or conflicting identity data.
4. **Complete topology:** enumerate all descendants, mount states, synthesized devices, APFS containers and every physical store, plus host boot/root/recovery relationships. Fail closed on partial, stale, or unavailable information.
5. **Eligibility policy:** deny internal, boot/recovery/root, synthesized, mounted, partitioned, APFS-backed, existing macOS, and unknown devices. Any future policy expansion requires a separately reviewed and versioned decision; this document does not approve APFS or existing macOS disks.
6. **Exclusive Disk Arbitration claim:** acquire and retain an exclusive `DADiskClaim` for the physical device before opening it. Handle claim callbacks, competing claims, mount/unmount events, claim loss, device removal, timeouts, daemon restart, and failed `DADiskUnclaim`. No descriptor may be issued unless the claim is active and identity/topology are freshly revalidated.
7. **Safe descriptor opening:** open only the approved raw device with `O_RDONLY | O_CLOEXEC | O_NOFOLLOW`; validate `fstat`/`fcntl`, character-device type, and identity on the opened descriptor, then compare the stable identity again. Never accept arbitrary paths or caller-supplied file descriptors.
8. **Lease lifecycle:** transfer a descriptor only over authenticated XPC, bind one lease to one connection and VM session, prevent concurrent leases for the same media identity, and define ordering between VM stop, descriptor closure, and claim release. Document that closing a daemon FD cannot revoke already duplicated copies.
9. **Hotplug and disconnect cleanup:** on client disconnect, VM exit, device change/removal, claim loss, daemon interruption, or restart, stop further I/O, terminate/stop the owning VM as needed, close all owned descriptors, release the claim, and clear reservations. Replug must require fresh topology and user approval.
10. **Signed deployment:** validate the signed app, daemon, launchd registration, entitlements, mutual code requirements, update and uninstall behavior on a clean supported macOS installation. Never fall back to running the GUI as root, changing `/dev` permissions, or invoking mutating shell commands.
11. **Hardware qualification:** run the complete lifecycle on signed release builds and expendable, identified hardware across every supported host macOS release and representative device/controller combinations. Preserve logs and before/after media hashes; demonstrate no writes and safe behavior under injected failure.

## Required negative and failure tests

Spoofed or unsigned clients; mismatched signing identity; reused BSD number with replacement media; changed serial/IORegistry identity; partial topology; mounted descendant; synthesized APFS disk; APFS physical store; boot/root/recovery relationship; internal disk; concurrent claim and concurrent lease; claim callback failure; mount attempt during lease; claim loss; descriptor unexpectedly writable or wrong device; unplug during active I/O; client/VM/daemon crash; disconnect and restart cleanup; failed unclaim; stale user consent; and stale daemon signature requirement.

## Current evidence

The production build intentionally has no grant API or raw-device open path. Read-only topology diagnostics do not establish attachment safety. The repository has not completed exclusive Disk Arbitration claim handling, lease/revocation semantics, or signed hardware lifecycle validation. Therefore no physical device is approved for attachment, and the capability must remain excluded from production targets.
