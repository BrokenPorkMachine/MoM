# MacOnMac — Security Model

Specification v0.1.0 · 2026-10-07

## Threat model
Malicious VM guest, compromised UI, media metadata attacker, device replacement race, faulty USB bridge, local process spoofing helper client, privilege escalation and host/data corruption.

## Boundaries
No root VM process. Disk broker (future) grants narrowly scoped FDs after designated-requirement verification and user consent. Read-only by default, with physically read-only FD. Every step checks actual current storage topology.

## Block rules
Host root backing physical stores never writable. Devices with host-mounted filesystem descendants never writable. Unknown APFS topology blocks writes. No raw media manipulation while guest owns lease. No generic privileged command execution.

## Build and shipment
Entitlement `com.apple.security.virtualization`; verify hardened runtime, signatures and XPC identities on macOS. No privileged broker in initial scaffold. Review direct distribution requirements separately from sandbox/Mac App Store rules.

## Incident response
Terminate guest I/O, release safely, preserve minimal logs, notify user and require explicit re-authorization after device changes. No automatic disk repair.


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
