# Managed update and rollback contract

This release uses a staged, administrator-controlled update flow. VM workspaces are user data and are never replaced by an application update.

## Update sequence

1. The administrator obtains one signed application package containing the app, embedded XPC service, launch-daemon executable, and daemon registration plist. App and daemon versions must come from the same package.
2. The deployment tool verifies the package signature, bundle identifiers, team identifier, daemon identifier, and the app/daemon compatibility contract before installation.
3. The tool records the currently installed package, version, signing identity, and health result in an administrator-owned deployment record. It stages the new package beside the current package and verifies it before changing the active path.
4. The app is asked to stop active VMs. The update is refused while a VM cannot be stopped cleanly. No VM workspace, disk image, firmware state, auxiliary storage, TPM state, pairing key, or user configuration is deleted or rewritten.
5. The tool replaces the application bundle as one filesystem operation, then registers or replaces the matching launch daemon. It must not mix an old app with a new daemon, or vice versa.
6. Post-update health checks validate code signatures, bundle identifiers, daemon registration/health, app launch, and the VM registry read path. The previous package remains available until these checks pass.

## Failure and rollback

If staging, signature validation, daemon approval, registration, launch, or health checks fail, the tool restores the previous application package and daemon registration from the deployment record. VM workspaces are left untouched. If rollback itself fails, the administrator must keep the VM data in place, stop launching the mismatched app, and use the recorded package to complete recovery.

Rollback is allowed only to a package whose compatibility contract is satisfied. A failed update never performs a schema downgrade automatically. VM metadata migrations must be forward-compatible or have their own tested backup/restore path before deployment.

## Administrator responsibilities

- Keep the application package, deployment record, and previous known-good package until the retention period expires.
- Deploy during a maintenance window and ensure no second administrator is updating the same installation.
- Preserve the per-user VM directories and their permissions; back them up independently before high-risk upgrades.
- Coordinate app and daemon versions as a unit and rerun the signed-package health check after reboot.

The current repository provides the contract and simulation test below; a production updater still requires packaging, notarization, administrator authorization, and fleet-specific deployment integration.
