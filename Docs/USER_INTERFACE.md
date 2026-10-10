# VolumeBoot — UI and Accessibility

Specification v0.1.0 · 2026-10-07

## Screens
Dashboard, storage explorer, APFS inspection, compatibility report, VM library, create VM wizard, VM console, physical device leases, experiments, diagnostics and settings.

## UX policy
Actions are named `Inspect`, `Clone`, `Attach read-only`, `Install macOS` and `Boot managed VM` to avoid implying interchangeability. Never offer a destructive default. Show explicit unsupported/experimental labels.

## Accessibility
Keyboard navigation, VoiceOver descriptions, high-contrast status, scalable typography, progress feedback and no color-only state. Surface denial causes inline and copyable.

## Initial scaffold
Functional SwiftUI browser built on safe `diskutil` inventory and a minimal existing VM start action. Full console and installer are pending.


## Cross-cutting rules
- No writes to host-mounted storage from a guest.
- Do not confuse block-device attachment with boot compatibility.
- Treat disk identity and platform configuration as untrusted until independently verified.
- Each API must expose typed errors, useful diagnostics and deterministic test seams.
- Experimental features remain disabled in production builds until their release gates pass.

## Status in v0.1.0 scaffold
This is a specification, not a claim of implemented production functionality. The implementation status appears in `IMPLEMENTATION_MATRIX.md`.
