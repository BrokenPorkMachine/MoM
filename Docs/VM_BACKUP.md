# VM backup and restore

MacOnMac backups are versioned directory snapshots created from a stopped VM. A backup contains:

- the complete VM workspace, including `manifest.json`, hardware/connectivity profiles, disk images, firmware, platform identity, auxiliary storage, and TPM state;
- copies of every external boot or additional disk image referenced by the hardware profile; and
- `backup.json`, which records the backup format version, source manifest, and external-disk mapping.

Restore requires a new destination directory. The workspace is copied without changing the manifest UUID, machine identity, firmware, or TPM state. External images are restored beside the VM in `<destination>.external-disks`, and the restored hardware profile points to those copies. Existing destinations, missing backup members, symbolic links in the source workspace, and missing external disks are rejected. The operation removes a partially restored destination on failure.

Backups are local snapshots, not a live-consistency mechanism. Stop the VM and wait for all disk leases and guest processes to be released before creating one. Cross-host restore still requires qualification on the target host and compatible guest/backend versions.
