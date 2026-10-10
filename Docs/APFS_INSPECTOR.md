# APFS Inspector — v0.2.0 implementation specification

## Implemented
- Executes `diskutil apfs list -plist` without device mutation.
- Parses container identifiers, UUIDs, physical stores, volumes, roles, mount points and best-effort encryption metadata.
- Exposes typed `APFSTopology`, `APFSContainerRecord`, and `APFSVolumeRecord`.
- Produces explicit warnings for unsupported response shapes or records without identifiers.
- Surfaces metadata alongside the device inventory.

## Deliberate limitations
- APFS role/volume metadata are not proof of bootable macOS.
- `diskutil` property-list keys can vary across macOS releases. Unknown fields are ignored; missing required IDs are surfaced as warnings.
- System/Data volume-group pairing, blessed boot assets, snapshot seals and cryptex verification are not implemented.
- No FileVault unlock, volume mounting, mutation, or direct APFS on-disk parsing.

## Next tasks
1. Add real fixture captures from macOS 27 and supported earlier versions (redacted).
2. Implement volume group correlation with corroborating `diskutil apfs listVolumeGroups` / supported metadata on target OS.
3. Add dedicated installation classification based on mounted System volumes and explicit evidence.
4. Add read-only tests covering Fusion Drive/multiple physical stores, missing metadata, and encrypted volumes.

## Safety invariant
All inspection operations must remain non-mutating. Never treat a synthetic APFS container node as a physical disk passthrough destination.
