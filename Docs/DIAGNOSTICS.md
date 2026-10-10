# VolumeBoot — DiagnosticsKit

Specification v0.1.0 · 2026-10-07

## Requirements
Capture timestamped events with stable session IDs, module names, event categories, result codes, elapsed durations and linkable preflight evidence.

## Privacy
Default redaction of serials, ECIDs, usernames, personal paths, FileVault material and raw APFS keys. Never log guest memory or raw disk content. Explicit opt-in for sensitive exports.

## Failure classification
Discovery, APFS parsing, code signing, authorization, lease, virtual platform configuration, restore-image install, boot, guest I/O, external device removal.

## Diagnostics bundle
JSON manifest, JSONL events, environment manifest, VM config (sans secrets), policy decisions and user-initiated log export. Keep data bounded with retention limits.

## Performance
`os_signpost` for scan duration, VM startup, attachment and shutdown. Sampling off by default when idle.


## Cross-cutting rules
- No writes to host-mounted storage from a guest.
- Do not confuse block-device attachment with boot compatibility.
- Treat disk identity and platform configuration as untrusted until independently verified.
- Each API must expose typed errors, useful diagnostics and deterministic test seams.
- Experimental features remain disabled in production builds until their release gates pass.

## Status in v0.1.0 scaffold
This is a specification, not a claim of implemented production functionality. The implementation status appears in `IMPLEMENTATION_MATRIX.md`.
