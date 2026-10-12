# Signed capability contract

The release build must derive offered capabilities from the signed artifact, not only from UI configuration. Release checks compare the app entitlements, embedded daemon entitlements, daemon identifier, team identifier, and feature policy before enabling any capability.

Current release decisions:

- NAT networking is available.
- Bridged networking is disabled unless the signed app contains the matching networking entitlement and the release policy enables it.
- Physical disk grants and broad passthrough are disabled regardless of daemon registration.
- A registered daemon is not considered healthy until authenticated XPC health succeeds.

Run `Scripts/check-signed-capabilities.sh <app>` against a signed bundle. A development-signed app may pass structural checks but does not qualify for distribution; Developer ID signing, notarization, and clean-host validation remain mandatory.
