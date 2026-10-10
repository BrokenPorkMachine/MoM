#!/usr/bin/env python3
"""Portable structural cross-check; NOT an Xcode compilation."""
from pathlib import Path
import sys
try:
    import yaml
except ImportError as exc:
    raise SystemExit('PyYAML is required to validate project.yml') from exc
root = Path(__file__).resolve().parents[1]
project = yaml.safe_load((root/'project.yml').read_text())
app_source_names = {p.name for f in ('App','Core') for p in (root/f).glob('*.swift')}
daemon_files = {p.relative_to(root).as_posix() for p in (root/'Privileged/VolumeBootRawDiskDaemon').glob('*.swift')}
explicit = {s['path'] for s in project['targets']['VolumeBootRawDiskDaemon']['sources']}
assert daemon_files <= explicit, f'daemon sources omitted: {daemon_files - explicit}'
assert 'Core/PhysicalDiskTopologyProof.swift' in explicit
pbx = (root/'VolumeBoot.xcodeproj/project.pbxproj').read_text()
for name in app_source_names | {Path(p).name for p in daemon_files}:
    assert f'path = "{name}";' in pbx, f'pbx missing {name}'
assert 'VolumeBootRawDiskDaemon' in pbx
assert 'VolumeBootDiskBroker' in pbx
print(f'Xcode source reference checks PASS: {len(app_source_names)} app files; {len(daemon_files)} daemon files')
