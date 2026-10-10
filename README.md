# VolumeBoot v0.16.0 — Guest Tools v2

This version extends v0.15.0 with manual host/guest clipboard offers, paired HMAC-authenticated ping/status requests, streamed file progress and SHA-256 receipts, network status diagnostics, and an opt-in per-user macOS guest-agent installer. It preserves VM NAT/optional bridging/VirtioFS and all earlier storage/VM work. Nothing here establishes direct boot of an existing physical macOS installation.

**Start here:** [Release notes](Docs/RELEASE_v0.16.0.md), [Guest Tools v2 specification](Docs/GUEST_TOOLS_V2_SPEC.md), [Networking](Docs/NETWORKING.md). Run `./Scripts/verify-linux.sh` for portable tests; macOS builds and guest testing must be done in Xcode and a managed VM on your Mac.

# VolumeBoot v0.15.0 — Network and Guest/Host Integration

Adds per-VM NAT / bridged / disconnected networking, persistent virtual MAC identity, opt-in VirtioFS workspace shares, and data-only host/guest messaging and file staging. Includes `volumeboot-host` and `volumeboot-guest-agent` CLI sources and a new SwiftUI Network & Guest Tools panel. NAT works without special bridging entitlements; bridged mode requires `com.apple.vm.networking` and signing support. None of these changes enable booting an existing physical macOS installation.

**Start here:** [Network specification](Docs/NETWORKING.md), [Guest/host tools](Docs/GUEST_HOST_TOOLS.md), [Release notes](Docs/RELEASE_v0.15.0.md).

Run `./Scripts/verify-linux.sh` for portable structural/policy checks; full macOS Xcode build and live guest boot are still unverified. On your Mac use `./Scripts/build-host-tool.sh` and `./Scripts/build-guest-agent.sh` for standalone utilities.

# VolumeBoot v0.14.0 — Experimental Read-Only Physical Disk Grants

VolumeBoot adds a **bounded XPC `FileHandle` handoff** from its signed, root
LaunchDaemon to the unprivileged VM process. A selected disposable physical
disk may be attached **read-only as secondary storage to an existing managed
macOS VM**. All actual behavior is pending a native macOS SDK compile, signing,
SMAppService installation, and live disposable-device test.

**Very restrictive v0.13 policy:** the device must be an *external physical
whole disk*, unmounted, *without a partition map containing partitions, APFS,
or a recognized filesystem*, and with consistent DiskArbitration/IOKit identity
and metadata before/after an `O_RDONLY` open. Unknown means denied. Do not use
this feature with valued data. No writes, filesystem repair, unmounting or
destructive initialization operations are implemented.

The existing macOS installation use case remains **unsupported**, because disks
with APFS/system partitions are explicitly denied. This release is a controlled
prerequisite, not evidence of direct macOS boot compatibility.

## Getting started

1. Read `Docs/RELEASE_v0.14.0.md`, `Docs/READ_ONLY_GRANT.md`, and `Docs/BROKER_DEPLOYMENT.md`.
2. Build the included `VolumeBoot.xcodeproj` on macOS with an Apple Developer Team.
3. Verify signatures with `Scripts/check-daemon-bundle.sh`.
4. Request and approve privileged daemon registration in the Device Browser.
5. Provision and confirm a normal managed VM **without** any physical disk first.
6. Only with an expendable **empty** external disk, select the whole-disk row,
   check the experimental secondary-disk toggle, and start that managed VM.
7. Stop the VM to release the local FD and XPC lease. Check the host test drive
   remains byte-for-byte unchanged using your preferred independent tooling.

## Checks runnable without Xcode

`./Scripts/verify-linux.sh` includes deterministic policy, daemon-contract,
lease reservation and authorization regression tests plus syntax/plist checks.
This is **not** a macOS full build or hardware validation.

# VolumeBoot v0.12.0 — Signed daemon deployment foundation

This release adds the launchd daemon executable, app-embedded registration plist, explicit ServiceManagement approval UI, mutual code-signing requirement checks, and daemon health protocol. **No raw physical disk handles or macOS bare-metal direct boot are exposed.**

The checked-in Xcode project now includes all three native targets; alternatively regenerate it from `project.yml` with `./Scripts/generate-xcodeproj.sh` (requires XcodeGen). Full instructions: `Docs/RELEASE_v0.12.0.md`. Verify the built, signed app with `Scripts/check-daemon-bundle.sh`.

# VolumeBoot v0.11.0

# VolumeBoot v0.10.0

Broker policy hardening and regression tests. **Physical raw disk attachment remains disabled.** See `Docs/RELEASE_v0.10.0.md`.

# VolumeBoot v0.5.0

Native macOS storage and virtualization research application. **v0.5.0 adds managed macOS guest provisioning from a locally provided Apple IPSW restore image.** Direct boot of existing physical macOS installations is not supported.

## Build
Open `VolumeBoot.xcodeproj` in Xcode on an Apple Silicon Mac with supported Xcode/macOS SDK. Run `Scripts/verify.sh`, or `Scripts/generate-xcodeproj.sh` if regenerating via XcodeGen.

## Provision
In **Managed VM**, choose a **new destination folder that does not exist**, select a compatible Apple macOS `.ipsw` restore image, set CPU/RAM and 64+ GiB disk, and choose **Install macOS**. On successful installation choose **Start VM**. Incomplete VM folders from failed installation are intentionally retained.

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
The existing v0.13.0 blank-external-media grant is unchanged.

`./Scripts/verify.sh` runs the tests and a macOS Xcode compile.
`./Scripts/verify-linux.sh` runs structural and cross-platform pure-Swift tests.
