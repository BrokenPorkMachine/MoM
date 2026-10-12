# VolumeBoot — Architecture

Specification v0.1.0 · 2026-10-07

## Scope
Native macOS host app, read-only device discovery, VM runtime and eventually restricted physical device access. macOS VM uses Apple's supported Virtualization.framework configuration; Hypervisor.framework is research-only because it does not expose general PCIe assignment.

## Modules and dependency direction
`App -> DeviceInventory / CompatibilityEngine / VMRuntime / Diagnostics`.
`BootCoordinator -> DiskAccessProtocol`; `DiskBroker` must run out-of-process as a least-privileged helper where allowed. UI never opens device nodes.

## Processes and trust boundaries
Host app is unprivileged; helper is privileged only for preauthorized disk handle operations and must verify client's designated requirement, stable device ID, full APFS ancestry, mount ownership and policy. The scaffold intentionally does not create the helper.

## Data flow
Discover -> Identify -> Classify -> Preflight -> Reserve -> Attach -> VM lifecycle -> Release. Discovery is not authorization. Classification is not a guarantee of boot.

## Persistence
VM records have UUID, schema version, VM hardware model data, machine identifier, auxiliary storage path, virtual disk path, resource limits and monotonic lifecycle journal. Commit atomically; reject partial/corrupt records.

## Compatibility
Main supported path: Apple Silicon macOS guest configured from supported restore-image requirements. Intel hosts get discovery but not macOS guest start under this implementation.


## Cross-cutting rules
- No writes to host-mounted storage from a guest.
- Do not confuse block-device attachment with boot compatibility.
- Treat disk identity and platform configuration as untrusted until independently verified.
- Each API must expose typed errors, useful diagnostics and deterministic test seams.
- Experimental features remain disabled in production builds until their release gates pass.

## Status in v0.1.0 scaffold
This is a specification, not a claim of implemented production functionality. The implementation status appears in `IMPLEMENTATION_MATRIX.md`.

## v0.15.0: Network and guest integration

See `NETWORKING.md`, `GUEST_HOST_TOOLS.md`, and `SUPPORT_MATRIX.md`. NAT is the default; bridged networking and physical disk grants are disabled in this release. VirtioFS sharing and guest data exchange require explicit opt-in and remain evaluation features. The file exchange is not a privileged management protocol; no inbound command execution is implemented. Full macOS validation remains outstanding.
