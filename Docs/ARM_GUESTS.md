# ARM Linux and Windows ARM

Select the guest operating system in **Virtual machines → Overview**. Use an Apple Silicon host, a new destination folder, an ARM64/AArch64 installer ISO, at least 4 GiB RAM, and a boot image of at least 64 GiB. The app checks that media is a local regular ISO file with a sector-aligned length; it cannot infer the architecture or completeness of its contents. Supply installation media yourself.

Choose **Create and start installer**, complete setup inside the guest, and shut down the guest. **Shut down** requests guest shutdown; **More VM actions → Force stop** powers off immediately if the guest cannot respond. Native shutdown and QEMU exit release the session automatically. Then choose **Finish installation and eject ISO** and confirm completion. This records your acknowledgement and removes installation media from subsequent boots. **Start** then boots the selected disk. Until completion is acknowledged, an ISO remains attached and the installer can be started again. Existing destination folders are refused; failed provisioning retains its folder and error in `manifest.json`.

For a stopped existing ARM VM, use **Overview → Installation media → Save media settings** after choosing a replacement ISO or executable path. Clear the optional Windows driver ISO field and save to detach it. An incomplete installation must retain an accessible installer ISO. Firmware templates apply only to creation; existing firmware/TPM state is preserved.

## ARM Linux

Linux uses Apple's generic platform, persistent EFI variables and machine identifier, VirtIO storage/graphics/network, and USB input. This follows Apple's [GUI Linux virtualization configuration](https://developer.apple.com/documentation/virtualization/running-gui-linux-in-a-virtual-machine-on-a-mac). Choose an EFI-capable AArch64 distribution with VirtIO drivers.

NAT, disconnected networking, and the existing optional bridged configuration are available. If you enable a host workspace share, mount the `volumeboot` VirtIO filesystem in Linux, for example:

```sh
sudo mkdir -p /mnt/volumeboot
sudo mount -t virtiofs volumeboot /mnt/volumeboot
```

The shared directory appears as `Workspace` under that mount. The bundled guest companion tools run in macOS; Linux can use the workspace files directly. Mouse capture/release buttons and the configurable release hotkey are available in the in-app console.

## Windows ARM

Windows uses an installed `qemu-system-aarch64` (9.2 or newer) and `swtpm`. Homebrew paths are detected automatically; **Windows backend** allows overrides for executables and UEFI firmware. Imported workspace paths are untrusted until the app presents an approval prompt showing the canonical path and SHA-256; approval pins those exact contents, and changed files require approval again. QEMU is version-checked before launch. See [backend executable trust](BACKEND_EXECUTABLE_TRUST.md) for details. Use the matching `edk2-aarch64-code.fd` and `edk2-arm-vars.fd` distributed with QEMU. These files are copied into the VM folder at creation. QEMU provides the [ARM virt platform](https://www.qemu.org/docs/master/system/arm/virt.html) and [macOS HVF acceleration](https://www.qemu.org/docs/master/system/introduction.html); swtpm supplies [TPM 2.0](https://www.qemu.org/docs/master/specs/tpm.html).

The saved platform is `virt-9.2`, with GICv3, ACPI, NVMe boot storage, USB installer media/keyboard/pointer, a framebuffer display, and persistent firmware/TPM state. Networking supports NAT or disconnected mode. For NAT, supply an optional driver ISO containing ARM64 VirtIO network drivers and install the matching driver in Windows setup or afterward. Boot storage uses NVMe to avoid requiring a VirtIO storage driver during installation. Driver media remains available after the installer ISO is ejected.

Windows opens a separate QEMU Cocoa window. **Control + Option + G** toggles capture there. The app shows this shortcut and disables input/display preferences that apply only to its embedded Apple console. **Shut down** sends an ACPI power-down request. **Force stop** ends QEMU through QMP and waits for both QEMU and swtpm before releasing image locks. Quitting the app asks before stopping an active session. Startup errors include the relevant log tail; `qemu.log` and `tpm.log` are retained in the VM folder.

Workspace sharing, the macOS guest companion, microphone input, and experimental physical disk attachment are unavailable for this Windows backend. CPU/RAM, audio output, raw boot disk selection, writable/read-only secondary images, and image management are supported. Retain the original VM folder, including `firmware-vars.fd` and `tpm`, when moving or loading an installed Windows disk.

## Validation

`Scripts/test-arm-guests.sh` validates legacy manifests, media checks, guest metadata, installation state transitions, native Linux EFI startup/shutdown, Windows QEMU configuration, live QEMU/swtpm startup with TCG and HVF, disk leases, and ISO ejection. It signs the test executable with the virtualization entitlement. QEMU and swtpm must be installed for this suite.

The test ISO is synthetic: these checks verify configuration and backend lifecycle, not a complete Windows/Linux installation. Full installation, guest drivers, display interaction, and macOS IPSW installation require real media and manual validation. No installer images or guest operating systems are bundled.
