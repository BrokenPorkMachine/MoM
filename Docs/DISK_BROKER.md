# VolumeBoot — DiskAccessBroker and XPC

Specification v0.1.0 · 2026-10-07

## Mandatory trust boundary
Privileged helper is NOT included in the scaffold. Initial `DiskBrokerPolicy.allowRequest` returns false for every request. No escalation, disk writing or physical passthrough exists in v0.1.

## Proposed protocol
`enumerateEligible()`, `inspectStableDevice(id)`, `requestReadOnlyLease(id, expectedIdentity)`, `requestExclusiveLease(...)`, `releaseLease(id)`, `getStatus(id)`.

## Authorization
Validate caller's signing requirement and user approval. Enumerate permissible operations in code (never generic `execute` or arbitrary `open(path)`). Reject symbolic links and replaced devices; independently re-resolve stable hardware identifiers. Never trust a client-supplied BSD path.

## Read-only lease
Open read-only FD at broker, use SCM_RIGHTS/XPC passing, retain ref and track VM owner. Pass into `VZDiskBlockDeviceStorageDeviceAttachment(fileHandle:readOnly:synchronizationMode:)`. A guest read-only setting is insufficient if FD permits writes.

## Exclusive writable lease
Not available until whole-media APFS/partition ancestry analysis; unmount confirmation and post-unmount revalidation; full ownership and anti-TOCTOU checks; host root and active APFS backing stores are permanently denied. No simultaneous host/guest FS writes.

## Crash safety
Lease invalidation on VM/XPC death, USB removal, device replacement, sleep/wake revalidation; make ownership journal durable. Device FD closure does not repair writes already issued by a guest.

## Delivery caveat
Apple advises against running the VM as root and recommends a separate privileged file-handle broker; this privilege-escalation approach is not Mac App Store compatible.


## Cross-cutting rules
- No writes to host-mounted storage from a guest.
- Do not confuse block-device attachment with boot compatibility.
- Treat disk identity and platform configuration as untrusted until independently verified.
- Each API must expose typed errors, useful diagnostics and deterministic test seams.
- Experimental features remain disabled in production builds until their release gates pass.

## Status in v0.1.0 scaffold
This is a specification, not a claim of implemented production functionality. The implementation status appears in `IMPLEMENTATION_MATRIX.md`.


## v0.7.0 implementation boundary
`Helpers/VolumeBootDiskBroker` is a **non-privileged, deny-all XPC service prototype**. Do not advertise it as installed/authorized or modify the listener to accept connections before implementing the full checks in RELEASE_v0.7.0.md. Device preflight is advisory and never constitutes authorization.

## v0.8.0 integration status
The XPC transport is diagnostic-only. Authorization is NOT inferred from successfully connecting to the service. No file descriptors, device opens, or privileged file operations are implemented. The app side uses `DiskBrokerClient` solely to show the service's declared capabilities.

## v0.10.0 authorization decision layer
`BrokerAuthorizationPolicy` is a *pure input-validation and permission-denial layer* shared between broker target and unit tests. It is not an authentication implementation and does not grant raw handles. Future trusted helper must verify the peer using OS-provided audit identity and enforce the same fail-closed physical-disk rules after the device is opened.
