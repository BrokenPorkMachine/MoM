# APFS Physical-Store Topology Proof (v0.14.0)

## Purpose and security posture

A **read-only diagnostic**, not a disk opening authorization. The daemon derives a
snapshot from `diskutil list -plist`, `diskutil apfs list -plist`, per-device
`diskutil info -plist`, and `diskutil info -plist /`; its Disk Arbitration probe
checks `DADiskIsClaimed`. The caller supplies only a strict whole-disk BSD name.
Neither the user nor a client process supplies trusted mount flags, media size,
APFS graph records, or an expected host root identity.

The pure analyzer (`Core/PhysicalDiskTopologyProof.swift`) is compiled into
both app and daemon. The daemon-only evidence collector is
`Privileged/VolumeBootRawDiskDaemon/PhysicalDiskTopologyProbe.swift`.

## Identity graph

```
external whole disk disk9
  +-- disk9s1 (EFI)
  +-- disk9s2 (APFS physical store)
       \--> synthesized container disk12
              +-- disk12s1 (System)
              +-- disk12s2 (Data)
```

The analyzer joins physical store identifiers to descendant partition records,
then includes all synthesized APFS volumes in mount checks. It also resolves
APFS-backed host-root snapshots such as `disk12s1s1` to `disk12s1`, refusing
any target that contains the host root or spans another physical whole disk.

## Fail-closed conditions

- Target not a strict whole-disk BSD name, absent or duplicated
- Internal/virtual/non-external disk or missing capacity
- Missing complete disk list or APFS container inventory
- Incomplete/malformed partition tree, physical store, or volume identifier
- APFS Fusion/multi-store container crossing the selected whole disk
- Mount state missing or mounted on *any* target partition or APFS volume
- Root filesystem backing device unknown or on the target disk
- Disk Arbitration reports an existing claim, or claim state is unknown

All APFS devices are additionally tagged **inspection only** regardless of
metadata confidence. A `candidateUnclaimed` result, if ever emitted for a
non-APFS disk, only means metadata observations are coherent. It does not
represent an acquired OS-level claim, an immutable physical-device identity,
or permission to pass through a block device.

## Known limits

- Read-only metadata can race an automount or hotplug after the scan. A real
  `DADiskClaim` *acquisition* plus lease ownership and post-claim revalidation
  is needed before extending grants to APFS/macOS clones.
- Disk Arbitration is cooperative coordination; it is not an IOMMU or kernel
  physical I/O lock. It does not prevent unrelated privileged raw I/O.
- APFS volume-group completeness, FileVault unlock state, Fusion devices and
  macOS boot policy are NOT verified by this component.
- Apple's virtual Mac boot loader still does not promise direct boot from
  an existing physical macOS installation.

## Validation

`./Scripts/test-topology-proof.sh` exercises fixture-based parsing of
physical stores, target isolation, synthesized mount status, host root snapshots,
missing metadata and JSON stability. macOS fixture comparison and a live
non-destructive test on an expendable clone are still required.
