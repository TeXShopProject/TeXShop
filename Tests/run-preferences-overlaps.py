#!/usr/bin/env python3
"""No two controls of the Preferences window overlap or touch, in any localization.

Renders each tab (and the theme tab's inner tabs) of every compiled Preferences.nib,
and the controls around the tabs, offscreen in the light and dark appearances, and
measures what each control actually draws, so controls whose bezel is drawn outside
their frame on current macOS are caught too. Controls must also stay off box titles
and inside their box without being cut off, and their text must fit, whichever item
a popup menu shows. Controls of a kind stacked in a view must line up, and labels
must not start with spaces. Every tab must yield a reasonable number of controls
that draw something, so the check cannot pass by measuring nothing."""
from pathlib import Path
import subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
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
    if controls < 3 or empty * 10 > controls:
        problems.append(f'too few controls measured: {l}')
for l in problems:
    print(l)
if problems:
    raise SystemExit(f'FAIL: {len(problems)} problems')
print(f'PASS: no overlapping, misplaced, misaligned or truncated controls in {len(nibs)} localizations, light and dark')
