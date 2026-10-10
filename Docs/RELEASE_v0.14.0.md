# VolumeBoot v0.14.0 — APFS topology and DA-claim laboratory

## Delivered

- Validated, fixture-testable physical-disk topology analyzer recognizing whole
  disks, child partitions, APFS physical stores, synthesized containers and
  synthesized APFS System/Data volumes.
- Host-root snapshot overlap detection, multi-store/partial-graph denial,
  mounted-descendant checking, and fail-closed unknown handling.
- Signed daemon diagnostic endpoint `readOnlyTopology` producing a structured
  report (broker protocol version 3), with claim-status observation.
- SwiftUI button on the Devices page to inspect selected physical disk topology.
- Standalone macOS-only `DiskClaimLab` exercising `DADiskClaim`/`DADiskUnclaim`
  with explicit consent, restricted to *blank expendable external disks*.
- Test harness, documentation, update to v0.14.0 and refreshed Xcode project.

## Unchanged

Read-only blank external scratch disk grants from v0.13.0 are preserved, subject
to signing and privileges. No new physical disk types are granted to VMs.
Managed macOS VM installation, registry, graphics and APFS installation
recognition are retained.

## Not complete

- No full Xcode/macOS compilation or real Disk Arbitration claim test has
  been performed in the release environment.
- No APFS clone or existing macOS physical disk may be transferred to a VM.
- No automatic unmount, no writable physical disks, no direct boot from a
  physical macOS installation; neither PCIe passthrough nor kernel-level
  exclusive disk ownership is offered.
- Before expanding grants: native macOS live tests, long-lived DA claim
  ownership in daemon, reconnect revocation, post-claim metadata revalidation,
  volume-group verification and filesystem integrity tests are mandatory.

## Verification commands

```
./Scripts/verify-linux.sh
./Scripts/verify.sh             # macOS with Xcode / SDK
./Scripts/build-claim-lab.sh    # macOS, compiler only
```
