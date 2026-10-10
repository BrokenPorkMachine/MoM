# Disk images

Open **Managed VM → Disks** to manage raw `.img` and `.raw` files. Create a sparse image with 1–2048 GiB capacity, load an existing image, grow its capacity, detach it, or permanently delete its file. Boot images require at least 64 GiB. The panel reports both virtual capacity and actual space allocated on the host.

For a new macOS installation, enter a new VM folder path in Overview and select an Apple IPSW. Use the default boot image (`disk.img` in the new folder), or choose/create a boot image in Disks first. **Install macOS** confirms possible data loss before installing into a selected existing image. The installer writes to that image directly; it does not copy it into the VM folder.

To run an installed image, select its original managed VM folder, then choose its boot image if the file moved. The folder must retain the matching `hardware-model.bin`, `machine-id.bin`, `auxiliary-storage`, and installed manifest. A standalone image does not contain the full virtual Mac identity. Click **Start VM** in Overview to boot the saved disk selection.

Disk choices persist automatically for existing managed VMs. `hardware.json` stores an optional absolute `bootDiskPath`; profiles without that field continue using the bundle's `disk.img`. Additional images keep their existing per-image read-only setting. Images are attached using [Apple's disk image attachment API](https://developer.apple.com/documentation/virtualization/vzdiskimagestoragedeviceattachment/init%28url%3Areadonly%3A%29-9qeco).

Stop the VM before changing its disks. An advisory exclusive lock is held on every image throughout startup, installation, and the running session. Other VolumeBoot instances honor these locks. External tools must also respect locks; close any host mounts or other programs using the image before editing it. Device nodes, symbolic links, malformed file lengths, and duplicate attachments are rejected. Creation is exclusive and never overwrites an existing file. Growth and deletion reject multiply hard-linked images.

Growth preserves existing bytes and increases virtual capacity. It does not expand guest partitions or the APFS container: do that inside macOS after restarting. Shrinking is intentionally unavailable because truncation could discard guest data. A boot disk's manifest capacity is updated after growth. Detach leaves the file intact; Delete confirms permanent data loss. Deleting a boot image keeps its missing reference visible until a replacement is chosen.

Run `Scripts/test-disk-images.sh` for sparse creation, growth/data preservation, deletion, locks, duplicate detection, old profile compatibility, release hotkeys, and native VZ attachment compatibility on macOS. The macOS installer and interactive console still require a compatible IPSW and a live guest for manual validation.
