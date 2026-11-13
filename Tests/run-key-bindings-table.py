#!/usr/bin/env python3
"""The key binding list in Settings › Keyboard: tokens and their file text, line
breaks and tabs, saving at once, Undo, empty rows, repeated and one-character
input characters, copy and paste, Insert, and moving rows. No window is ordered,
beeps are counted, and key bindings are written to a temporary folder only.

  --mutations   also check that the test finds four deliberate faults"""
from pathlib import Path
import subprocess, sys, tempfile
from source_tree import include_args
root = Path(__file__).resolve().parents[1]
source = root / 'Sources/Settings/TSKeyBindingsController.m'
mutations = {
    'line-break-not-a-token': ('@"#PASTE#", @"\\n", @"\\t", TSKeyBindingMark]', '@"#PASTE#", @"\\t", TSKeyBindingMark]', 'Symbols, line breaks and tabs are tokens'),
    'not-used-at-once': ('    [GlobalData sharedGlobalData].g_autocompletionDictionary = dictionary;\n', '', 'save a real line break and tab, at once'),
    'replacement-character-dropped': ('        } else if (value == nil) {', '        } else if (value == nil && NO) {', 'A pasted U+FFFC without an attachment is saved'),
    'input-not-limited': ('    if (text.length == 0 || [text rangeOfComposedCharacterSequenceAtIndex:0].length == text.length) return;', '    return;', 'Typing in an input character keeps only the new character'),
}
def run(text):
    with tempfile.TemporaryDirectory(prefix='texshop-key-bindings-') as tmp:
        tmp = Path(tmp); controller = tmp / 'TSKeyBindingsController.m'; controller.write_text(text)
        binary = tmp / 'test'
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Werror', '-Wno-deprecated-declarations', '-mmacosx-version-min=14.6', '-DNSBeep=TSTestBeep',
                        '-include', str(root / 'Tests/KeyBindingsBeep.h'), '-framework', 'Cocoa', '-I', str(root / 'Tests'), *include_args(root),
                        str(root / 'Tests/KeyBindingsTable.m'), str(controller), str(root / 'Sources/App/GlobalData.m'), str(root / 'Sources/App/globals.m'), '-o', str(binary)], check=True)
        return subprocess.run([str(binary), str(root / 'Resources/TeXShop/Keyboard/autocompletion.plist')], capture_output=True, text=True, timeout=120)
original = source.read_text()
result = run(original); print(result.stdout, end=''); print(result.stderr, end='', file=sys.stderr)
assert result.returncode == 0, 'key binding list test failed'
if '--mutations' in sys.argv:
    for name, (before, after, expected) in mutations.items():
        assert original.count(before) == 1, name
        result = run(original.replace(before, after))
        assert result.returncode != 0 and expected in result.stderr, (name, result.stderr)
        print('DETECTED', name)
