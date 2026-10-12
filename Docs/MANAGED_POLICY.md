# Administrator-managed policy

Administrators may install `/Library/Application Support/MacOnMac/policy.json`. The policy is read before an existing VM starts or a new VM is provisioned. If the file exists but is malformed, startup fails closed. If it is absent, the product's normal per-user settings and release feature gates apply.

Supported controls are `allowedStorageRoots`, `maxCPUCount`, `maxMemoryGiB`, `allowMicrophone`, `allowWritableShares`, `allowGuestTools`, `allowBridgedNetworking`, and `allowedExecutablePaths`. Policy denial is reported as a configuration error; the app does not silently weaken or override it. The file should be root/admin-owned and not writable by ordinary users.
