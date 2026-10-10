# VolumeBoot v0.12.0 — Signed launchd daemon deployment & authenticated health channel

## Implementation
- Adds **separate privileged daemon tool** (`VolumeBootRawDiskDaemon`), embedded into the main app at `Contents/MacOS/VolumeBootRawDiskDaemon` by an XcodeGen post-build script.
- Adds SMAppService-compatible launchd plist under `Contents/Library/LaunchDaemons` using `BundleProgram`, `MachServices`, and `AssociatedBundleIdentifiers`.
- Adds **manual, explicit** daemon registration and approval status in the storage UI, using `SMAppService.daemon(plistName:)`. There is no auto-installation.
- Implements a mach-service listener and a client using `.privileged`, mutual code-signing requirement checks, and self-signature team-ID discovery. **If unsigned/ad-hoc or Team ID is missing, daemon exits or client refuses registration.**
- Daemon checks root effective UID before starting; provides only `healthReport` and denial-only `readOnlyGrantStatus`.
- Protocol versioning, payload size restrictions, consistent signing requirements, bounded XPC response time, and Linux-runnable pure contract tests.

## Intentionally missing
- **NO raw disk open, no descriptor passing, no real leases, no writable access.**
- No direct boot of a bare-metal macOS installation.
- Mac SDK compilation and actual root daemon registration remain **unverified** in this environment.
- Checked-in `VolumeBoot.xcodeproj` includes all three targets. XcodeGen can regenerate it from `project.yml` if preferred; the XcodeGen and checked-in configurations must be compared during the macOS build audit.

## macOS checklist
1. Open the included Xcode project. If regenerating from YAML instead, `brew install xcodegen` and run `./Scripts/generate-xcodeproj.sh`.
2. Set the same non-ad-hoc Apple Developer Team for BOTH `VolumeBoot` and `VolumeBootRawDiskDaemon` targets.
3. Build using Xcode with hardened runtime enabled; validate actual built app with `Scripts/check-daemon-bundle.sh /path/to/VolumeBoot.app`.
4. Move application to `/Applications` if needed, run it, and use the explicit `Request installation` button. Approve the daemon through System Settings.
5. Verify `Test signed connection` reports a root daemon, with physical grants disabled.
6. Run negative tests with a second Team ID, ad-hoc signature, unapproved service, app restart, and daemon crash.

## Next gated milestone
Before opening physical media, independently verify complete APFS and host-root topology inside the privileged daemon, fresh stable identity and mount state, approved user intent, lease persistence across XPC calls, and FD transfer and cleanup under a full macOS integration test. Read-only kernel FD + read-only VZ attachment both required.
