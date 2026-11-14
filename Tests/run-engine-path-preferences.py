#!/usr/bin/env python3
"""Test the actual discovery UI methods with in-memory defaults and controlled results."""
from pathlib import Path
import subprocess
import tempfile
from production_fragments import verify_embedded
import xml.etree.ElementTree as ET
from source_tree import include_args, source_file

root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/Settings/TSPreferences.m').read_text(encoding='latin1')
methods = source[source.index('- (void)cancelEnginePathDiscovery'):source.index('- (IBAction)tetexBinPathChanged:')]
# Exercise the production entry guards without loading the entire Preferences nib.
entry = source[source.index('- (IBAction)showPreferences:'):]
entry = entry[:entry.index('    if (![self prepareSettingsWindow])')]
discovery=methods
methods += '\n' + entry + '_tetexBinPathField.stringValue = [SUD stringForKey:TetexBinPath]; _gsBinPathField.stringValue = [SUD stringForKey:GSBinPath]; [_prefsWindow makeKeyAndOrderFront:sender];\n}\n'
verify_embedded('\n'+methods,[('engine discovery methods',source,'\n'+discovery),('preference entry guards',source,'\n'+entry)])
for nib in (root / 'Resources/Interfaces').glob('*.lproj/Preferences.nib/designable.nib'):
    actions = ET.parse(nib).findall('.//button/connections/action[@selector="discoverEnginePaths:"]')
    assert len(actions) == 1 and actions[0].get('target') == '-2', nib
with tempfile.TemporaryDirectory() as td:
    td = Path(td)
    generated = td / 'PreferencesMethods.h'
    generated.write_text(methods)
    exe = td / 'EnginePathPreferences'
    subprocess.run(['clang', '-fobjc-arc', '-framework', 'Cocoa', '-I', str(td), *include_args(root),
                    str(root / 'Tests/EnginePathPreferences.m'), str(source_file(root, 'TSPreferenceProfile.m')), str(source_file(root, 'globals.m')),
                    '-o', str(exe)], check=True)
    subprocess.run([str(exe)], check=True, timeout=20)
