# VolumeBoot v0.11.0 — Versioned Broker Contract & XPC Resilience

## Implemented
- Versioned, size-bounded JSON diagnostic capability report shared between XPC service and client.
- Protocol compatibility verification and explicit rejection of any unexpected privileged/raw-access capability claims.
- Exactly-once XPC callback completion gate, with timeout and interruption handling.
- Standalone broker protocol regression harness and refreshed documentation.

## Safety boundary
The bundled XPC service is an **unprivileged diagnostic service**. It does NOT install a privileged launch daemon, grant disk access, transfer file descriptors, or boot physical macOS volumes. All physical disk opening remains denied. Never change policy to allow disks without signed daemon deployment, audit-token caller verification, device-topology verification and lease cleanup.

## Next release gates
1. Build/test with the actual macOS 27 SDK and run XPC integration tests.
2. Design and separately review signed launch daemon provisioning with SMAppService.
3. Test caller signing-requirement verification and audit-token identity binding.
4. Test descriptor passing and exclusive disk ownership on disposable storage only.
