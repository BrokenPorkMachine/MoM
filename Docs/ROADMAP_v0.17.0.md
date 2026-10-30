# v0.17.0 stabilization — qualification gate (first increment)

This branch introduces a **fail-closed, portable, evidence-record validator**.
It does not qualify any currently untested guest and does not change the supported
release matrix. Do not infer production readiness from passing source or synthetic
backend tests.

## Usage

```sh
python3 -m unittest discover -s Tests -p 'QualificationGateTests.py' -v
python3 Scripts/qualify-guest.py /path/to/guest-evidence.json
python3 Scripts/qualify-guest.py --json /path/to/guest-evidence.json
```

Exit code 0 means the operator-supplied record contains all required identity
fields, valid digests, a passing status and a nonempty evidence reference for
each required check. It **does not independently verify** that the reference is
authentic or that the test passed. Release approval requires human review of the
logs, artifacts, hashes, and signed build, ideally on an independent clean host.

## Record format

```json
{
  "schema_version": 1,
  "host_model": "Mac model",
  "host_chip": "Apple chip",
  "host_build": "macOS build",
  "app_commit": "full commit SHA",
  "artifact_sha256": "64 hexadecimal characters",
  "signing_identity": "Team ID and signing certificate",
  "guest_name": "macOS/Linux/Windows",
  "guest_version": "precise guest release",
  "installer_sha256": "64 hexadecimal characters",
  "backend_name": "Virtualization.framework or QEMU/HVF",
  "backend_version": "backend version",
  "checks": {
    "install": {"status": "not_run", "evidence": "reason or log reference"}
  }
}
```

The `checks` object must include **every** name from `CHECKS` in
`Scripts/qualify-guest.py`: install, login, reboot, disk persistence, DHCP,
DNS, outbound network, input, display, audio, graceful shutdown, forced stop,
sleep/wake, interrupted-operation recovery. Each requires `status: pass` and
nonempty `evidence` for qualification. `fail` and `not_run` deliberately
cause a nonzero result. Preserve failed records: do not silently rewrite them.

## Remaining v0.17.0 work

1. Introduce transactional VM operation journaling and deterministic recovery.
2. Test abrupt process exits, stale leases, interrupted provisioning, and disk full.
3. Benchmark and improve resumable macOS IPSW download behavior.
4. Add guest-tools revocation, anti-replay persistence, and hostile-share tests.
5. Integrate the qualification gate into the local release script after producing
   actual signed, notarized guest-install artifacts.
6. Recompute SOURCE_MANIFEST.sha256 from the complete checked-out branch and
   run `Scripts/verify.sh` on macOS. Do not merge without these checks.

Physical device attachment remains disabled. Existing-install boot is unsupported.
