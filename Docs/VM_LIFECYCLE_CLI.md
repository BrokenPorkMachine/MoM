# VM lifecycle CLI contract

`maconmac-vm` is the administrator-facing contract for inventory and lifecycle automation. Commands emit one JSON object per invocation, use exit `0` for success, `2` for invalid arguments, `3` for a missing VM, `4` for a busy/in-use VM, and `10` for an operation failure. Human-readable output is never mixed into structured output.

Required commands are:

```text
maconmac-vm inventory --root <directory>
maconmac-vm status --vm <directory>
maconmac-vm provision --vm <directory> --restore-image <ipsw> --disk-gib <n>
maconmac-vm start --vm <directory>
maconmac-vm stop --vm <directory>
```

The CLI must use the same workspace lease as the app, refuse a competing owner with exit `4`, never print pairing secrets, and authenticate administrator actions through the invoking user/session. Provisioning and start/stop must report stable fields (`id`, `state`, `path`, `operation`, `error`) and preserve the VM workspace on failure. The current repository has the core lease and registry contracts; packaging this CLI with the signed app and wiring asynchronous Virtualization.framework operations remains a release integration task.
