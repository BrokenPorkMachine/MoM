# VolumeBoot v0.9.0 — Read-only Safety Gate and Lease Foundation

## What was implemented
- Deterministic fail-closed physical media eligibility policy.
- Whole-disk-only device name and physical media checks.
- Explicit rejection of unknown host-root, mount-descendant, APFS-store, and identity state.
- In-memory reservation/attachment lease state machine with conflict checks.
- Separate unit tests for positive and negative authorization-policy cases.
- Existing unprivileged XPC diagnostics retained without a raw-disk access path.

## What is NOT implemented
- No privileged LaunchDaemon or SMAppService installation.
- No audit-token-bound signing requirement verification.
- No raw device handle grant or FD transfer.
- No functioning physical passthrough or direct physical macOS boot.

## Reason for scope limit
Granting block device access from an unverified XPC caller, or relying on advisory diskutil metadata to prove a disk is safe, is unacceptable. Runtime-enabled privileged functionality needs verification on a signed macOS/Xcode build and a disposable USB device.

## Next milestone
Implement a signed, privileged daemon with restricted Mach service, audit-token-based code requirement, DiskArbitration/IOKit topology validation, verified read-only FD handoff, and disconnect cleanup. Security tests must precede enabling the feature.
