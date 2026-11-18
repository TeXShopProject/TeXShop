#!/usr/bin/env python3
"""Completion and mark keys: the yielding F5 of Edit › Complete Label or Citation Key,
the menu item and its target, Escape and Tab during composition in the source and the
Experiment, and Escape in the Experiment panel. The production shortcut units and
TSMarkMenu.m are compiled as they are; the text view parts are the production
fragments of TSTextView.m and ScrapTextView.m, verified byte for byte. No window is shown.
"""
import argparse, os, subprocess, tempfile
from pathlib import Path
from production_fragments import method, verify_embedded
from shortcut_sources import production_source, companion_sources
from source_tree import include_args, source_file

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['yield-off', 'hold-back', 'swallow-off', 'composition-off', 'escape-pass', 'menu-field-editor', 'record-macro', 'restore-conflict', 'backtab', 'shared-flag', 'control-y', 'nested-drop', 'control-bracket'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
production = production_source(root)
text_view = source_file(root, 'TSTextView.m').read_text(encoding='latin-1')
scrap_view = source_file(root, 'ScrapTextView.m').read_text(encoding='latin-1')
mark_menu = source_file(root, 'TSMarkMenu.m').read_text(encoding='utf-8')
completion_keys = source_file(root, 'TSCompletionKeys.h').read_text(encoding='utf-8')
completion_keys_text = completion_keys

docommand = method(text_view, '- (void)doCommandBySelector:(SEL)selector')
composition = method(text_view, '- (void)keyDown:(NSEvent *)theEvent\n{\n    // During composition')
pass_scrap = method(scrap_view, '- (void)passKeyDown:(NSEvent *)theEvent')
fragments = [('TSTextView doCommandBySelector:', text_view, docommand),
             ('TSTextView composition', text_view, composition),
             ('ScrapTextView passKeyDown:', scrap_view, pass_scrap)]
# The Experiment's keyDown has the same composition block and the same doCommandBySelector:.
assert scrap_view.count(composition) == 1, 'ScrapTextView has the same keyDown:'
assert method(scrap_view, '- (void)doCommandBySelector:(SEL)selector') == docommand, 'both views drop the same commands'
assert '[SUD boolForKey: CommandCompletionAlternateMarkShortcutKey]' in text_view and 'stringForKey: CommandCompletionAlternateMarkShortcutKey' not in text_view
assert '[SUD boolForKey: CommandCompletionAlternateMarkShortcutKey]' in scrap_view and 'stringForKey: CommandCompletionAlternateMarkShortcutKey' not in scrap_view
assert 'NSString *g_commandCompletionCharTab = g_commandCompletionChar;' in scrap_view, 'the Experiment follows the trigger key'
# Shift-Tab (Backtab) is the Tab trigger with Shift in all three comparisons of both views.
live_text = text_view[:text_view.index('/* NEW VERSION')]
def code_lines(text, needle):
    return sum(1 for line in text.splitlines() if needle in line and not line.strip().startswith('//'))
assert code_lines(live_text, '[TSCompletionTypedKey(theEvent) isEqualToString: g_commandCompletionChar] &&') == 3
assert code_lines(live_text, '[[theEvent characters] isEqualToString: g_commandCompletionChar]') == 0
assert code_lines(scrap_view, '[TSCompletionTypedKey(theEvent) isEqualToString: g_commandCompletionCharTab] &&') == 3
assert '(self.selectedRange.length > 2) && editorCanAddBrackets && ![self hasMarkedText]' in text_view, 'no enclosing during composition'

harness = (root / 'Tests/CompletionMarkKeys.m').read_text(encoding='utf-8').replace('#import "TSCompletionKeys.h"', completion_keys)
harness = harness.replace('@@DOCOMMAND_SOURCE@@', docommand).replace('@@KEYDOWN_SOURCE@@', composition).replace('@@PASS_SCRAP@@', pass_scrap)
if not args.mutation:
    verify_embedded(harness, fragments)
def mutate(text, old, new):
    assert text.count(old) == 1, args.mutation
    return text.replace(old, new)
if args.mutation == 'yield-off':
    production = mutate(production, 'return [NSSet setWithObject:@"TSShortcut.completeLabelOrCitationKey:.0"];', 'return [NSSet set];')
elif args.mutation == 'hold-back':
    production = mutate(production, ': [yielding containsObject:command.commandID] ? TSBinding(@"", 0) : TSBinding(command.defaultKey, command.defaultModifiers);', ': TSBinding(command.defaultKey, command.defaultModifiers);')
elif args.mutation == 'swallow-off':
    harness = mutate(harness, '    if (TSCompletionKeyComposingView == self) return;\n', '')
elif args.mutation == 'composition-off':
    harness = mutate(harness, '    if ([self hasMarkedText] && TSIsCompletionFamilyKey(theEvent)) {', '    if (NO) {')
elif args.mutation == 'escape-pass':
    harness = mutate(harness, '        TSIsPlainOrShiftedEscape(theEvent))\n        return;', '        NO)\n        return;')
elif args.mutation == 'record-macro':
    production = mutate(production, ' ?: [self macroNamingKey:key modifiers:flags];', ';')
elif args.mutation == 'restore-conflict':
    production = mutate(production, 'NSString *conflict = [self commandYieldsDefault:command] ? nil : [self conflictForRestoringCommand:command];', 'NSString *conflict = [self conflictForRestoringCommand:command];')
elif args.mutation == 'backtab':
    harness = mutate(harness, 'if (c == 0x09 || c == 0x19) return event.keyCode == kVK_Tab ? @"\\t" : @"";', 'if (c == 0x09) return characters;')
elif args.mutation == 'shared-flag':
    harness = mutate(harness, '    if (TSCompletionKeyComposingView == self) return;\n', '    if (TSCompletionKeyComposingView != nil) return;\n')
elif args.mutation == 'control-y':
    harness = mutate(harness, 'if (c == 0x09 || c == 0x19) return event.keyCode == kVK_Tab ? @"\\t" : @"";', 'if (c == 0x09 || c == 0x19) return @"\\t";')
elif args.mutation == 'control-bracket':
    harness = mutate(harness, 'if (c == 0x1b) return event.keyCode == kVK_Escape ? characters : @"";', 'if (c == 0x1b) return characters;')
elif args.mutation == 'nested-drop':
    harness = mutate(harness, '    if (was == view) TSCompletionKeyComposingView = nil;\n', '')
elif args.mutation == 'menu-field-editor':
    mark_menu = mutate(mark_menu, 'return view.isEditable && !view.isFieldEditor ? view : nil;', 'return view.isEditable ? view : nil;')
with tempfile.TemporaryDirectory(prefix='texshop-completion-keys-') as folder:
    temp = Path(folder)
    (temp / 'TSKeyboardShortcuts.m').write_text(production)
    (temp / 'TSMarkMenu.m').write_text(mark_menu)
    (temp / 'test.m').write_text(harness)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-I', folder, *include_args(root), '-I', str(root / 'Tests'),
                    '-framework', 'Cocoa', '-framework', 'Carbon', str(temp / 'test.m'), str(temp / 'TSMarkMenu.m'),
                    *companion_sources(root), '-o', str(temp / 'test')], check=True)
    (temp / 'home/Library/Preferences').mkdir(parents=True)
    result = subprocess.run([str(temp / 'test')], capture_output=True, text=True, timeout=120,
                            env=dict(os.environ, HOME=str(temp / 'home'), CFFIXED_USER_HOME=str(temp / 'home')))
    if args.mutation:
        assert result.returncode == 1 and 'FAIL:' in result.stderr, result.stdout + result.stderr
        print('PASS: detected', args.mutation)
    elif result.returncode:
        raise SystemExit(result.stdout + result.stderr)
    else:
        print(result.stdout, end='')
