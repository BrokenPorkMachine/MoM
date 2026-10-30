#!/usr/bin/env python3
"""Fail-closed validation of MacOnMac guest qualification evidence.

Uses only the Python standard library. Evidence is supplied by the operator,
not discovered from source-code tests or synthetic boot smoke tests.
"""
import argparse
import json
import pathlib
import sys

SCHEMA = 1
IDENTITY = ("host_model", "host_chip", "host_build", "app_commit",
            "artifact_sha256", "signing_identity", "guest_name", "guest_version",
            "installer_sha256", "backend_name", "backend_version")
CHECKS = ("install", "login", "reboot", "disk_persistence", "network_dhcp",
          "network_dns", "network_outbound", "input", "display", "audio",
          "graceful_shutdown", "forced_stop", "sleep_wake",
          "interrupted_operation_recovery")
VALID_STATUS = {"pass", "fail", "not_run"}

def validate(record):
    failures = []
    if not isinstance(record, dict):
        return ["Evidence root must be an object"]
    if record.get("schema_version") != SCHEMA:
        failures.append("schema_version must be 1")
    for key in IDENTITY:
        value = record.get(key)
        if not isinstance(value, str) or not value.strip():
            failures.append(f"Missing identity: {key}")
    for key in ("artifact_sha256", "installer_sha256"):
        value = record.get(key)
        if isinstance(value, str) and (len(value) != 64 or
                 any(c not in "0123456789abcdefABCDEF" for c in value)):
            failures.append(f"{key} must be a 64-character SHA-256 hex digest")
    checks = record.get("checks")
    if not isinstance(checks, dict):
        return failures + ["checks must be an object"]
    for key in CHECKS:
        entry = checks.get(key)
        if not isinstance(entry, dict):
            failures.append(f"Missing check: {key}")
            continue
        status = entry.get("status")
        if status not in VALID_STATUS:
            failures.append(f"{key}: invalid status")
        if status != "pass":
            failures.append(f"{key}: not qualified ({status})")
        evidence = entry.get("evidence")
        if not isinstance(evidence, str) or not evidence.strip():
            failures.append(f"{key}: missing evidence reference")
    return failures

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("record", type=pathlib.Path, help="JSON evidence record")
    parser.add_argument("--json", action="store_true", help="Output machine-readable validation")
    args = parser.parse_args(argv)
    try:
        record = json.loads(args.record.read_text(encoding="utf-8"))
        failures = validate(record)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        failures = [f"Unable to read evidence: {exc}"]
    result = {"qualified": not failures, "failures": failures}
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print("QUALIFIED" if not failures else "NOT QUALIFIED")
        for failure in failures:
            print(" - " + failure)
    return 0 if not failures else 1

if __name__ == "__main__":
    sys.exit(main())
