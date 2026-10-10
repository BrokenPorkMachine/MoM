# VolumeBoot v0.5.0 — Managed VM Lifecycle

## Implemented
- Installer progress observable through `VZMacOSInstaller.progress` with periodic UI refresh.
- Versioned, atomically persisted installation manifests; UUID, creation date, disk size, explicit provisioning/installed/failed states and last failure.
- Refuse to boot incomplete/failed managed VM records.
- Enumerate managed VM records in a user-selected destination parent folder, with UI selection.
- Keep failed provisioning bundles for inspection; never automatically erase them.
- Guard against opening `/dev/` as a managed VM destination.

## Known limitations
- This environment cannot run macOS Xcode or Virtualization.framework. Full build and guest boot need macOS host verification.
- No privileged raw-disk access; no physical passthrough.
- No automatic resume after failed install; recovery requires new provisioning to a distinct folder.
- Existing v0.4 VM manifests (v1) are not automatically migrated; compatibility migration is deferred.
- Progress is approximate and sourced from Apple installer progress.
