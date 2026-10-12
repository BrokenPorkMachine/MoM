# MacOnMac — Virtual workspace manager

**Current support boundary:** this is an evaluation preview; no complete guest configuration is yet production-qualified. Physical disk attachment is disabled, and host disk inventory/topology are inspection-only. See the [release support matrix](Docs/SUPPORT_MATRIX.md) for host, guest, backend, feature status, and qualification gates.

The native workspace separates setup, console, hardware, disks, and network, with recent VM persistence, readiness checks, unsaved-change protection, graceful shutdown, and confirmed force stop. See the [correctness/UI audit](Docs/AUDIT_AND_POLISH.md) and run `Scripts/preview-ui.sh` for layout previews.

**Virtual machines** installs and runs macOS from Apple IPSW files, ARM Linux from an AArch64 ISO using Apple Virtualization.framework, and Windows ARM from an ARM64 ISO using QEMU/HVF with persistent UEFI and TPM 2.0. Windows requires QEMU 9.2+ and swtpm. See [ARM guest setup](Docs/ARM_GUESTS.md).

Administrators should follow the [managed update and rollback contract](Docs/UPDATE_ROLLBACK.md); application and daemon versions must be deployed together, while VM workspaces remain user data.

See the [current product scope](Docs/PRODUCT_SCOPE.md), [dependency and licensing record](Docs/DEPENDENCIES_AND_LICENSES.md), and [support commitments](Docs/SUPPORT_AND_MAINTENANCE.md) before enterprise deployment.

Use the [current release guide](Docs/RELEASE_GUIDE.md) for installation, administration, troubleshooting, and recovery. Files named `RELEASE_v*.md` are historical notes only.

**Virtual machines → Disks** creates, loads, attaches, detaches, deletes, and grows raw disk images, including selectable installation/boot images. **Console** adds mouse capture/release buttons, click capture, and a configurable release hotkey (Control + Option + Escape by default) for macOS/Linux. Windows uses QEMU’s console and Control + Option + G. See [disk image workflows](Docs/DISK_IMAGES.md) and [console controls](Docs/VM_CONSOLE.md).

Run `Scripts/test-disk-images.sh` and `Scripts/test-arm-guests.sh` for disk workflows and native Linux/QEMU startup/shutdown checks. The latter requires macOS, QEMU, and swtpm; its synthetic ISO tests configuration and EFI/backend startup, not OS installation. Full OS installation and interactive console checks require your own compatible installer media.

# MacOnMac v0.16.0 — Guest Tools v2

This version extends v0.15.0 with manual host/guest clipboard offers, paired HMAC-authenticated ping/status requests, streamed file progress and SHA-256 receipts, network status diagnostics, and an opt-in per-user macOS guest-agent installer. It preserves VM NAT/VirtioFS and all earlier storage/VM work. Nothing here establishes direct boot of an existing physical macOS installation.

**Start here:** [Release notes](Docs/RELEASE_v0.16.0.md), [Guest Tools v2 specification](Docs/GUEST_TOOLS_V2_SPEC.md), [Networking](Docs/NETWORKING.md). Run `./Scripts/verify-linux.sh` for portable tests; macOS builds and guest testing must be done in Xcode and a managed VM on your Mac.

# MacOnMac v0.15.0 — Network and Guest/Host Integration

Adds per-VM NAT / bridged / disconnected networking, persistent virtual MAC identity, opt-in VirtioFS workspace shares, and data-only host/guest messaging and file staging. Includes `MacOnMac-host` and `MacOnMac-guest-agent` CLI sources and a new SwiftUI Network & Guest Tools panel. NAT works without special bridging entitlements; bridged mode requires `com.apple.vm.networking` and signing support. None of these changes enable booting an existing physical macOS installation.

**Start here:** [Network specification](Docs/NETWORKING.md), [Guest/host tools](Docs/GUEST_HOST_TOOLS.md), [Release notes](Docs/RELEASE_v0.15.0.md).

Run `./Scripts/verify-linux.sh` for portable structural/policy checks; full macOS Xcode build and live guest boot are still unverified. On your Mac use `./Scripts/build-host-tool.sh` and `./Scripts/build-guest-agent.sh` for standalone utilities.

# MacOnMac v0.14.0 — Physical Disk Grant Experiment (Withdrawn)

The v0.14.0 physical-disk grant experiment is not part of the current release scope. The attachment toggle and daemon grant path are disabled. Do not follow older release notes that describe granting a physical disk to a VM; use the current [release support matrix](Docs/SUPPORT_MATRIX.md). Topology inspection remains diagnostic and read-only.

