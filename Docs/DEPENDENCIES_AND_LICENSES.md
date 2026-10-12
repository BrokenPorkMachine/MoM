# Dependencies and licensing record

The release inventory must be updated whenever a dependency or tool version changes. The current qualification record includes:

| Component | Tested version/source | Distribution gate |
|---|---|---|
| macOS SDK / Xcode | macOS 27 SDK, Xcode 27.1 | Apple SDK terms and signing requirements |
| QEMU | 11.1.2 on the qualification host | Verify project license and configure-time options before redistribution |
| swtpm | 0.10.2 on the qualification host | Verify GPL obligations and source-offer requirements before redistribution |
| Apple Virtualization.framework | macOS 15+ system framework | Apple platform terms |
| Apple firmware / restore images | Supplied by the administrator | Never redistribute without Apple authorization |

This repository does not currently redistribute third-party binaries. A production package must ship a generated SBOM, complete license notices, source-offer records where required, and the exact hashes/build options for QEMU, swtpm, firmware, drivers, and build tools.
