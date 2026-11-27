#!/usr/bin/env python3
"""The key binding list in Settings › Keyboard: tokens and their file text, line
breaks and tabs, saving at once, Undo, empty rows, repeated and one-character
input characters, copy and paste, Insert, moving rows, striped
rows in light and dark, and the Paste column, which cannot be checked for an
output with a placeholder or a mark. No window is ordered,
beeps are counted, and key bindings are written to a temporary folder only.

  --mutations   also check that the test finds seventeen deliberate faults"""
from pathlib import Path
import subprocess, sys, tempfile
from source_tree import include_args
root = Path(__file__).resolve().parents[1]
source = root / 'Sources/Settings/TSKeyBindingsController.m'
mutations = {
    'line-break-not-a-token': ('@"#PASTE#", @"\\n", @"\\t", TSKeyBindingMark]', '@"#PASTE#", @"\\t", TSKeyBindingMark]', 'Symbols, line breaks and tabs are tokens'),
    'not-used-at-once': ('    [GlobalData sharedGlobalData].g_autocompletionDictionary = dictionary;\n', '', 'save a real line break and tab, at once'),
    'replacement-character-dropped': ('        } else if (value == nil) {', '        } else if (value == nil && NO) {', 'A pasted U+FFFC without an attachment is saved'),
    'rows-not-striped': ('    table.usesAlternatingRowBackgroundColors = YES;', '    table.usesAlternatingRowBackgroundColors = NO;', 'Neighboring rows have different backgrounds'),
    'paste-not-saved': ('    written &= [pasteKeys writeToFile:', '    if (NO) written &= [pasteKeys writeToFile:', 'Checking Paste saves the row at once'),
    'placeholder-box-enabled': ('    box.enabled = pastable;', '    box.enabled = YES;', 'has its box off and dimmed'),
    'check-kept-with-mark': ('        // A placeholder or a mark takes the row off pasted text for good.\n        if (!TSKeyBindingPastable(output)) self.mutablePaste[row] = @NO;\n', '', 'Taking the mark out after saving leaves the row unchecked'),
    'box-not-live': ('[self updatePasteBoxInRow:row output:', '[self class]; if (0) [self updatePasteBoxInRow:row output:', 'Typing #INS# turns the box off at once'),
    'input-column-stretched': ('    key.resizingMask = NSTableColumnUserResizingMask;\n', '', 'The Paste column keeps its width at the right end'),
    'stale-check-taken': ('[paste addObject:@([pasteKeys containsObject:key] && TSKeyBindingPastable(values[i]))];', '[paste addObject:@([pasteKeys containsObject:key])];', 'stays off when the placeholder is gone'),
    'unsaved-change-kept': ('    if ([self save]) return YES;', '    [self save]; return YES;', 'A check that cannot be saved is not shown'),
    'failed-step-dropped': ('            if (redoing) [undo undo]; else [undo redo];\n', '', 'Then one Undo takes back only the last check'),
    'failed-redo-as-undo': ('            if (redoing) [undo undo]; else [undo redo];', '            [undo redo];', 'A Redo that cannot be saved'),
    'selection-moves-on-failure': ('            NSInteger kept = !saved || (NSInteger)other >= row ? row : row - 1;', '            NSInteger kept = (NSInteger)other < row ? row - 1 : row;', 'keeps both rows and the selection'),
    'retried-for-each-step': ('        if (self.keepingFailedStep) return;\n', '', 'An Undo of several changes that cannot be saved is tried once'),
    'box-read-after-editing': ('    BOOL checked = sender.state == NSControlStateValueOn;\n    NSTextField *field = [self editedField];\n    if (field && [self.tableView rowForView:field] == row) [self.tableView.window makeFirstResponder:self.tableView];\n', '    NSTextField *field = [self editedField];\n    if (field && [self.tableView rowForView:field] == row) [self.tableView.window makeFirstResponder:self.tableView];\n    BOOL checked = sender.state == NSControlStateValueOn;\n', 'Checking Paste while the output is edited'),
    'input-not-limited': ('    if (text.length == 0 || [text rangeOfComposedCharacterSequenceAtIndex:0].length == text.length) return;', '    return;', 'Typing in an input character keeps only the new character'),
}
def run(text):
    with tempfile.TemporaryDirectory(prefix='texshop-key-bindings-') as tmp:
        tmp = Path(tmp); controller = tmp / 'TSKeyBindingsController.m'; controller.write_text(text)
        binary = tmp / 'test'
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Werror', '-Wno-deprecated-declarations', '-mmacosx-version-min=14.6', '-DNSBeep=TSTestBeep',
                        '-include', str(root / 'Tests/KeyBindingsBeep.h'), '-framework', 'Cocoa', '-I', str(root / 'Tests'), *include_args(root),
                        str(root / 'Tests/KeyBindingsTable.m'), str(controller), str(root / 'Sources/Editor/TSPlaceholderToken.m'), str(root / 'Sources/App/GlobalData.m'), str(root / 'Sources/App/globals.m'), str(root / 'Sources/Windows/TSListBottomBar.m'), '-o', str(binary)], check=True)
        return subprocess.run([str(binary), str(root / 'Resources/TeXShop/Keyboard/autocompletion.plist')], capture_output=True, text=True, timeout=120)
original = source.read_text()
# The bundled key bindings: ¥ gives a backslash and is checked for pasting; every row checked for
# pasting exists and can be checked (no #SEL#, #INS#, #PASTE# or mark in its output).
import plistlib
keyboard = root / 'Resources/TeXShop/Keyboard'
bundled = plistlib.loads((keyboard / 'autocompletion.plist').read_bytes())
bundled_paste = plistlib.loads((keyboard / 'autocompletionPaste.plist').read_bytes())
assert bundled['\u00a5'] == '\\', 'the bundled \u00a5 row gives a backslash'
assert bundled_paste == ['\u00a5'], 'only the bundled \u00a5 row is checked for pasting'
assert all(k in bundled and not any(x in bundled[k] for x in ('#SEL#', '#INS#', '#PASTE#', '\u2022')) for k in bundled_paste), 'bundled checked rows can be checked'
print('PASS: the bundled \u00a5 row gives a backslash and is checked for pasting')
result = run(original); print(result.stdout, end=''); print(result.stderr, end='', file=sys.stderr)
assert result.returncode == 0, 'key binding list test failed'
if '--mutations' in sys.argv:
    for name, (before, after, expected) in mutations.items():
        assert original.count(before) == 1, name
        result = run(original.replace(before, after))
        assert result.returncode != 0 and expected in result.stderr, (name, result.stderr)
        print('DETECTED', name)
