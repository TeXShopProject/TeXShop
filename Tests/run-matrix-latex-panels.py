#!/usr/bin/env python3
"""The Matrix and LaTeX panels in every language, loaded offscreen with their own controllers and the
application's factory defaults (MatrixLaTeXPanels.m): what their buttons insert is unchanged, the Matrix
panel numbers its rows without a ruler, starts them below the header and makes Insert the default button,
and the LaTeX panel shows its groups with segmented controls and draws its symbols in the color of text.
Their layout in every language is checked by run-interface-label-fit.py."""
from pathlib import Path
import subprocess, sys, tempfile
from source_tree import include_args
from panel_sources import DEFINE, panel_controller_sources, panel_environment
root = Path(__file__).resolve().parents[1]
interfaces = root / 'Resources/Interfaces'


def loaded(folder):
    # The application loads keyedobjects-101300.nib where it exists.
    newer = folder / 'keyedobjects-101300.nib'
    return newer if newer.exists() else folder / 'keyedobjects.nib'


entries = [f'{lproj.stem}|{loaded(lproj / "matrixpanel.nib")}|{loaded(lproj / "completionpanel1.2.nib")}'
           for lproj in sorted(interfaces.glob('*.lproj')) if (lproj / 'matrixpanel.nib').exists()]
assert len(entries) == 12, entries
with tempfile.TemporaryDirectory(prefix='texshop-panels-') as tmp:
    tmp = Path(tmp)
    binary = tmp / 'MatrixLaTeXPanels'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', DEFINE, '-I', str(root / 'Tests'), *include_args(root),
                    str(root / 'Tests/MatrixLaTeXPanels.m'), *panel_controller_sources(root), '-o', str(binary)], check=True)
    result = subprocess.run([str(binary), *entries], capture_output=True, text=True, timeout=600, env=panel_environment(root, tmp / 'home'))
    print(result.stdout, end='')
    if result.returncode and not result.stdout.strip():
        print(result.stderr[-3000:], file=sys.stderr)
    sys.exit(result.returncode)
