# MacOnMac Implementation and Qualification Matrix

The earlier sections record implementation milestones, not current release availability. See the [release support matrix](SUPPORT_MATRIX.md) for the shipping boundary and the qualification record below for current test evidence.

| Subsystem | Current implementation | Limitations |
|---|---|---|
| Storage inventory | Read-only diskutil discovery | Live DiskArbitration event feed incomplete |
| APFS inspector | Read-only container and volume parsing | Adds physical-store graph proof; runtime validation is still pending |
| macOS installation candidates | System/Data grouping heuristic | Not a bootability certification |
| Managed macOS VM | Restore IPSW provisioning, persistent identity, VZ console | Requires full Xcode and macOS host testing |
| Unprivileged XPC | Versioned diagnostic service and timeout handling | Read-only, empty external test disks only; macOS integration unverified |
| Privileged daemon deployment | launchd plist, separate signed-tool target, SMAppService approval UI | Registration and signed macOS XPC connection not runtime-tested |
| Caller authentication | Reciprocal code signing requirements using Team ID and exact identifiers | Per-device user opt-in UI; OS grant is narrowly gated; OS-level disk claim still missing |
| Disk safety | Pure historical policy tests; production daemon reports topology only | No physical disk grants in production; attachment APIs and raw opener excluded from app/daemon targets |
| Physical disk passthrough | Not included in production runtime | Disabled pending stable identity, complete topology, exclusive Disk Arbitration claim lifecycle, cleanup, signed deployment, and hardware qualification |
| Existing physical macOS boot | Research only | No direct boot functionality |
| Release validation | Linux Swift parse/tests, plists/YAML/PBX structure, zip integrity | macOS Xcode compile/sign, live daemon and test-media tests pending |

**Policy:** No raw physical disk operations may be activated based on diagnostic or inferred metadata alone.

**Current physical-disk release boundary:** historical NSXPC FileHandle and raw-open experiments remain in research source only. Production targets expose no grant operation and cannot attach any host physical disk. APFS and existing macOS disks remain ineligible. See `PHYSICAL_DISK_SECURITY_GATES.md` for the conditions required before reconsideration.

| APFS topology proof | Pure Swift graph validator, daemon inventory collector and read-only UI report | Cannot authorize APFS attachment before long-lived DA claim + post-claim verification |
| Disk Arbitration research | `DADiskIsClaimed` observation and standalone opt-in C claim/unclaim lab | Laboratory not integrated into daemon and not macOS-verified |

## v0.15.0: Network and guest integration

See `NETWORKING.md` and `GUEST_HOST_TOOLS.md`. NAT is the default; optional bridging requires a suitable entitlement. VirtioFS sharing and the guest data exchange require an explicit opt-in. The file exchange is not a privileged management protocol; no inbound command execution is implemented. Full macOS validation remains outstanding.

## v0.16.0: Guest Tools v2

| Subsystem | Added | Not yet verified |
|---|---|---|
| Clipboard | Manual, text-only offers and explicit import via UI/CLI | AppKit host/guest runtime |
| Authenticated guest requests | Paired HMAC-SHA256 ping/status allowlist, signed responses, time window | Hostile-filesystem proof, macOS integration |
| File transfer | Paired HMAC receipts, streamed chunk writes, verified listing and receive, bounded quotas/expiry | Multi-GB resume, hostile-guest isolation, macOS VM qualification |
| Networking diagnostics | Mode + heartbeat age + signed response status | Guest IP/DHCP/DNS and actual traffic |
| Guest installation | Per-user launchd user-agent install/uninstall script | macOS launchctl runtime |

Existing physical macOS installations are not bootable using this release.

## Managed guests and workspace audit

| Subsystem | Current implementation | Validation limits |
|---|---|---|
| Managed guests | macOS IPSW; native ARM Linux EFI; Windows ARM QEMU/HVF with persistent UEFI/TPM | Synthetic backend checks pass on the current host; no guest family has completed real-media qualification (record below) |
| Disk images | Sparse raw creation, boot selection, secondary attachment/access, growth, detach, confirmed deletion, session locks | Guest partition/filesystem growth remains a guest operation |
| Console input | Native capture/release, configurable host release shortcut, focus-loss release; external Windows console controls | Interactive input validation remains manual |
| Workspace | Guided creation, library/recents, separate console and settings, dirty-state protection, readiness, graceful/forced shutdown | Light/dark/compact render checks; VoiceOver and real guest interaction remain manual |
| Optimization | Linear block ingestion for SHA-256, throttled progress, bounded QEMU log reads, lazy inventory | Reference SHA vectors and incremental boundary tests pass |

The app builds in Debug without code signing on the current Apple Silicon host using the macOS 27 SDK. Full signed bundle/notarization checks and privileged daemon deployment are separate release gates. See [audit scope and validation](AUDIT_AND_POLISH.md).

## Real installer qualification record — 2026-10-12

This is the result of the current qualification attempt, not a claim that guests are supported.

| Host tested | App / toolchain | Backend checks | Real installer qualification |
|---|---|---|---|
| Apple Silicon, macOS 27.0.1 (build 26A434), arm64 | Xcode 27.1 (27A9275), macOS 27.0 SDK; deployment target macOS 15.0; Debug build with code signing disabled | `Scripts/verify.sh` passed, including 37 synthetic ARM guest assertions: native Linux VM configuration/start/stop, disk lease/persistence lifecycle, and Windows QEMU 11.1.2 + swtpm 0.10.2 startup/shutdown with synthetic media. Guest Tools host/agent tests also passed. | None. No `.ipsw` or `.iso` installer media was found in the repository or Downloads. No login, installed guest reboot, guest network, driver, display, or audio result was collected. |

| Guest | Backend | Install | Login | Reboot | Disk persistence | Networking | Drivers | Display | Audio | Shutdown |
|---|---|---|---|---|---|---|---|---|---|---|
| Managed macOS guest | Apple Virtualization.framework | Not run — no IPSW | Not run | Not run | Not run | Not run | Not run | Not run | Not run | Not run |
| AArch64 Linux guest | Apple Virtualization.framework | Not run — no distribution ISO | Not run | Not run | Not run | Not run | Not run | Not run | Not run | Not run |
| Windows ARM64 guest | QEMU/HVF, UEFI, swtpm | Not run — no Windows ARM64 ISO | Not run | Not run | Not run | Not run | Not run | Not run | Not run | Not run |

The guest lifecycle assertions above operate on synthetic media and firmware; they prove backend configuration and startup behavior only. They do not count as installation, login, guest reboot, guest disk integrity, guest networking, driver, display, or audio qualification. macOS 15.x and 26.x hosts have not been exercised. The only host build recorded here is an unsigned Debug build on macOS 27.0.1; it does not qualify a distributable artifact.

For each future pass, record the exact Mac model/chip and host build, app commit and signed artifact identity, installer release and SHA-256, backend/dependency versions, and evidence for every test column. Validate install to desktop/login, restart and reboot, a guest-written persistence sentinel across reboot, guest DHCP/DNS/outbound checks, guest device/driver status, display resolution and input, audio playback/output, and clean guest shutdown. Run the same matrix for each host macOS version claimed by the release.
