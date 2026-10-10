# VM Console — v0.3.0

The SwiftUI host embeds `VZVirtualMachineView` using `NSViewRepresentable`. The view retains the live VM object supplied by `VMRuntimeService`. Starting an existing VM is still dependent on correctly provisioned files and Apple's supported virtual Mac boot path. There is no automatic restore-image installation in this release.

## Next work
Implement installation wizard using `VZMacOSRestoreImage` and `VZMacOSInstaller`, persistent metadata writer, first-run VM creation, proper lifecycle reporting, cancellation, recovery, and synchronized VM view state. Validate keyboard focus and VM shutdown in Xcode.
