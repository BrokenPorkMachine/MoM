# VolumeBoot — DeviceInventory

Specification v0.1.0 · 2026-10-07

## Contract
`listDevices() async throws -> [StorageDevice]` returns a snapshot. Future implementation uses DiskArbitration callbacks and IOKit topology; initial implementation invokes read-only `diskutil list -plist` and `diskutil info -plist`.

## Identity
Never persist BSD disk numbers as stable identifiers. Build identity from IOMedia UUID, whole-media identity, transport path, and APFS UUID evidence; handle cloned UUIDs. Preserve source and confidence for each field.

## Requirements
Enumerate whole disks, physical partitions, APFS synthesized containers, mounts, device size, block size, bus, internal/removable, writable state, and timestamp. Debounce device arrival/removal. Never treat a synthesized container as an exclusive physical device.

## Failure handling
Partial discovery is a typed state: continue listing good devices with errors attached. Time bound subprocess invocations; guard against hung media, malformed plist and changing identifiers.

## Tests
Synthetic plist fixtures, disconnect during enumeration, external SSD with multiple APFS containers, multi-store container, FileVault locked disk, zero-byte media, cloned UUIDs, reordering and mount changes.

## Acceptance
No disk mutation; stable topology and nonblocking UI; event-driven inventory with documented field provenance.


## Cross-cutting rules
- No writes to host-mounted storage from a guest.
- Do not confuse block-device attachment with boot compatibility.
- Treat disk identity and platform configuration as untrusted until independently verified.
- Each API must expose typed errors, useful diagnostics and deterministic test seams.
- Experimental features remain disabled in production builds until their release gates pass.

## Status in v0.1.0 scaffold
This is a specification, not a claim of implemented production functionality. The implementation status appears in `IMPLEMENTATION_MATRIX.md`.
