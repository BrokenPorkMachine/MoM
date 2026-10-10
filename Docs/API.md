# VolumeBoot — Public Modules and Contracts

Specification v0.1.0 · 2026-10-07

## v0.1 implemented types
`StorageDevice`: identifier/name/filesystem/mount/transport/size flags. `DeviceInventoryService.listDevices()`: async read-only inventory. `CompatibilityEngine.inspect(_:)`: conservative classification. `VMRuntimeService.startExistingVM(at:cpuCount:memoryBytes:)`: starts a pre-provisioned VM on Apple Silicon. `stop()`: requests stop. `DiskBrokerPolicy`: always denies leases.

## Later APIs
`APFSInspector.inspect`, `VMRegistry.save/load`, `BootCoordinator.preflight`, `PrivilegedDiskBroker.requestLease`, `VZRestoreInstaller.install`, `USBBackend.probe`, `DiagnosticsExporter.export`.

## Error policy
Error codes must be stable, typed and carry safe remediation info. All async work is cancellable and must not strand disk leases.


## Cross-cutting rules
- No writes to host-mounted storage from a guest.
- Do not confuse block-device attachment with boot compatibility.
- Treat disk identity and platform configuration as untrusted until independently verified.
- Each API must expose typed errors, useful diagnostics and deterministic test seams.
- Experimental features remain disabled in production builds until their release gates pass.

## Status in v0.1.0 scaffold
This is a specification, not a claim of implemented production functionality. The implementation status appears in `IMPLEMENTATION_MATRIX.md`.


## v0.14.0 privileged topology diagnostic (protocol v3)

`readOnlyTopology(_ wholeDiskBSDName: String, withReply: (String) -> Void)`
returns `PhysicalDiskTopologyReport` JSON, including `candidateUnclaimed`,
`inconclusive` or `denied`, APFS physical-store and synthesized-volume arrays,
mount-state evidence, host-root overlap, reasons and limitations. Strings that
begin with `DENIED:` or `INCONCLUSIVE:` mean the daemon could not construct a
structured report. This method **never** opens a physical disk, changes mounts,
or creates an exclusive Disk Arbitration claim.

Version 3 is incompatible with earlier daemon protocol versions; rebuild and
re-register the signed daemon rather than mixing daemon/app versions.

## v0.15.0: Network and guest integration

See `NETWORKING.md` and `GUEST_HOST_TOOLS.md`. NAT is the default; optional bridging requires a suitable entitlement. VirtioFS sharing and the guest data exchange require an explicit opt-in. The file exchange is not a privileged management protocol; no inbound command execution is implemented. Full macOS validation remains outstanding.
