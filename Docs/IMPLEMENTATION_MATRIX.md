# VolumeBoot v0.14.0 — Implementation Matrix

| Subsystem | Current implementation | Limitations |
|---|---|---|
| Storage inventory | Read-only diskutil discovery | Live DiskArbitration event feed incomplete |
| APFS inspector | Read-only container and volume parsing | Adds physical-store graph proof; runtime validation is still pending |
| macOS installation candidates | System/Data grouping heuristic | Not a bootability certification |
| Managed macOS VM | Restore IPSW provisioning, persistent identity, VZ console | Requires full Xcode and macOS host testing |
| Unprivileged XPC | Versioned diagnostic service and timeout handling | Read-only, empty external test disks only; macOS integration unverified |
| Privileged daemon deployment | launchd plist, separate signed-tool target, SMAppService approval UI | Registration and signed macOS XPC connection not runtime-tested |
| Caller authentication | Reciprocal code signing requirements using Team ID and exact identifiers | Per-device user opt-in UI; OS grant is narrowly gated; OS-level disk claim still missing |
| Disk safety | Pure policy and lease state-machine tests | Blank physical media grant only; APFS topology is inspection-only |
| Physical disk passthrough | VZ read-only attachment built around already-authorized FD | FD grant implemented in source but awaits macOS integration validation |
| Existing physical macOS boot | Research only | No direct boot functionality |
| Release validation | Linux Swift parse/tests, plists/YAML/PBX structure, zip integrity | macOS Xcode compile/sign, live daemon and test-media tests pending |

**Policy:** No raw physical disk operations may be activated based on diagnostic or inferred metadata alone.

**v0.14 risk:** NSXPC FileHandle transport and read-only OS open exist in source, but the daemon has no OS-level disk claim and handles only blank external media. No existing APFS/macOS volume is eligible.

| APFS topology proof | Pure Swift graph validator, daemon inventory collector and read-only UI report | Cannot authorize APFS attachment before long-lived DA claim + post-claim verification |
| Disk Arbitration research | `DADiskIsClaimed` observation and standalone opt-in C claim/unclaim lab | Laboratory not integrated into daemon and not macOS-verified |

## v0.15.0: Network and guest integration

See `NETWORKING.md` and `GUEST_HOST_TOOLS.md`. NAT is the default; optional bridging requires a suitable entitlement. VirtioFS sharing and the guest data exchange require an explicit opt-in. The file exchange is not a privileged management protocol; no inbound command execution is implemented. Full macOS validation remains outstanding.

## v0.16.0: Guest Tools v2

| Subsystem | Added | Not yet verified |
|---|---|---|
| Clipboard | Manual, text-only offers and explicit import via UI/CLI | AppKit host/guest runtime |
| Authenticated guest requests | Paired HMAC-SHA256 ping/status allowlist, signed responses, time window | Hostile-filesystem proof, macOS integration |
| File staging | Chunked writes, progress callback, SHA-256 receipt | Multi-GB resume, hardened filesystem TOCTOU |
| Networking diagnostics | Mode + heartbeat age + signed response status | Guest IP/DHCP/DNS and actual traffic |
| Guest installation | Per-user launchd user-agent install/uninstall script | macOS launchctl runtime |

Existing physical macOS installations are not bootable using this release.

## Managed guests and workspace audit

| Subsystem | Current implementation | Validation limits |
|---|---|---|
| Managed guests | macOS IPSW; native ARM Linux EFI; Windows ARM QEMU/HVF with persistent UEFI/TPM | Synthetic EFI and live QEMU/TPM lifecycle checks pass; full guest installations need real media |
| Disk images | Sparse raw creation, boot selection, secondary attachment/access, growth, detach, confirmed deletion, session locks | Guest partition/filesystem growth remains a guest operation |
| Console input | Native capture/release, configurable host release shortcut, focus-loss release; external Windows console controls | Interactive input validation remains manual |
| Workspace | Guided creation, library/recents, separate console and settings, dirty-state protection, readiness, graceful/forced shutdown | Light/dark/compact render checks; VoiceOver and real guest interaction remain manual |
| Optimization | Linear block ingestion for SHA-256, throttled progress, bounded QEMU log reads, lazy inventory | Reference SHA vectors and incremental boundary tests pass |

The app source compiles on this Apple Silicon host using the installed macOS 26 SDK. Full Xcode bundle/signing checks and privileged daemon deployment are separate release gates. See [audit scope and validation](AUDIT_AND_POLISH.md).
