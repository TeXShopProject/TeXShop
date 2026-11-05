#!/usr/bin/env python3
"""No two controls of the Preferences window overlap or touch, in any localization.

Renders each tab (and the theme tab's inner tabs) of every compiled Preferences.nib
offscreen and measures what each control actually draws, so controls whose bezel is
drawn outside their frame on current macOS are caught too."""
from pathlib import Path
import subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
nibs = sorted(str(p) for p in (root / 'Resources/Interfaces').glob('*.lproj/Preferences.nib'))
with tempfile.TemporaryDirectory() as td:
    exe = Path(td) / 'PreferencesOverlaps'
    subprocess.run(['clang', '-fobjc-arc', '-O2', '-framework', 'Cocoa', str(root / 'Tests/PreferencesOverlaps.m'), '-o', str(exe)], check=True)
    out = subprocess.run([str(exe)] + nibs, check=True, capture_output=True, text=True).stdout
problems = [l for l in out.splitlines() if '\tOVERLAP' in l or '\tTIGHT' in l]
for l in problems:
    print(l)
if problems:
    raise SystemExit(f'FAIL: {len(problems)} overlapping or touching controls')
print(f'PASS: no overlapping controls in {len(nibs)} localizations')
