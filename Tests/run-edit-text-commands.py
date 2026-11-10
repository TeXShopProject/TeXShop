#!/usr/bin/env python3
"""Edit menu text commands: string conversions, the TSTextView command code
(alerts are answered in-process; no window is shown) and every compiled menu."""
from pathlib import Path
import subprocess
import sys
import tempfile
from source_tree import include_args, source_file

root = Path(__file__).resolve().parents[1]
text_view = source_file(root, 'TSTextView.m').read_text(encoding='utf-8')
start = text_view.index('#pragma mark ========Edit Menu Text Commands==========')
end = text_view.index('\n@end', start)
section = '@implementation TSTextView (EditCommands)\n' + text_view[start:end] + '\n@end\n@implementation TSTextView\n'
mutation = sys.argv[1] if len(sys.argv) > 1 else ''
if mutation == 'no-undo-name':
    section = section.replace('[[self undoManager] setActionName:actionName];', '')
elif mutation == 'convert-without-asking':
    section = section.replace('if ([[self string] length] == 0) {', 'if (YES) { [self replaceRange:NSMakeRange(0, [[self string] length]) usingConversion:conversion actionName:actionName];')
elif mutation == 'no-character-info':
    section = section.replace('[weakSelf.document showCharacterInfo:nil];', '')
elif mutation == 'nfd-for-modified-nfd':
    section = section.replace('[s normalizedStringWithModifiedNFD]', '[s decomposedStringWithCanonicalMapping]')
elif mutation == 'exchange-keeps-clipboard':
    section = section.replace('[general setString:replaced forType:NSPasteboardTypeString];', '')
elif mutation == 'exchange-raw-selection':
    section = section.replace('replaced = [selection stringForType:NSPasteboardTypeString];', 'replaced = [[self string] substringWithRange:[self selectedRange]];')
elif mutation:
    raise SystemExit('unknown mutation ' + mutation)
menus = sorted((root / 'Resources/Interfaces').glob('*.lproj/MainMenu.nib/keyedobjects*.nib'))
if len(menus) != 36:
    raise SystemExit('Expected 36 compiled menu variants')
utilities = root / 'Sources/Utilities'
with tempfile.TemporaryDirectory(prefix='texshop-edit-commands-') as tmp:
    (Path(tmp) / 'TSTextViewEditCommands.inc').write_text(section, encoding='utf-8')
    exe = Path(tmp) / 'edit-commands'
    subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', '-I', tmp, '-I', str(root / 'Tests'),
                    *include_args(root), str(root / 'Tests/EditTextCommands.m'),
                    str(utilities / 'NSString-Extras.m'), str(utilities / 'NSString-CharacterConversion.m'),
                    str(utilities / 'NSMutableString-Extras.m'), '-o', str(exe)], check=True)
    result = subprocess.run([str(exe), *map(str, menus)], capture_output=True, text=True, timeout=300)
    print(result.stdout, end='')
    if result.returncode:
        print(result.stderr, end='')
        raise SystemExit(f'FAIL ({mutation or "production"})')
