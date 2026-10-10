# VM Registry v0.5.0

VM state is stored at `<bundle>/manifest.json`, atomically written. `VMInstallState` is provisioning/installed/failed. Only installed records are launchable. A failed or interrupted install is **never** implicitly converted to installed. Discovery enumerates manifest-bearing immediate subdirectories of a user-chosen parent directory, without changing their content. No global indexing or destructive repairs are performed. Future: transactional migration, durability/fdatasync, backup manifests and identity consistency checks.
