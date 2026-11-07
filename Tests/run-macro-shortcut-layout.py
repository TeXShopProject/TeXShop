#!/usr/bin/env python3
"""Check status layout against all localized macro-editor nibs without showing windows."""
from pathlib import Path
import subprocess, tempfile, sys
root=Path(__file__).resolve().parents[1]
source=(root/'Sources/TSMacroEditor.m').read_text()
body=source[source.index('- (void)installShortcutStatus'):source.index('- (void)collectShortcutCandidates:')]
with tempfile.TemporaryDirectory(prefix='texshop-macro-layout-') as td:
    (Path(td)/'MacroStatusLayout.inc').write_text(body)
    binary=Path(td)/'layout'
    subprocess.run(['xcrun','clang','-fobjc-arc','-Wno-incomplete-implementation','-framework','Cocoa','-I',td,'-I',str(root/'Sources'),str(root/'Tests/MacroShortcutLayout.m'),'-o',str(binary)],check=True)
    for path in sorted((root/'Resources/Interfaces').glob('*.lproj/MacroEditor.nib/keyedobjects.nib')):
        args=[str(binary),str(path)]
        if len(sys.argv)>1 and path.parts[-3] in ('Base.lproj','ja.lproj'):
            args.append(str(Path(sys.argv[1])/f'macro-{path.parts[-3]}.png'))
        subprocess.run(args,check=True)
