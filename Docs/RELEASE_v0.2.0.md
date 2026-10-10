# VolumeBoot 0.2.0 — Device/APFS foundation

## Changes
- Added typed APFS topology models, conservative plist decoder, and read-only inspector.
- Added a restricted `diskutil` command runner and validated BSD identifiers for per-device queries.
- Integrated APFS summary and selected-volume roles into the storage browser.
- Retained the existing managed-VM loader without changing its boot assumptions.
- Kept raw physical disk attachment and experimental boot disabled.

## Verification
Run `Scripts/verify.sh` on a Mac with a compatible Xcode SDK. This release was assembled on Linux, so macOS framework compilation, VM operation and APFS parsing against real macOS 27 plist output are **not verified**.

## Known issues / forward work
- Current device inventory can skip a disk when `diskutil info` fails; add per-device diagnostics.
- APFS plist formats require real macOS fixture-based verification.
- Existing managed-VM boot path expects a pre-provisioned bundle; restore-image installation remains pending.
- GUI guest display and privileged disk broker remain pending.
