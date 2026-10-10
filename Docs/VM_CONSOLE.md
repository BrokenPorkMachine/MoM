# VM console

The SwiftUI host embeds `VZVirtualMachineView` using `NSViewRepresentable` and keeps the live VM supplied by `VMRuntimeService`. Provision a guest from a compatible Apple IPSW or select an installed managed VM before starting the console.

Click **Capture mouse** or click the guest console when click capture is enabled. The pointer stays within the console while captured, and keyboard focus moves to the guest. **Release mouse** returns input to the host. Released consoles display the guest but do not forward clicks, scrolling, or keyboard input.

The default release hotkey is **Control + Option + Escape**. In **Managed VM → Hardware → Input**, choose that shortcut, **Control + Command + G**, or **Option + Command + G**, and enable/disable capture on click. Save hardware settings before the next boot. The release shortcut is intercepted on the host before the guest receives it, including when system shortcut capture is enabled.

Input also releases when the app becomes inactive, the console window loses keyboard focus, the VM changes, or the console disappears. Event monitors are removed on teardown. Mouse confinement uses the host's absolute pointer coordinates, preserving compatibility with both the virtual trackpad and USB pointer.
