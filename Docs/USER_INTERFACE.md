# VolumeBoot — UI and Accessibility

Specification v0.1.0 · 2026-10-07

## Screens
Dashboard, storage explorer, APFS inspection, compatibility report, VM library, create VM wizard, VM console, physical device leases, experiments, diagnostics and settings.

## UX policy
Actions are named `Inspect`, `Clone`, `Attach read-only`, `Install macOS` and `Boot managed VM` to avoid implying interchangeability. Never offer a destructive default. Show explicit unsupported/experimental labels.

## Accessibility
Keyboard navigation, VoiceOver descriptions, high-contrast status, scalable typography, progress feedback and no color-only state. Surface denial causes inline and copyable.

## Current workspace
The native sidebar opens Virtual machines by default. Create/Open actions live in the toolbar and app menu. The VM workspace separates Overview, Console, Hardware, Disks, and Network, with scrollable settings and a console that fills the detail area. Recent workspaces persist across launches.

Creation groups operating system, destination, media, and resources. Existing workspaces show status, storage, compute/network summaries, validation, and installation completion when applicable. Unsaved settings block startup until saved or reloaded. Failed profile loads preserve selection. Opening another VM prompts before discarding unsaved changes.

Disk creation and growth use focused sheets. Destructive actions require confirmation. Shut down requests guest cooperation; Force stop and quitting an active VM explicitly warn about unsaved guest work. Windows uses its own QEMU display and clearly shows its fixed capture shortcut.

Use `Scripts/preview-ui.sh` to render light, dark, compact, disk, hardware, and network layouts. See [audit results and validation limits](AUDIT_AND_POLISH.md).


## Cross-cutting rules
- No writes to host-mounted storage from a guest.
- Do not confuse block-device attachment with boot compatibility.
- Treat disk identity and platform configuration as untrusted until independently verified.
- Each API must expose typed errors, useful diagnostics and deterministic test seams.
- Experimental features remain disabled in production builds until their release gates pass.

## Status in v0.1.0 scaffold
This is a specification, not a claim of implemented production functionality. The implementation status appears in `IMPLEMENTATION_MATRIX.md`.
