# VM provisioning specification — v0.4.0

## Objective
Create and install a supported Apple Silicon macOS virtual machine from a locally supplied Apple IPSW file using public Virtualization.framework APIs.

## Workflow
1. User selects a local `.ipsw` restore image and a **new, absent** destination folder on a selected storage volume.
2. `VZMacOSRestoreImage.image(from:)` inspects image, `mostFeaturefulSupportedConfiguration` provides compatible virtual Mac model and minimum resources.
3. Validate requested CPUs and memory against both Apple limits and image requirements.
4. Create a VM folder exclusively (existing folder must never be modified).
5. Persist `hardware-model.bin`, `machine-id.bin`, and `auxiliary-storage` for the VM identity.
6. Create `disk.img` as a sparse raw virtual disk, at least 64 GiB.
7. Construct a `VZMacPlatformConfiguration`, macOS boot loader, VirtIO storage, display, input, entropy and NAT network.
8. Validate the VM configuration before installation.
9. Install with `VZMacOSInstaller`, preserving partial data on failure.
10. Write `manifest.json` only on successful installation; permit subsequent boot using persistent VM metadata.

## Security rules
- Physical disks are not opened or attached.
- Destination folder must not exist; no overwrite or implicit deletion.
- Installation writes only inside the user-selected destination folder.
- Installer errors are surfaced; partial data retained for diagnosis.
- Do not ask for or log FileVault passwords, recovery keys, or Apple IDs.
- Root privileges are never required for this phase.

## Known gaps
- No restore-image downloader, progress bar, resume, cancellable installer, or security-scoped bookmark persistence.
- No on-device Xcode compile/runtime verification was possible in the development container.
- Sparse disk creation requires filesystem free-space monitoring during installation.
- `manifest.json` is only a completion marker; VM startup still uses existing hardware metadata.
- No automatic cleanup of unsuccessful folders (deliberately conservative).

## Tests to run on macOS
- Valid signed Apple Silicon restore image successfully installs; reaches setup assistant.
- Persisted VM reboots with same machine ID and auxiliary storage.
- Existing destination folder rejected without byte change.
- Bad/missing IPSW and incompatible image rejected.
- Insufficient CPUs/RAM rejected.
- Installer error retains diagnostic artifacts without touching outside the VM folder.
- Physical volume inventory and inspection continue to work unchanged.


## v0.5.0 additions
The UI samples `VZMacOSInstaller.progress` during installation. Manifest state is persisted before provisioning and after success or failure. Interrupted installations remain in `provisioning` state and cannot be booted without future verified recovery tooling.
