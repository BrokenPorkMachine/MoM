# Privileged Broker Daemon — Component Specification (v0.12.0)

## Roles / trust
**App**: never root. Shows status, asks for explicit registration, presents read-only discovery. **Launchd daemon**: executable registered by SMAppService, runs in a privileged bootstrap context, is signed by the same Apple Developer Team, and accepts only VolumeBoot app identity. **Existing app XPC service**: diagnostics only, separate from privileged daemon.

## Deployment
- `project.yml`: `VolumeBootRawDiskDaemon` command line tool and app post-build copy step.
- launchd plist: `Resources/LaunchDaemons/ca.zensoftware.VolumeBoot.RawDiskBroker.plist`.
- Binary location: `VolumeBoot.app/Contents/MacOS/VolumeBootRawDiskDaemon`.
- plist location: `VolumeBoot.app/Contents/Library/LaunchDaemons/ca.zensoftware.VolumeBoot.RawDiskBroker.plist`.
- Registration: only on user interaction with `SMAppService.daemon(plistName:).register()`; approval is a separate OS-level step.

## Authentication
- No caller-supplied PID, file path or team string used for identity.
- Runtime obtains own signing team ID from Security.framework; requires `anchor apple generic`, **exact identifier**, and matching 10-character Developer Team ID.
- Uses documented `NSXPCListener.setConnectionCodeSigningRequirement` and `NSXPCConnection.setCodeSigningRequirement` for both sides. Requires a non-ad-hoc signed build.
- Future requests that grant FD must independently bind device identity and authorization context to connection lifetime; code signing alone is NOT sufficient user authorization.

## IPC protocol
`healthReport -> bounded JSON Health`, `readOnlyGrantStatus(bsdWholeDiskName) -> DENIED`. No XPC method exists for opening a disk or transferring file descriptors.

## Non-goals
No device write, encryption bypass, APFS mutation, boot policy patching, arbitrary command execution, free-form file path RPC, or direct macOS boot.

## Tests
- Pure Swift protocol tests, signing-requirement format and injection resistance, invalid whole-disk names.
- Bundle plist validation, presence of daemon build target and copy scripts.
- macOS Xcode build, signed app/daemon verification and approval check on actual host (pending).
