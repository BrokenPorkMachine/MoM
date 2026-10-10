# Broker deployment (updated v0.12.0)

The signed launchd daemon *deployment path* is now implemented, but **all raw disk access is still denied**. See `DAEMON_COMPONENT_SPEC.md` and `RELEASE_v0.12.0.md`. The older diagnostic XPC helper remains an unprivileged app service.

# Broker deployment / signing specification

## Present architecture
The `VolumeBootDiskBroker` target is an app-embedded, *unprivileged* XPC service. Its capability report is advisory and it grants no disk file descriptors. An app-embedded XPC service is NOT a privileged daemon and its existence must not be interpreted as disk authorization.

## Future privileged architecture (not shipped)
Use a separately signed and installed launchd daemon with the appropriate macOS ServiceManagement supported configuration and user authorization. The daemon must independently authenticate the calling process using its audit token and a strict code-signing requirement; PID or executable path alone is insufficient. Bind each authorization to a specific selected whole-device identity and transaction, not an arbitrary `/dev` path.

Verify device identity with DiskArbitration and IOKit immediately before opening; recursively resolve partitions, APFS synthesized volumes, and all physical backing stores. Deny the host root store, mounted descendants, incomplete topology, media changes, virtual devices, or uncertain identity. Read-only only, with the kernel FD opened `O_RDONLY` and passed through an authenticated XPC channel. Keep a broker-owned lifetime lease and close on disconnect, invalidation, or device disappearance. Never trust the GUI's preflight or status string for authorization.

## Integration tests to add on a signed macOS host
- Unauthorized client, different signing identity, malformed message, stale device UUID.
- Media unplug/replug and BSD node reassignment between preflight and open.
- Mounted APFS descendants, multi-store containers, and host-root identification.
- Service crash, client crash, timeout, lease cleanup and EOF/disconnect.
- Block-level hash equality across read-only attach and detach on an expendable disk.
