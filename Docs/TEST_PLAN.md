# VolumeBoot — Quality and Test Plan

Specification v0.1.0 · 2026-10-07

## Layers
Unit: parsing, identifiers, risk rules, VM registry, model validation. Integration: external disposable media, real boot, broker auth. End-to-end: install, boot, suspend, detach, restart and exported diagnostics.

## Device matrix
Internal host NVMe (inspection only), external USB SSD, external USB HDD, Thunderbolt NVMe, SATA, encrypted/locked APFS, non-APFS volumes, multiple APFS containers.

## Destructive tests
ONLY disposable disks with explicit test labels and validated pre/post SHA-256 sample regions. Abrupt unplug, forced app termination, sleep/wake, device BSD renumber, helper crash, permission changes, disk full.

## Automated gates
Source lint, Swift compile on actual macOS/Xcode, entitlements inspection, fixture tests, VM config validation. A green Linux syntax check is not equivalent to macOS SDK build.

## Release gates
No physical-write path before third-party review of broker and preflight. No 'existing Mac direct boot supported' until repeatable clone tests prove compatibility.


## Cross-cutting rules
- No writes to host-mounted storage from a guest.
- Do not confuse block-device attachment with boot compatibility.
- Treat disk identity and platform configuration as untrusted until independently verified.
- Each API must expose typed errors, useful diagnostics and deterministic test seams.
- Experimental features remain disabled in production builds until their release gates pass.

## Status in v0.1.0 scaffold
This is a specification, not a claim of implemented production functionality. The implementation status appears in `IMPLEMENTATION_MATRIX.md`.

## v0.15.0: Network and guest integration

See `NETWORKING.md` and `GUEST_HOST_TOOLS.md`. NAT is the default; optional bridging requires a suitable entitlement. VirtioFS sharing and the guest data exchange require an explicit opt-in. The file exchange is not a privileged management protocol; no inbound command execution is implemented. Full macOS validation remains outstanding.
