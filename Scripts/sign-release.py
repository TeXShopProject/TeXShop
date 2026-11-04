#!/usr/bin/env python3
"""Terada: sign nested release code inside out with secure timestamps."""
import argparse
from pathlib import Path
import os
import plistlib
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('app', type=Path)
parser.add_argument('--identity', required=True)
args = parser.parse_args()
app = args.app.resolve()
if not (app / 'Contents/Info.plist').is_file():
    parser.error('Expected a built application bundle')
macho = {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xce'}
paths = {app}
for directory, folders, files in os.walk(app, followlinks=False):
    base = Path(directory)
    for name in folders:
        p = base / name
        if not p.is_symlink() and p.suffix in {'.app', '.xpc', '.framework', '.mdimporter'}:
            paths.add(p)
    for name in files:
        p = base / name
        if not p.is_symlink():
            with p.open('rb') as f:
                if f.read(4) in macho:
                    paths.add(p)
# Read existing entitlements before changing any nested signatures.
entitlements = {}
for path in paths:
    result = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(path)], capture_output=True)
    data = result.stdout
    start = data.find(b'<?xml')
    values = plistlib.loads(data[start:]) if start >= 0 else {}
    values.pop('com.apple.security.get-task-allow', None)
    entitlements[path] = values
with tempfile.TemporaryDirectory() as td:
    for path in sorted(paths, key=lambda p: (-len(p.parts), str(p))):
        command = ['codesign', '--force', '--sign', args.identity, '--timestamp', '--options', 'runtime', '--generate-entitlement-der']
        values = entitlements[path]
        if values:
            plist = Path(td) / 'entitlements.plist'
            plist.write_bytes(plistlib.dumps(values))
            command += ['--entitlements', str(plist)]
        command.append(str(path))
        subprocess.run(command, check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print(f'Signed and verified {len(paths)} code objects.')
