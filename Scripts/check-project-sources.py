#!/usr/bin/env python3
"""Portable structural cross-check; NOT an Xcode compilation."""
from pathlib import Path
import sys, re, subprocess, json
try:
    import yaml
except ImportError as exc:
    raise SystemExit('PyYAML is required to validate project.yml') from exc
root = Path(__file__).resolve().parents[1]
project = yaml.safe_load((root/'project.yml').read_text())
app_source_names = {p.name for p in (root/'App').glob('*.swift')}
core_excludes = set(project['targets']['MacOnMac']['sources'][1].get('excludes', []))
app_source_names |= {p.name for p in (root/'Core').glob('*.swift') if p.name not in core_excludes}
daemon_files = {p.relative_to(root).as_posix() for p in (root/'Privileged/VolumeBootRawDiskDaemon').glob('*.swift')}
explicit = {s['path'] for s in project['targets']['MacOnMacRawDiskDaemon']['sources']}
daemon_excludes = {'Privileged/VolumeBootRawDiskDaemon/TrustedDiskProbe.swift'}
assert daemon_files - daemon_excludes <= explicit, f'daemon sources omitted: {daemon_files - daemon_excludes - explicit}'
assert not daemon_excludes & explicit, 'raw-device probe must stay out of the production daemon target'
assert 'PhysicalDiskAccess.swift' in core_excludes and 'ReadOnlyGrantPolicy.swift' in core_excludes
assert 'Core/PhysicalDiskAccess.swift' not in explicit and 'Core/ReadOnlyGrantPolicy.swift' not in explicit, 'raw opener and grant policy must stay out of the production daemon target'
assert 'Core/PhysicalDiskTopologyProof.swift' in explicit
pbx_path = root/'MacOnMac.xcodeproj/project.pbxproj'
pbx = pbx_path.read_text()
assert not re.search(r'(?m)^\s*(?:<{7}|={7}|>{7}|\|{7})(?:\s|$)', pbx), 'pbx contains source control conflict markers'
assert not re.search(r'\(\s*,\s*\)', pbx), 'pbx contains an invalid empty array; use ()'
if sys.platform == 'darwin':
    # Filename presence alone cannot detect a malformed OpenStep property list.
    parsed = subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(pbx_path)], capture_output=True, text=True)
    assert parsed.returncode == 0, f'pbx property list invalid: {parsed.stderr or parsed.stdout}'
    document = json.loads(parsed.stdout)
    objects = document['objects']
    assert objects[document['rootObject']]['isa'] == 'PBXProject'
    for identifier, obj in objects.items():
        references = []
        for key in ('children', 'files', 'buildPhases', 'buildConfigurations', 'dependencies', 'targets'):
            references.extend(obj.get(key, []))
        for key in ('fileRef', 'target', 'targetProxy', 'buildConfigurationList', 'mainGroup', 'productRefGroup', 'productReference', 'containerPortal'):
            if key in obj: references.append(obj[key])
        for reference in references:
            assert reference in objects, f'pbx {identifier} refers to missing object {reference}'
    app_target = next(obj for obj in objects.values() if obj.get('isa') == 'PBXNativeTarget' and obj.get('name') == 'MacOnMac')
    source_refs = set()
    for phase_id in app_target['buildPhases']:
        phase = objects[phase_id]
        if phase['isa'] == 'PBXSourcesBuildPhase':
            source_refs.update(objects[objects[file_id]['fileRef']]['path'] for file_id in phase['files'])
    assert app_source_names <= source_refs, f'app sources missing from compile phase: {app_source_names - source_refs}'
    print('Xcode property list and object graph checks PASS')
for name in app_source_names | {Path(p).name for p in daemon_files - daemon_excludes}:
    assert re.search(r'path = (?:"' + re.escape(name) + r'"|' + re.escape(name) + r');', pbx), f'pbx missing {name}'
assert 'MacOnMacRawDiskDaemon' in pbx
assert 'MacOnMacDiskBroker' in pbx
print(f'Xcode source reference checks PASS: {len(app_source_names)} app files; {len(daemon_files)} daemon files')
