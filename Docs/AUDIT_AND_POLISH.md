# Correctness and interface audit

The audit covers managed macOS, ARM Linux, Windows ARM, raw image management, native input capture, VM state, settings persistence, and guest file staging. The existing physical disk authorization policies remain intact.

## Correctness fixes

- Repaired invalid empty dependency arrays in the Xcode project and fixed the portable generator. Project verification now rejects conflict markers and malformed empty arrays; on macOS it also parses the property list, checks object references, and verifies the app source build phase.

- Profile loading reads the manifest, hardware, and connectivity before changing selection. A failed load preserves the previous workspace. The selected OS is immutable for an existing VM; draft OS defaults no longer overwrite loaded settings.
- Hardware, network, and media edits show an unsaved indicator and block startup until saved or reloaded. Automatic disk selection/access changes update their saved baseline. Opening a different workspace or quitting prompts before discarding edits, including a configured creation draft. New VM clears previous guest-tool status and opens the VM workspace from any sidebar section.
- Native guest shutdown/error callbacks release session references and disk leases, update the console, and release any physical grant. Graceful shutdown uses the native guest request or QEMU ACPI power-down. Force stop and quitting an active VM require explicit confirmation because they power off immediately.
- Loaded Windows profiles reject unsupported network/sharing settings before saving. Live network edits are disabled. Switching workspace or quitting during file staging is blocked.
- ISO validation rejects nonregular, empty, and misaligned media before provisioning. Manifest reads reject unsupported versions and invalid boot capacities.
- Readiness checks report missing images, identity files, firmware, installation media, executables, and unsupported settings. These checks precede, and do not replace, backend configuration validation.
- Windows has an explicit single-socket CPU topology. QEMU startup diagnostics read only a bounded log tail.

## Interface

The native sidebar starts with virtual machines, with host inventory and service diagnostics kept separate. A selected VM has Overview, Console, Hardware, Disks, and Network sections. Creation has guided OS/media/resource fields; installed VMs show status and configuration summaries. The console owns the available detail area instead of sharing an overflowing setup form.

Disk creation uses a sheet; storage rows show capacity, host allocation, access mode, and full paths on demand. Detach preserves data. Permanent deletion is in an action menu with a separate confirmation. Hardware panels use consistent widths and units. Backend paths, device access, and daemon diagnostics use disclosure controls. Status includes text/symbols as well as color. Native controls retain keyboard focus, accessibility labels, and system appearance.

Recent workspaces persist per user and reopen on the next launch. The library also discovers immediate siblings of the selected workspace. Entries use canonical folder paths for identity, so filesystem aliases do not duplicate a VM and copied manifests do not collide in the list. Verification checks the maintained project without regenerating it. Both generators are tested using isolated fixtures; XcodeGen preserves maintained Info.plist privacy and application metadata.

## Optimization

A local optimized microbenchmark hashed 16 MiB using the production 128 KiB chunk size: 0.487 s before and 0.228 s after (2.14×), with identical digests. This measures hashing, not end-to-end file transfer performance.

Streaming SHA-256 processes each 64-byte block directly from the incoming chunk, keeping at most one partial block. The previous implementation repeatedly shifted the entire remaining chunk. Transfer progress reaches the main actor at most ten times per second, plus completion. Storage inventory runs on demand rather than every launch. VM configuration reuses the already-read manifest when loading profiles.

## Validation and limits

`Scripts/verify-linux.sh` covers the disk, profile, ARM backend, network, broker/grant/topology, and guest-tools regressions. Added checks include failed profile loading, dirty settings, recent VM persistence with an in-memory preferences store, immutable guest type, image access persistence, native stop cleanup, ISO alignment, a million-byte SHA reference vector, and incremental hashing across block boundaries.

`Scripts/preview-ui.sh [output-folder]` renders new VM setup, the minimum window size, an installed overview, disks, dark hardware settings, and networking. It opens temporary test windows and captures only their content. No real guests or installer images are used.

Source compilation and native Linux EFI / QEMU HVF + TPM lifecycle tests are available on this host. Full Xcode bundle/signing verification, real macOS/Windows/Linux installation, guest driver/network testing, physical daemon deployment, and interactive input/VoiceOver validation require the corresponding environment and media. No claim of certification, device passthrough readiness, or complete OS installation is implied by the UI polish.
