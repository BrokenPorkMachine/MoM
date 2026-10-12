# Product scope decisions

- The runtime supports one active VM session per app instance. Concurrent workloads are not promised; administrators should run separate isolated workspaces and app instances only when each workspace has its own lease.
- Snapshots, cloning, and templates are not offered. No VM UUID, MAC, firmware, TPM, or pairing-key duplication workflow exists.
- Existing physical macOS boot and broad USB/GPU/PCIe/Neural Engine passthrough remain research-only and outside the managed disk-image VM product.
