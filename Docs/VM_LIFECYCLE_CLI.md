# VM lifecycle CLI contract

`maconmac-vm` is the administrator-facing contract for inventory and lifecycle automation. Commands emit one JSON object per invocation, use exit `0` for success, `2` for invalid arguments, `3` for a missing VM, `4` for a busy/in-use VM, and `10` for an operation failure. Human-readable output is never mixed into structured output.

The currently shipped read-only commands are:

```text
maconmac-vm inventory --root <directory>
maconmac-vm status --vm <directory>
```

`inventory`, `status`, `start`, `stop`, and `provision` are exposed by the packaged per-user `MacOnMacVMControl` XPC daemon. The daemon owns one runtime session, uses the same workspace lease as the app, runs in the user's launch-agent bootstrap namespace rather than as root, and returns structured operation results. The standalone CLI currently covers inventory/status; lifecycle calls are made through the per-user app/daemon channel.

The CLI must use the same workspace lease as the app, refuse a competing owner with exit `4`, never print pairing secrets, and authenticate administrator actions through the invoking user/session. Provisioning and start/stop must report stable fields (`id`, `state`, `path`, `operation`, `error`) and preserve the VM workspace on failure. The current repository has the core lease and registry contracts; packaging this CLI with the signed app and wiring asynchronous Virtualization.framework operations remains a release integration task.
