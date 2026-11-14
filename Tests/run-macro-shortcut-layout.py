#!/usr/bin/env python3
"""Check status layout against all localized macro-editor nibs without showing windows."""
from pathlib import Path
import subprocess, tempfile, sys
from source_tree import include_args
from macro_editor_sources import write_sources, layout_body, FRAMEWORKS
root=Path(__file__).resolve().parents[1]
body=layout_body(root)
with tempfile.TemporaryDirectory(prefix='texshop-macro-layout-') as td:
    mutation='--mutations' in sys.argv
    extra=write_sources(root,td,'MacroStatusLayout.inc')
    binary=Path(td)/'layout'
    subprocess.run(['xcrun','clang','-fobjc-arc','-Wno-incomplete-implementation','-Wno-deprecated-declarations','-Wno-nullability-completeness',*FRAMEWORKS,'-I',td,'-I',str(root/'Tests'),*include_args(root),str(root/'Tests/MacroShortcutLayout.m'),*extra,'-o',str(binary)],check=True)
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
            'the list turns to the inset style': ('    if (rows.style == NSTableViewStyleAutomatic) rows.style = rows.effectiveStyle;\n', ''),
            'the shortcut field takes typing keys': ('if (binding.key.length != 1 || ![TSShortcutStore isAllowedKey:binding.key modifiers:binding.modifiers]) return NO;', 'if (binding.key.length != 1) return NO;'),
            'the contents overlap the shortcut row': ('    CGFloat gap = MAX(8, NSMinY(contentsFrame) - NSMaxY([keyField frame]));', '    CGFloat gap = MIN(8, NSMinY(contentsFrame) - NSMaxY([keyField frame])) - 12;'),
        }
        field_source=(root/'Sources/Macros/TSMacroShortcutField.m').read_text()
        field_cases={
            'Escape does not end the waiting': ('    if (c == 27 && !flags) {\n        [self endRecording];\n        return YES;\n    }\n', ''),
            '⊗ shows without a shortcut': ('self.clearButton.hidden = !(self.enabled && self.shortcut.length > 0);', 'self.clearButton.hidden = !self.enabled;'),
        }
        for name,(before,after) in [*cases.items(),*(('field: '+k,v) for k,v in field_cases.items())]:
            field_case=name.startswith('field: ')
            text=field_source if field_case else body
            assert text.count(before)==1,name
            (Path(td)/'MacroStatusLayout.inc').write_text(body if field_case else body.replace(before,after))
            mutated=Path(td)/'TSMacroShortcutField.m'
            mutated.write_text(field_source.replace(before,after) if field_case else field_source)
            sources=[str(mutated) if x.endswith('/TSMacroShortcutField.m') else x for x in extra]
            subprocess.run(['xcrun','clang','-fobjc-arc','-Wno-incomplete-implementation','-Wno-deprecated-declarations','-Wno-nullability-completeness',*FRAMEWORKS,'-I',td,'-I',str(root/'Tests'),*include_args(root),str(root/'Tests/MacroShortcutLayout.m'),*sources,'-o',str(binary)],check=True)
            result=subprocess.run([str(binary),str(root/'Resources/Interfaces/Base.lproj/MacroEditor.nib/keyedobjects.nib')],capture_output=True,text=True)
            assert result.returncode and 'FAIL ' in result.stderr,(name,result.stderr)
            print('DETECTED:',name,result.stderr.strip())

        # Removing the Portuguese minimum size must fail the old-small-frame restoration case.
        (Path(td)/'MacroStatusLayout.inc').write_text(body)
        subprocess.run(['xcrun','clang','-fobjc-arc','-Wno-incomplete-implementation','-Wno-deprecated-declarations','-Wno-nullability-completeness',*FRAMEWORKS,'-I',td,'-I',str(root/'Tests'),*include_args(root),str(root/'Tests/MacroShortcutLayout.m'),*extra,'-o',str(binary)],check=True)
        nibSource=(root/'Resources/Interfaces/pt.lproj/MacroEditor.nib/designable.nib').read_text()
        minimum='<string key="NSMinSize">{270, 272}</string>'
        assert nibSource.count(minimum)==1
        altered=Path(td)/'MacroEditor.xib'; altered.write_text(nibSource.replace(minimum,''))
        nib=Path(td)/'MacroEditor.nib'
        subprocess.run(['xcrun','ibtool','--compile',str(nib),str(altered)],check=True,capture_output=True)
        result=subprocess.run([str(binary),str(nib/'keyedobjects.nib')],capture_output=True,text=True)
        assert result.returncode and 'FAIL ' in result.stderr,result.stderr
        print('DETECTED: Portuguese window has no usable minimum size',result.stderr.strip())
