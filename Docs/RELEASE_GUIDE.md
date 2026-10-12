# Current installation and release guide

1. Build the current `MacOnMac.xcodeproj` or use the signed distribution artifact; do not use historical project names.
2. Run `Scripts/verify.sh`, `Scripts/check-source-manifest.sh`, and `Scripts/check-daemon-bundle.sh <signed-app>`.
3. Confirm app/daemon identifiers, team, entitlements, nested signatures, and capability policy. Use [UPDATE_ROLLBACK.md](UPDATE_ROLLBACK.md) for deployment and rollback.
4. Install the app through the administrator's managed deployment system. Request daemon approval explicitly; verify registration and authenticated health.
5. Keep VM workspaces outside the application bundle. Back up stopped VMs before high-risk updates and preserve the previous signed package until health checks pass.
6. For support, export diagnostics only at the user's request and follow [SECURITY_RESPONSE.md](SECURITY_RESPONSE.md).

Historical `RELEASE_v*.md` files are archived release notes and are not installation instructions.
