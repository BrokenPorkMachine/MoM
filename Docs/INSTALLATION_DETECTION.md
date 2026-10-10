# Installation Detection — v0.3.0

## Scope
Read-only candidate identification based on APFS volume role and volume-group UUID. Groups System and Data only when the same nonempty group UUID identifies one unambiguous Data volume within the same container. No guessing based on volume names. No disk mutations.

## Current limitations
A System role is **not** evidence of a bootable, authenticated, compatible macOS installation. OS version, Preboot integrity, snapshot seal, and boot policy are not yet validated. Missing UUIDs and ambiguous pairings produce warnings, not forced matches. Diskutil plist structures vary by OS release, so fixtures from macOS 27 are required.

## Acceptance tests
System+Data with equal group IDs; mismatched group IDs; missing ID; duplicate matching Data volumes; multiple containers; encrypted volumes; System without Data; corrupted plist. Ensure no writes to volumes.
