# MacOnMac release support matrix

**Status: evaluation preview; no guest configuration is currently production-qualified.** The app's deployment target is macOS 15.0 on Apple Silicon. That is a build/deployment floor, not evidence that every host release from macOS 15 onward has passed end-to-end validation. This matrix distinguishes code that exists from configurations that may be represented as supported to customers.

## Host and guest configurations

| Host | Guest | Backend | Current status | Release boundary |
|---|---|---|---|---|
| Apple Silicon, macOS 15.0 or later | macOS guest installed from a compatible Apple IPSW | Apple Virtualization.framework | Implemented; installation and lifecycle qualification pending | Evaluation only. No macOS major/minor combination is production-supported until the signed app completes install, reboot, shutdown, storage, networking, and recovery checks on that host release. |
| Apple Silicon, macOS 15.0 or later | AArch64 Linux from ISO | Apple Virtualization.framework | Implemented; synthetic EFI/backend startup checks exist; real distribution installation and interactive use are unqualified | Evaluation only. No distribution/version is production-supported until installer, boot persistence, virtio devices, networking, shutdown, and recovery are checked. |
| Apple Silicon, macOS 15.0 or later | Windows ARM64 from ISO | User-approved QEMU 9.2+ with HVF, UEFI, and swtpm | Backend paths are SHA-256 pinned per user and version-checked at launch; Windows installation and interactive use are unqualified | Experimental evaluation only. No Windows release is production-supported until installation, activation behavior, drivers, networking, display/input, TPM persistence, updates, shutdown, and recovery are checked. See `BACKEND_EXECUTABLE_TRUST.md`. |

The phrase “macOS 15.0 or later” does not promise support for future host releases. The declared Xcode deployment target is 15.0; the project has not published a host-by-host qualification record. Build, signing, notarization, installation, and upgrade behavior must be qualified separately for each host release named in a future supported matrix.

## Feature matrix

| Feature | Backend / guest scope | Release status | Current behavior / gate |
|---|---|---|---|
| Managed VM creation and lifecycle | Apple Virtualization.framework macOS/Linux; QEMU/HVF Windows ARM64 | Implemented, guest qualification pending | Available for evaluation. Do not describe any guest configuration as enterprise-supported until its host/guest row passes the checks above. |
| VM disk images | Managed virtual disks for supported VM backends | Implemented; end-to-end guest qualification pending | Available for evaluation. Use VM-owned image files; validate guest I/O, detach, growth, full-disk behavior, crash recovery, and data integrity before declaring support. |
| NAT networking | Managed VM backends | Implemented; live guest networking qualification pending | Available for evaluation. DHCP, DNS, outbound connectivity, isolation, reconnect, and host sleep/wake remain release gates. |
| Bridged networking | Apple Virtualization.framework where entitled | **Disabled in this release** | The UI omits the option and connectivity policy rejects saved/manual bridged profiles. Loading an older profile selects NAT; qualification requires the entitlement, signed build, and live-network tests. |
| VirtioFS workspace sharing and guest tools | macOS/Linux VM integrations; guest-specific | Implemented, security and compatibility qualification pending | Opt-in evaluation functionality. Do not use as a hostile-guest isolation boundary; validate guest versions, permissions, reconnect, and data-integrity behavior before general availability. |
| Host disk inventory, APFS inspection, topology diagnostics | Host macOS storage APIs; optional signed daemon for topology | Inspection-only | Visible as diagnostics. These operations must not change mounts, open a host disk for guest use, or imply compatibility with booting a physical installation. |
| Physical disk attachment / descriptor grants | Privileged daemon to managed VM | **Excluded from production targets** | The app has no attachment workflow or VM runtime path; the XPC protocol has no request/release operations; and the production daemon does not compile the raw-device opener or grant policy. Topology diagnostics remain read-only. Keep APFS and existing macOS disks ineligible. Reintroduce only after every gate in `PHYSICAL_DISK_SECURITY_GATES.md` passes, including signed real-hardware lifecycle validation. |
| Existing physical macOS installation boot | Physical APFS/system volumes | Unsupported / research | Not exposed as a VM boot option. No compatibility or data-safety claim is made. |
| USB, GPU, PCIe, or Apple Neural Engine passthrough | Physical host devices | Unsupported | Not exposed. These require separate backend capability and security qualification. |

## Release gates

Before calling a host/guest/backend row supported, keep a versioned qualification record with the exact Mac model/chip, host build, app build and signing identity, guest installer/version, backend and dependency versions, and results. At minimum, pass clean install, first boot, restart, graceful and forced stop, persistent storage and integrity, configured networking, sleep/wake, upgrade, uninstall/reinstall, resource pressure, diagnostics, and recovery from interrupted operations. Run the checks on every host macOS major version claimed in the release notes and on representative supported hardware.

The release pipeline must build and sign the distributable app and privileged helper, verify signatures and entitlements, produce a notarized artifact, and install/update/uninstall that artifact on a clean supported host. A source compile or synthetic ISO startup is not a substitute for these checks. Until those records exist, describe this product as an evaluation preview and identify guest workflows as unqualified.

## Qualification run on the available host — 2026-10-12

The available test host is Apple Silicon, arm64, macOS 27.0.1 (build 26A434), with Xcode 27.1 (27A9275), macOS 27.0 SDK, QEMU 11.1.2, and swtpm 0.10.2. The deployment target remains macOS 15.0. `Scripts/verify.sh` passed outside the restricted sandbox, including policy, disk-image, networking, guest-tool protocol, and 37 synthetic ARM guest checks. Debug and Release app schemes compile successfully; the Release artifact validates only as ad-hoc signed (`TeamIdentifier=not set`). The daemon bundle gate therefore rejects it, and a team-signing attempt could not match the installed certificate to the requested team. This verifies source/build and synthetic backend paths on this one host; it does not qualify a signed release artifact or any installed guest.

No `.ipsw` or `.iso` installer media was found in the repository or Downloads during this run. Consequently, for managed macOS, AArch64 Linux, and Windows ARM64, real install, login, reboot, guest-written disk persistence, guest networking, drivers, display, audio, and shutdown remain **not run**. macOS 15.x and 26.x hosts are also untested. The detailed per-guest results and repeatable evidence requirements are in [IMPLEMENTATION_MATRIX.md](IMPLEMENTATION_MATRIX.md).

## Current release policy

This repository does not yet establish enterprise production support for any complete VM guest configuration. The managed macOS, ARM Linux, and Windows ARM paths remain available for evaluation while their qualification gates are pending. Physical disk grants are disabled in the UI, app model, and privileged service; host inventory and topology remain inspection-only. Features marked unavailable above must stay hidden or disabled in a release build until their gates pass.
