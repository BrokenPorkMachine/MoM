# Read-only disk descriptor grant — v0.13.0

## Threat model and scope

The app runs unprivileged. A root daemon is an extremely sensitive boundary.
Only a caller signed with the matching Apple Team ID AND exact app bundle ID
can connect to the privileged listener. The app also verifies daemon Team ID
and code identifier before trusting it. The daemon rejects unsigned/self-
reported identity, arbitrary file paths, partition identifiers, writable
access, and unknown disk metadata.

## Protocol version 2

`healthReport(withReply:)` advertises the experimental feature.
`requestReadOnlyDisk(_:withReply:)` accepts ONLY a whole-disk BSD identifier
(e.g. `disk9`) and returns `(FileHandle?, JSONGrantMetadata, denialReason)`.
`releaseReadOnlyDisk(_:withReply:)` accepts the connection's lease UUID.
The XPC connection stays alive while the VM uses the block device.

Data travels as an NSXPC `FileHandle`, not a numeric FD (FD numbers are only
valid within each process). An Apple developer example confirms FD handles are
transportable through NSXPC. The unprivileged app checks the received FD's
`O_RDONLY` status, duplicates the descriptor, and builds a read-only
`VZDiskBlockDeviceStorageDeviceAttachment`. The transferred disk is SECONDARY
storage; the guest boots from its managed `disk.img`.

## Hard denial conditions

- Invalid, changed, or partition BSD name
- Missing or inconsistent diskutil/IOKit identity
- Internal, virtual, or unknown transport/location
- Mounted, partitioned, APFS, other filesystems, or unknown topology
- No reported physical disk size or IOKit registry identity
- Not running as a signed, approved root daemon
- Another connection already reserving the same disk
- Untrusted code signature or broker timeout
- Descriptor is not a character device, is not read-only, or changes identity

The daemon opens `/dev/rdiskN` with `O_RDONLY | O_CLOEXEC | O_NOFOLLOW |
O_NONBLOCK`, verifies descriptor and path identity, and re-probes metadata.
It never calls `diskutil` with mutating subcommands, never unmounts media,
and never writes a byte to a disk.

## Lease lifetime

A single authenticated XPC connection may hold one lease. A process-wide
reservation map refuses the same disk to other connections. Connection
invalidation, interruption, explicit release, or process exit closes the
daemon-side descriptor and removes its reservation. The VM-side handle must
be closed after the VM stops. Closing one copy does NOT forcibly revoke other
open descriptor copies. Therefore an already-running VM must be stopped before
releasing its lease.

## Required macOS acceptance tests (NOT YET RUN)

1. Confirm app and daemon sign with matching Team IDs and exact identifiers.
2. Approve daemon via SMAppService. Confirm mutual signature rejection tests.
3. Attach an expendable completely empty external disk, verify it is denied
   when mounted, internal, partitioned, virtual, or APFS.
4. Confirm only a read-only FD reaches an unprivileged guest as SECONDARY disk.
5. Confirm a second client cannot lease the same media.
6. Force-kill client and daemon separately, confirm no stale reservation.
7. Unplug/replug under read load, confirm fail-closed cleanup.
8. Independently compare raw device bytes before and after boot and detach.
9. Verify host sleep/reboot behavior and service signing on a clean macOS install.

## What this release intentionally does NOT implement

- Exclusive Disk Arbitration claim / prevention of future host mounting.
- Full recursive APFS/host-root ownership validation.
- Read-write physical disks or hardware NVMe/PCIe passthrough.
- Existing macOS physical installation boot.
- Automatic descriptor revocation after client copy has been transferred.
- Compatibility guarantee for a specific macOS 27 beta/SDK build.

Do not expand eligibility until Disk Arbitration claiming and a full APFS
physical-store graph validator are present and tested on real hardware.
