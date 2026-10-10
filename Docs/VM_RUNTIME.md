# VolumeBoot — VirtualMachineKit

Specification v0.1.0 · 2026-10-07

## State model
Unconfigured -> validating -> ready -> starting -> running -> stopping -> stopped, with failed/interrupted branches. Serialize all state changes on the main actor or dedicated actor; do not allow duplicate starts.

## Boot configuration
Use `VZMacOSBootLoader`, `VZMacPlatformConfiguration` and persisted `VZMacHardwareModel`, `VZMacMachineIdentifier`, `VZMacAuxiliaryStorage`. Use supported restore-image requirements when provisioning. Include CPU, RAM, disk, graphics, keyboard, pointer, entropy and network as needed; call `validate()` before starting.

## Data layout
Managed VM bundle: `hardware-model.bin`, `machine-id.bin`, `auxiliary-storage`, `disk.img`, `vm.json` and `logs/`. Only v0.1 manually opens already-provisioned files. It does not install macOS or create a console view yet.

## Lifecycle
Handle delegate stop/error callbacks, maintain a reference to running VM, block simultaneous access to the same writable image, flush metadata and report errors. Don't assume an app crash causes a clean guest shutdown.

## Tests
Missing hardware metadata, corrupt identity, unsupported hardware, invalid RAM, duplicate start, cancellation, failure before launch, shutdown, crash while booting, VM image attached twice.

## Acceptance
Provision from an IPSW using `VZMacOSRestoreImage` and `VZMacOSInstaller`, boot, present guest console and cleanly re-boot with preserved identity. Those are future stages.


## Cross-cutting rules
- No writes to host-mounted storage from a guest.
- Do not confuse block-device attachment with boot compatibility.
- Treat disk identity and platform configuration as untrusted until independently verified.
- Each API must expose typed errors, useful diagnostics and deterministic test seams.
- Experimental features remain disabled in production builds until their release gates pass.

## Status in v0.1.0 scaffold
This is a specification, not a claim of implemented production functionality. The implementation status appears in `IMPLEMENTATION_MATRIX.md`.
