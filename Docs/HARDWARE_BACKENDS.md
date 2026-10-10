# VolumeBoot — Hardware Attachment Backends

Specification v0.1.0 · 2026-10-07

## Capability hierarchy
`diskImage`: supported primary macOS boot storage. `physicalBlockDevice`: documented virtual block attachment, gated by broker. `usbPassthrough`: API availability/guest compatibility gated and experimental. `pcieController`: research only, NO assumed public passthrough implementation.

## Interface (design)
`probe(host, device) -> CapabilityResult`, `preflight(device, mode) -> Findings`, `attach(lease, vmConfiguration) -> Attachment`, `detach(owner)`; keep capability differences visible.

## USB passthrough
Evaluate documented beta `VZUSBPassthroughDeviceConfiguration` and its required USB capture/accessory types under installed macOS 27 SDK. Capturing USB hardware does not prove firmware/bootloader USB boot support; never auto-capture keyboard, host boot drives, or devices in active use.

## Physical PCIe/NVMe
`VZNVMExpressControllerDeviceConfiguration` is a virtual device and must not be advertised as direct NVMe hardware assignment. Hypervisor.framework alone does not confer a public general PCIe/IOMMU assignment API. Treat full PCIe passthrough as unsupported unless verified.

## Test matrix
Per backend: API availability, device capture, host access exclusion, disconnect, suspend/resume, data checksums, guest recognition, boot attempts on expendable clones.


## Cross-cutting rules
- No writes to host-mounted storage from a guest.
- Do not confuse block-device attachment with boot compatibility.
- Treat disk identity and platform configuration as untrusted until independently verified.
- Each API must expose typed errors, useful diagnostics and deterministic test seams.
- Experimental features remain disabled in production builds until their release gates pass.

## Status in v0.1.0 scaffold
This is a specification, not a claim of implemented production functionality. The implementation status appears in `IMPLEMENTATION_MATRIX.md`.
