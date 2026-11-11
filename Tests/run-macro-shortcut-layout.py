#!/usr/bin/env python3
"""Check status layout against all localized macro-editor nibs without showing windows."""
from pathlib import Path
import subprocess, tempfile, sys
from source_tree import include_args
root=Path(__file__).resolve().parents[1]
source=(root/'Sources/Macros/TSMacroEditor.m').read_text()
body=source[source.index('- (void)installShortcutStatus'):source.index('- (void)collectShortcutCandidates:')]
with tempfile.TemporaryDirectory(prefix='texshop-macro-layout-') as td:
    mutation='--mutations' in sys.argv
    (Path(td)/'MacroStatusLayout.inc').write_text(body)
    binary=Path(td)/'layout'
    subprocess.run(['xcrun','clang','-fobjc-arc','-Wno-incomplete-implementation','-framework','Cocoa','-I',td,*include_args(root),str(root/'Tests/MacroShortcutLayout.m'),str(root/'Sources/Windows/TSDialogButtonLayout.m'),str(root/'Sources/Editor/TSMarkMenu.m'),'-o',str(binary)],check=True)
    for path in sorted((root/'Resources/Interfaces').glob('*.lproj/MacroEditor.nib/keyedobjects*.nib')):
        args=[str(binary),str(path)]
        if len(sys.argv)>1 and sys.argv[1]!='--mutations' and path.parts[-3] in ('Base.lproj','ja.lproj'):
            args.append(str(Path(sys.argv[1])/f'macro-{path.parts[-3]}.png'))
        subprocess.run(args,check=True)
    if mutation:
        cases={
            'grow window above its saved top edge': ('windowFrame.origin.y -= minimum.height - NSHeight(windowFrame);', ''),
            'frame growth on reopening': ('    if (self.shortcutStatus) return;', '    if (self.shortcutStatus) return; NSRect f=[window frame]; f.size.height+=60; [window setFrame:f display:NO];'),
            'editors extend beyond window': ('frame.origin.y += height; frame.size.height -= height;', 'frame.origin.y += height;'),
            'controls overlap status band': ('} else if (NSMinY(frame) < editorBottom) frame.origin.y += height;', '}'),
            'minimum height excludes status band': ('minimum.height += height;', ''),
            'restored small window stays too small': ('if (NSHeight(windowFrame) < minimum.height)', 'if (NO)'),
        }
        for name,(before,after) in cases.items():
            assert body.count(before)==1
            (Path(td)/'MacroStatusLayout.inc').write_text(body.replace(before,after))
            subprocess.run(['xcrun','clang','-fobjc-arc','-Wno-incomplete-implementation','-framework','Cocoa','-I',td,*include_args(root),str(root/'Tests/MacroShortcutLayout.m'),str(root/'Sources/Windows/TSDialogButtonLayout.m'),str(root/'Sources/Editor/TSMarkMenu.m'),'-o',str(binary)],check=True)
            result=subprocess.run([str(binary),str(root/'Resources/Interfaces/Base.lproj/MacroEditor.nib/keyedobjects.nib')],capture_output=True,text=True)
            assert result.returncode and 'FAIL ' in result.stderr,(name,result.stderr)
            print('DETECTED:',name,result.stderr.strip())

        # Removing the Portuguese minimum size must fail the old-small-frame restoration case.
        (Path(td)/'MacroStatusLayout.inc').write_text(body)
        subprocess.run(['xcrun','clang','-fobjc-arc','-Wno-incomplete-implementation','-framework','Cocoa','-I',td,*include_args(root),str(root/'Tests/MacroShortcutLayout.m'),str(root/'Sources/Windows/TSDialogButtonLayout.m'),str(root/'Sources/Editor/TSMarkMenu.m'),'-o',str(binary)],check=True)
        nibSource=(root/'Resources/Interfaces/pt.lproj/MacroEditor.nib/designable.nib').read_text()
        minimum='<string key="NSMinSize">{270, 272}</string>'
        assert nibSource.count(minimum)==1
        altered=Path(td)/'MacroEditor.xib'; altered.write_text(nibSource.replace(minimum,''))
        nib=Path(td)/'MacroEditor.nib'
        subprocess.run(['xcrun','ibtool','--compile',str(nib),str(altered)],check=True,capture_output=True)
        result=subprocess.run([str(binary),str(nib/'keyedobjects.nib')],capture_output=True,text=True)
        assert result.returncode and 'FAIL ' in result.stderr,result.stderr
        print('DETECTED: Portuguese window has no usable minimum size',result.stderr.strip())
