#!/usr/bin/env python3
"""Check common panes in all languages without showing windows.

Default: current pane action/tag/string, text fit, containment and stack geometry.
--legacy: historical fixed-tab pixel fixture only; not current product coverage.
Use PANE_DRAWINGS with the default mode for offscreen light/dark captures.
"""
from pathlib import Path
import subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
# The old nibs remain historical fixtures; product geometry is checked on the shared panes.
if '--legacy' not in sys.argv:
    subprocess.run([sys.executable,str(root/'Tests/run-settings-panes.py'),*sys.argv[1:]],check=True)
    raise SystemExit(0)
nibs = sorted(str(p) for p in (root / 'Resources/Interfaces').glob('*.lproj/Preferences.nib'))
with tempfile.TemporaryDirectory() as td:
    exe = Path(td) / 'PreferencesOverlaps'
    subprocess.run(['clang', '-fobjc-arc', '-O2', '-framework', 'Cocoa', str(root / 'Tests/PreferencesOverlaps.m'), '-o', str(exe)], check=True)
    out = subprocess.run([str(exe)] + nibs, check=True, capture_output=True, text=True).stdout
kinds = ('\tOVERLAP', '\tTIGHT', '\tOVER-TITLE', '\tOUT-OF-BOX', '\tTRUNC', '\tCLIPPED', '\tALIGN', '\tLEADING-SPACE', '\tNOISE')
problems = [l for l in out.splitlines() if any(k in l for k in kinds)]
stats = [l for l in out.splitlines() if '\tSTAT ' in l]
# 9 tabs, the theme tab with 2 inner tabs, and the controls around them, in 2 appearances.
expected = len(nibs) * 11 * 2
if len(stats) != expected:
    problems.append(f'checked {len(stats)} tabs, expected {expected}')
for l in stats:
    fields = dict(kv.split('=') for kv in l.split('\tSTAT ')[1].split())
    controls, empty = int(fields['controls']), int(fields['empty'])
    if controls < (2 if '\tbar\t' in l else 3) or empty * 10 > controls:
        problems.append(f'too few controls measured: {l}')
for l in problems:
    print(l)
if problems:
    raise SystemExit(f'FAIL: {len(problems)} problems')
print(f'PASS: no overlapping, misplaced, misaligned or truncated controls in {len(nibs)} localizations, light and dark')
