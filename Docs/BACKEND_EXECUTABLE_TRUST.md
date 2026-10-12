# Windows backend executable trust

Windows ARM workspaces use host executables, so a manifest path is an executable request from the workspace author. Importing or discovering a VM never approves or runs those paths.

Before provisioning a Windows workspace or starting an imported Windows VM, MacOnMac resolves each QEMU and swtpm path to an absolute canonical path, requires a regular executable Mach-O file, and computes its SHA-256. If that exact path and digest have not been approved, the app pauses and shows the executable kind, full path, and digest. The user can trust that exact file for future launches, allow it once in the current app session, or cancel. This prompt is shown separately for QEMU and swtpm. A different path or changed file contents requires a new decision.

Persistent approvals are stored per user in `~/Library/Application Support/MacOnMac/BackendExecutableTrust.json`; the directory is restricted to the account and the file is written with private permissions. Workspace manifests never carry approvals. A malformed or insecure trust store fails closed. “Allow once” is kept in memory and is lost when MacOnMac exits.

After approval, and before each launch, MacOnMac rechecks the path and digest. It then runs the approved QEMU with `--version` and requires a parseable version of at least 9.2, runs the approved swtpm with `--version` and requires a parseable swtpm version response, and requires the workspace machine type `virt-9.2`. Version probes have a five-second timeout and bounded captured output. The app repeats approval-pin checks immediately before starting each child process.

This policy is an explicit local-user trust decision for a host executable. It does not establish that an executable is publisher-signed or safe, and it does not defend against an attacker who can modify the logged-in user's files or race that same user's process. Enterprise deployment should distribute managed, signed backend binaries and control their installation paths. Replacing a binary changes its digest and prompts again.
