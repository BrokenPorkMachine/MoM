# VolumeBoot 0.13.0 — Physical descriptor grant laboratory

This release extends v0.12.0; it does not replace the established VM, inventory,
APFS, or compatibility components.

## New implementation

- `Core/ReadOnlyGrantPolicy.swift`: testable, fail-closed strict-media policy;
  process-local global disk reservation map.
- `Privileged/VolumeBootRawDiskDaemon/TrustedDiskProbe.swift`: read-only
  `diskutil` topology check plus DiskArbitration/IOKit registry identifier,
  `O_RDONLY` open and post-open TOCTOU revalidation.
- Signed daemon: versioned request/release of NSXPC FileHandles, per-connection
  session, duplicate-grant denial, automatic server-side cleanup.
- `PrivilegedBrokerClient`: versioned grant decoding, timeout/interrupt
  completion, read-only FD validation and retention of authenticated XPC
  connection while VM uses storage.
- UI: explicit secondary-disk test toggle, never changes VM boot disk.
- Integrated VM path: optional `ReadOnlyPhysicalDiskLease` is held during
  guest runtime and released after successful stop.
- Tests: positive and deny-case policy tests, reservation ownership checks,
  grant metadata protocol tests. Checked-in `.xcodeproj` regenerated.

## Non-negotiable restrictions

**Only a disposable, empty, unmounted, unpartitioned, external physical disk is
eligible.** All APFS / macOS installation disks remain denied; read-write
access is not provided. No disk auto-unmount and no destructive operations.
This is a laboratory test path and not production-ready physical passthrough.

## Validation boundaries

Source parser / Linux-runnable pure-contract tests / plist & ZIP structure can
run in this build environment. Real macOS full compile, ServiceManagement
registration, root signing, actual NSXPC transport, and guest read tests were
NOT performed and must not be inferred from syntax passes.

## Mac build validation

```sh
./Scripts/verify.sh
./Scripts/check-daemon-bundle.sh /path/to/VolumeBoot.app
```

With a completely expendable, confirmed blank external disk, verify that the
whole-disk BSD identifier and DiskArbitration topology are complete. Launch a
managed VM normally before testing the optional secondary-disk toggle. Never
use your internal drive, boot drive, or any disk containing valuable data.

## Next engineering gate

1. Xcode compile fixes based on macOS 27 SDK type checking and strict signing.
2. Live root-helper+XPC integration tests, real read-only descriptor transfer.
3. OS-level Disk Arbitration claims and mount-event observation.
4. Recursive APFS dependency map for safe READ-ONLY access to nonblank media.
5. Controlled experiments on disposable clones for macOS boot compatibility.
