# Operational diagnostics

`Diagnostics` keeps at most 500 timestamped events for provisioning, startup, shutdown, backend, and daemon failures. Events are redacted before storage: the current user's home path and pairing-key filenames are replaced, and secrets must never be passed to the logger.

Support export is user-controlled through `Diagnostics.export(to:)`; it writes a bounded JSON file to the selected destination and does not upload or retain the bundle elsewhere. VM disk contents, pairing secrets, clipboard text, and guest file contents are not exported.
