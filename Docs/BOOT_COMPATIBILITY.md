# VolumeBoot — BootCompatibility

Specification v0.1.0 · 2026-10-07

## Verdicts
`managedSupported`, `experimentalCandidate`, `blockedBySafety`, `incompatible`, `unknown`. v0.1 only emits conservative `inspectionOnly` / `blocked` placeholders.

## Evidence graph
Host architecture -> guest architecture -> host framework capability -> installed macOS version -> supported virtual hardware -> auxiliary storage provenance -> physical disk access policy -> result.

## Non-goals
Existing physical Mac boot is never inferred from metadata. Creating arbitrary auxiliary storage is not a replacement for Apple's installer. No unsupported boot-policy bypass or system volume patching.

## Proof levels
L0 discovered, L1 recognized macOS candidate, L2 virtual hardware preflight passed, L3 disposable clone reached setup/desktop, L4 repeatable clean reboot and data integrity. Shipping support requires L4 across an explicit version matrix.

## Tests
Error reason ordering, UNKNOWN classifications, unsupported CPU, host active disk, mismatched metadata, orphaned auxiliary storage, FileVault lock and disk identity drift.


## Cross-cutting rules
- No writes to host-mounted storage from a guest.
- Do not confuse block-device attachment with boot compatibility.
- Treat disk identity and platform configuration as untrusted until independently verified.
- Each API must expose typed errors, useful diagnostics and deterministic test seams.
- Experimental features remain disabled in production builds until their release gates pass.

## Status in v0.1.0 scaffold
This is a specification, not a claim of implemented production functionality. The implementation status appears in `IMPLEMENTATION_MATRIX.md`.
