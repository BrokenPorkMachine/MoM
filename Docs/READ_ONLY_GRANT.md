# Read-only disk grant experiment — disabled, non-production

This document records the earlier v0.13.0 design only. It is **not an operational procedure** and its protocol descriptions do not match the production build. The production app has no physical attachment workflow or VM descriptor path; the production XPC contract has no grant request/release operations; and the daemon target excludes the raw-device opener and grant policy. Do not use old grant instructions or treat preflight/topology diagnostics as authorization.

The production policy remains fail closed. APFS and its physical stores, existing macOS disks, mounted media, host boot/root/recovery storage, internal or synthesized devices, and devices with incomplete identity/topology remain ineligible.

## Historical v0.13.0 design

The experiment proposed mutual code-signature checks, a read-only `/dev/rdiskN` descriptor, and a lease associated with an authenticated XPC connection. The design recognized that file descriptors can be duplicated across processes and that closing the daemon's copy cannot revoke a VM's copy. Those ideas were not sufficient for safe release: the daemon did not retain an exclusive Disk Arbitration claim, stable identity and device-change handling were incomplete, and signed hardware lifecycle qualification was not performed.

Any future implementation must satisfy the complete gates in [PHYSICAL_DISK_SECURITY_GATES.md](PHYSICAL_DISK_SECURITY_GATES.md), including exclusive claim acquisition and release, complete APFS/host-root topology checks, hotplug and disconnect cleanup, signed deployment, and hardware validation. Passing a source test, synthetic-media test, or topology query alone cannot authorize production attachment.
