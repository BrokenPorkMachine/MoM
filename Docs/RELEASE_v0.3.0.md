# v0.3.0 — Installation Candidates + Guest Console

* Added conservative APFS System/Data grouping using volume-group UUID (when exposed by diskutil).
* Added installation-candidate browser, with explicit uncertainty.
* Embedded guest display via VZVirtualMachineView for previously provisioned managed VMs.
* Registered previously omitted DiskutilProcess.swift in the checked-in Xcode project.
* Retained the fail-closed physical disk policy. No automated restore installer or existing-install direct boot in this release.

## Validation limits
Swift parser and static/plist checks can run on Linux; a real Xcode compile and macOS 27 hardware test must be completed on a Mac.
