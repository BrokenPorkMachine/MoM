# Support and maintenance commitments

- Supported release window: the current release and the immediately previous minor release, subject to the host/guest matrix.
- Severity 1: data loss, privilege boundary failure, or an update that prevents VM recovery. Acknowledge within one business day and provide mitigation or hotfix ownership.
- Severity 2: reproducible VM start/stop, backup/restore, or daemon-health failure without data loss. Triage within three business days.
- Severity 3: UI, documentation, or compatibility defect with a workaround. Schedule for the next maintenance release.

Security reports should be sent privately to the project security contact before public disclosure. The maintainer owns compatibility decisions, security fixes, release notes, and hotfix sign-off. Every fix must include a regression test or a documented reason why hardware qualification is required.
