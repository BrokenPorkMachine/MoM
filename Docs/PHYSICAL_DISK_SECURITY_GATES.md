# Physical disk authorization gates — normative

1. Receive caller's audit token from trusted XPC transport; verify designated signing requirement against the *connected process*, reject absence/mismatch.
2. Obtain explicit user approval for a single physical whole disk and read-only mode.
3. Resolve a stable media identity; require exact match to preflight-selected device.
4. Resolve ALL descendant partition mount states and APFS physical store relationships. Fail closed if any information is unavailable.
5. Reject internal disks, boot/recovery/root storage, synthesized devices, any mounted descendant, any APFS physical store not exhaustively checked.
6. Open only `/dev/rdiskN` with O_RDONLY | O_CLOEXEC | O_NOFOLLOW and validate fstat + fcntl on the opened handle; compare identity again after open.
7. Transfer only an appropriate FileHandle over authenticated XPC; bind the lease to a single live connection and VM session.
8. Prevent concurrent grants for the same stable identity. Reject stale session requests.
9. On disconnect, revoke leases, close helper-owned FDs, and stop future grants until device state is re-established. VM-owned duplicate handles may persist and need coordinated VM teardown.
10. Never provide a permissive fallback to running the GUI as root, chmod on /dev nodes, or calling arbitrary shell commands.

## Required negative tests
Spoofed clients; reused disk number; device removal; mounted child partition; synthesized APFS disk; boot physical store; stale identity; unrecognized transport; descriptor unexpectedly writable; simultaneous lease; broker restart; partial topology response; stale code signature requirement.
