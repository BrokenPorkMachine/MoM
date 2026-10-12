# OS media downloads

MacOnMac keeps operating-system media under the user’s control.

- macOS uses `VZMacOSRestoreImage.latestSupported()` to discover the newest restore image Apple reports as supported by the host. The downloaded file is staged beside the requested destination and moved into place only after the download completes.
- If Apple’s restore-image catalogue is unavailable, MacOnMac can open Terminal with Apple’s `softwareupdate --list-full-installers` command or a validated `softwareupdate --fetch-full-installer --full-installer-version …` command. This downloads Apple’s official full installer application to `/Applications`; it is a host installer workflow and is separate from the IPSW required by the Virtualization framework VM installer.
- Ubuntu ARM64 opens Ubuntu’s official server download page so the user can select the current release and accept its terms.
- Windows 11 ARM64 opens Microsoft’s official download page. The user downloads the installer from Microsoft and then selects the local ISO in MacOnMac.

The app does not mirror, redistribute, or silently replace operating-system media. Downloads are user initiated, use HTTPS, and are not included in diagnostics or VM exports.
