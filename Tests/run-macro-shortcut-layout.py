#!/usr/bin/env python3
"""Check status layout against all localized macro-editor nibs without showing windows."""
from pathlib import Path
import subprocess, tempfile, sys
root=Path(__file__).resolve().parents[1]
source=(root/'Sources/TSMacroEditor.m').read_text()
body=source[source.index('- (void)installShortcutStatus'):source.index('- (void)collectShortcutCandidates:')]
with tempfile.TemporaryDirectory(prefix='texshop-macro-layout-') as td:
    mutation='--mutations' in sys.argv
    (Path(td)/'MacroStatusLayout.inc').write_text(body)
    binary=Path(td)/'layout'
    subprocess.run(['xcrun','clang','-fobjc-arc','-Wno-incomplete-implementation','-framework','Cocoa','-I',td,'-I',str(root/'Sources'),str(root/'Tests/MacroShortcutLayout.m'),'-o',str(binary)],check=True)
    for path in sorted((root/'Resources/Interfaces').glob('*.lproj/MacroEditor.nib/keyedobjects.nib')):
        args=[str(binary),str(path)]
        if len(sys.argv)>1 and sys.argv[1]!='--mutations' and path.parts[-3] in ('Base.lproj','ja.lproj'):
            args.append(str(Path(sys.argv[1])/f'macro-{path.parts[-3]}.png'))
        subprocess.run(args,check=True)
    if mutation:
        # Reintroduce the faulty frame expansion independently of layout placement.
        broken=body.replace('    if (self.shortcutStatus) return;', '    if (self.shortcutStatus) return; NSRect f=[window frame]; f.size.height+=60; [window setFrame:f display:NO];')
        (Path(td)/'MacroStatusLayout.inc').write_text(broken)
        subprocess.run(['xcrun','clang','-fobjc-arc','-Wno-incomplete-implementation','-framework','Cocoa','-I',td,'-I',str(root/'Sources'),str(root/'Tests/MacroShortcutLayout.m'),'-o',str(binary)],check=True)
        result=subprocess.run([str(binary),str(root/'Resources/Interfaces/Base.lproj/MacroEditor.nib/keyedobjects.nib')],capture_output=True,text=True)
        assert result.returncode and 'FAIL ' in result.stderr, result.stderr
        print('DETECTED: frame growth on reopening:',result.stderr.strip())
