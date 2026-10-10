# VolumeBoot — Existing macOS Direct Boot Research

Specification v0.1.0 · 2026-10-07

## Method
Maintain a known-good `VZMacOSInstaller` VM. Run all experiments on a disposable copy of storage, beginning read-only. Preserve version, model identifier and all failures. Use external device only after the regular VM is demonstrably stable.

## Stages
E01 standard RAW-image managed VM; E02 RAW image stored on external SSD; E03 broker-mediated read-only physical block attachment as secondary disk; E04 dedicated disk managed install; E05 clone of an existing physical Mac installation; E06 USB passthrough; E07 comparison of boot environments.

## Observations
Capture host/guest versions, disk topology, auxiliary storage provenance, exposed virtual device model, guest disk recognition, boot progress and errors, shutdown result, byte-level source integrity.

## Stop criteria
Any host mounted writable filesystem collision, device identity drift, access loss, unexpected write, boot-policy mutation request, unknown lock/encryption state or kernel panic resets to read-only inspection.

## What success means
Existing-install support requires clean start, desktop, shutdown, repeat start and unchanged original source, backed by a compatibility matrix. A guest recognizing the disk is not success.


## Cross-cutting rules
- No writes to host-mounted storage from a guest.
- Do not confuse block-device attachment with boot compatibility.
- Treat disk identity and platform configuration as untrusted until independently verified.
- Each API must expose typed errors, useful diagnostics and deterministic test seams.
- Experimental features remain disabled in production builds until their release gates pass.

## Status in v0.1.0 scaffold
This is a specification, not a claim of implemented production functionality. The implementation status appears in `IMPLEMENTATION_MATRIX.md`.
