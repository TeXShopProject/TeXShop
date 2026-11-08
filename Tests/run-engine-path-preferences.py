#!/usr/bin/env python3
"""Test the actual discovery UI methods with in-memory defaults and controlled results."""
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/TSPreferences.m').read_text(encoding='latin1')
methods = source[source.index('- (void)cancelEnginePathDiscovery'):source.index('- (IBAction)tetexBinPathChanged:')]
# Exercise the production entry guards without loading the entire Preferences nib.
entry = source[source.index('- (IBAction)showPreferences:'):]
entry = entry[:entry.index('    if (![self prepareSettingsWindow])')]
methods += '\n' + entry + '_tetexBinPathField.stringValue = [SUD stringForKey:TetexBinPath]; _gsBinPathField.stringValue = [SUD stringForKey:GSBinPath]; [_prefsWindow makeKeyAndOrderFront:sender];\n}\n'
for nib in (root / 'Resources/Interfaces').glob('*.lproj/Preferences.nib/designable.nib'):
    actions = ET.parse(nib).findall('.//button/connections/action[@selector="discoverEnginePaths:"]')
    assert len(actions) == 1 and actions[0].get('target') == '-2', nib
with tempfile.TemporaryDirectory() as td:
    td = Path(td)
    generated = td / 'PreferencesMethods.h'
    generated.write_text(methods)
    exe = td / 'EnginePathPreferences'
    subprocess.run(['clang', '-fobjc-arc', '-framework', 'Cocoa', '-I', str(td),
                    str(root / 'Tests/EnginePathPreferences.m'), '-o', str(exe)], check=True)
    subprocess.run([str(exe)], check=True, timeout=20)