# MacOnMac v0.12.0 — Signed daemon deployment foundation

This release adds the launchd daemon executable, app-embedded registration plist, explicit ServiceManagement approval UI, mutual code-signing requirement checks, and daemon health protocol. **No raw physical disk handles or macOS bare-metal direct boot are exposed.**

The checked-in Xcode project now includes all three native targets; alternatively regenerate it from `project.yml` with `./Scripts/generate-xcodeproj.sh` (requires XcodeGen). Full instructions: `Docs/RELEASE_v0.12.0.md`. Verify the built, signed app with `Scripts/check-daemon-bundle.sh`.

# MacOnMac v0.11.0

# MacOnMac v0.10.0

Broker policy hardening and regression tests. **Physical raw disk attachment remains disabled.** See `Docs/RELEASE_v0.10.0.md`.

# MacOnMac v0.5.0

Native macOS storage and virtualization research application. **v0.5.0 adds managed macOS guest provisioning from a locally provided Apple IPSW restore image.** Direct boot of existing physical macOS installations is not supported.

## Build
Open `MacOnMac.xcodeproj` in Xcode on an Apple Silicon Mac with supported Xcode/macOS SDK. Run `Scripts/verify.sh`, or `Scripts/generate-xcodeproj.sh` if regenerating via XcodeGen.

## Provision
In **Virtual machines → Overview**, choose a **new destination folder that does not exist**, select a compatible Apple macOS `.ipsw` restore image, set CPU/RAM and 64+ GiB disk, and choose **Install macOS**. On successful installation choose **Start**. Incomplete VM folders from failed installation are intentionally retained.

## Safety
Device/APFS inspection remains read-only. Privileged physical device access, generic passthrough and existing-installation boot remain disabled.

See `Docs/VM_PROVISIONING.md`, `Docs/RELEASE_v0.5.0.md` and `Docs/SECURITY.md`.


See `Docs/RELEASE_v0.5.0.md` for the managed VM lifecycle changes.

## v0.6.0 physical storage milestone

The read-only VirtIO block-device attachment and file-descriptor lease interfaces are implemented, but a signed privileged XPC service **is not yet installed**. Ordinary users cannot attach raw physical disks through the UI. This safety-critical capability remains disabled; see `Docs/PHYSICAL_DISK_BACKEND.md`.


## v0.9.0
Read-only selected-device preflight and fail-closed XPC helper prototype; see `Docs/RELEASE_v0.9.0.md`. The checked-in .xcodeproj builds the app; run `Scripts/generate-xcodeproj.sh` with XcodeGen to add the separate XPC helper target. Raw physical attachment remains disabled.


**v0.9.0:** Diagnostic XPC transport is now wired into the UI. This is not a privileged disk broker; physical disk passthrough remains intentionally disabled. See Docs/RELEASE_v0.9.0.md.


## v0.11.0
See `Docs/RELEASE_v0.11.0.md` and `Docs/BROKER_DEPLOYMENT.md`. Run `./Scripts/test-broker-contract.sh` to verify the versioned capability contract. Raw physical-device passthrough is disabled.

## v0.14.0 read-only APFS topology laboratory

Use **Devices → Privileged daemon → Inspect selected disk topology** after
installing and approving the signed daemon. This performs *only* metadata reads:
`diskutil list -plist`, `diskutil apfs list -plist`, `diskutil info -plist`
for each observed descendant and `/` for host-root reference, plus a read-only
DiskArbitration `DADiskIsClaimed` query. It reports APFS physical-store ancestry,
synthesized volumes, mount state, multi-store containers, and host-root overlap.

**No APFS / existing macOS disk can be granted to a VM in this build.** The
exclusive `DADiskClaim`/`DADiskUnclaim` lifecycle is not yet implemented or
validated on macOS. `candidateUnclaimed` means *only* preliminary observations.
Physical-disk attachment and descriptor grants are disabled in this release. The daemon exposes topology diagnostics only; it cannot grant a raw disk descriptor to a VM.

`./Scripts/verify.sh` runs the tests and a macOS Xcode compile.
`./Scripts/verify-linux.sh` runs structural and cross-platform pure-Swift tests.

Build the structured VM inventory/status tool with `Scripts/build-vm-cli.sh`; see `Docs/VM_LIFECYCLE_CLI.md`.
