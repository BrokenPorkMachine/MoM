# Read-only physical disk backend — v0.6.0

## Actual scope

`ReadOnlyPhysicalDiskLease` accepts **only an already authorized file descriptor** and duplicates it, verifies it is opened `O_RDONLY`, and creates `VZDiskBlockDeviceStorageDeviceAttachment(readOnly: true)`. `VMRuntimeService.startExistingVM` can optionally add this as a **secondary** disk to a managed guest. The managed guest disk remains the boot device. The VM retains the lease for the run.

**The privileged broker is not installed or usable.** `DisabledPhysicalDiskLeaseBroker` always rejects access. No raw disk node is opened by the app. Consequently physical disks cannot yet be selected from the UI or passed through on a typical Mac. This is an implementation milestone, *not* a usable physical passthrough release.

## Broker completion tasks (release blocking)

1. Add a signed launchd ServiceManagement privileged helper target and authenticated XPC listener. Never trust client-provided paths or raw BSD identifiers without checking device identities against IOKit/DiskArbitration.
2. Pass open descriptors using an XPC-capable transport with actual FD transfer (for example native XPC descriptors or a Unix domain socket with SCM_RIGHTS); do not serialize descriptor integers.
3. Walk APFS container physical stores, partitions and mounts before granting device leases. Deny active host system disks and entire overlapping physical store topology.
4. Build atomic reservations and device generations, handle detach, hot-unplug, sleep, client crash, and helper restart. Deny concurrent guest writable activity.
5. Enforce `O_RDONLY` at open time, then separately set guest `readOnly: true`. Supply the VM with a stable duplicate of the transferred FD; no path reopen.
6. Record audit events and test malicious caller, forged UUID, BSD-number reuse, racing mount changes, and hot unplug.
7. Validate entitlements/signature/team IDs and successful lifecycle on a Mac before enabling the GUI.

## Safety invariants

- Never provide an automatic `open("/dev/...")` fallback.
- No physical-disk writing in v0.6.x.
- Physical attachment does not imply physical macOS installations can boot.
- No use of `VZNVMExpressControllerDeviceConfiguration` as physical NVMe passthrough.
- A read-only guest could still observe an inconsistent snapshot when the host writes; test on unmounted, disposable media first.

## API contract

`PhysicalDiskIdentity`: BSD name, backing disk name, UUID, size, internal/whole-disk flags. These fields are hints until broker revalidation.

`ReadOnlyDiskLeaseRequest`: expected identity + random session ID.

`PhysicalDiskLeaseBroker.authorizeReadOnly`: eventually returns an authenticated read-only descriptor lease; currently fail-closed.

`VMRuntimeService.startExistingVM(..., readOnlyDisk:)`: attaches the lease as additional VirtIO storage for that VM run only.
