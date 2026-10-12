# Security review and response process

Security review covers imported VM bundles, malformed manifests and journals, workspace leases, guest-writable exchange data, XPC caller authentication, daemon privilege boundaries, pairing secrets, diagnostics, and concurrent operations. Every release runs malformed-input, interrupted-write, cross-process lease, signed-bundle, and daemon contract tests.

Report vulnerabilities privately to the project security contact with affected version, host/guest configuration, reproduction steps, impact, and any safe evidence. Do not include VM images, pairing keys, clipboard contents, or personal paths. Maintainers acknowledge reports within one business day, assign severity, protect the reporter, and publish a remediation/advisory after a fix is available. Emergency privilege-boundary or data-loss issues may require a release hold and coordinated customer notification.
