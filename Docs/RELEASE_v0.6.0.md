# v0.6.0 — Physical attachment foundation

- Added `PhysicalDiskIdentity`, read-only disk lease request and typed errors.
- Added transferred FD access mode validation and `VZDiskBlockDeviceStorageDeviceAttachment` read-only device creation.
- Added optional **secondary** physical disk attachment in managed VM configuration.
- Added fail-closed broker protocol and disabled implementation. The privileged broker and GUI activation are **not implemented**.
- Disk writes and direct boot from existing macOS installations are **not supported**.

## Verification

Swift syntax parsing and Xcode project source registration inspected in non-macOS environment. A real Xcode build, runtime attach, and privilege isolation test remain mandatory before shipping.
