#!/usr/bin/env python3
"""Pasted text gets LF line endings when ConvertLF is on (the default), in every document and in the Experiment
source, and so does the clipboard text of #PASTE# in macros and command completion. The yen signs and backslashes
of a paste change in the Japanese modes in documents, as before, and stay as they are in the Experiment source, as
before. The key bindings checked for pasting apply to a paste in documents and in the Experiment source while key
bindings are on there, not to #PASTE#; rows with a placeholder or a mark never do; Undo takes the whole paste away.

The production paste methods of TSTextView and ScrapTextView, the shared pasteFilteredTextFromPasteboard:type: of
TSTextView.m, the Japanese filters of TSEncodingSupport.m, GlobalData.m and NSMutableString-Extras.m are compiled verbatim with
OgreKit (Tests/PasteLineEndings.m). Paste is the real -[NSTextView paste:], from a private pasteboard that stands
in for the clipboard; preferences stay in memory. Nothing is shown on screen. --mutations breaks each rule and the
test must then fail."""
from pathlib import Path
import os, subprocess, sys, tempfile
from production_fragments import method, verify_embedded
from source_tree import include_args

root = Path(__file__).resolve().parents[1]
text_view = (root / 'Sources/Editor/TSTextView.m').read_text(encoding='utf-8')
scrap = (root / 'Sources/Editor/ScrapTextView.m').read_text(encoding='utf-8')
encodings = (root / 'Sources/App/TSEncodingSupport.m').read_text(encoding='utf-8')
fragments = []


def part(source, signature, label, optional=False):
    if optional and signature not in source:
        return ''
    fragment = method(source, signature)
    fragments.append(('complete method:' + label, source, fragment))
    return fragment


category = part(text_view, '- (BOOL)pasteFilteredTextFromPasteboard:', 'pasteFilteredTextFromPasteboard', optional=True)
document = part(text_view, '- (BOOL)readSelectionFromPasteboard:', 'TSTextView readSelectionFromPasteboard')
experiment = part(scrap, '- (BOOL)readSelectionFromPasteboard:', 'ScrapTextView readSelectionFromPasteboard', optional=True)
filters = encodings[encodings.index('// replace backslashes by yens'):].rstrip() + '\n'
extras = (root / 'Sources/Utilities/NSMutableString-Extras.m').read_text(encoding='utf-8')
global_data = (root / 'Sources/App/GlobalData.m').read_text(encoding='utf-8')
harness = (root / 'Tests/PasteLineEndings.m').read_text(encoding='utf-8')
mutations = {
    'only in the Japanese modes': ('category', 'if (! filter && ! convertLF && bindings.count == 0)', 'if (! filter && bindings.count == 0)'),
    'no LF line endings': ('category', 'if (convertLF)\n\t\tstring =', 'if (NO)\n\t\tstring ='),
    'not in the Experiment': ('experiment', 'if ([self pasteFilteredTextFromPasteboard: pboard type: type japaneseFilter: NO keyBindings: [self.document isDoAutoCompleteEnabled]])\n\t\treturn YES;\n', ''),
    'yen signs in the Experiment': ('experiment', 'japaneseFilter: NO keyBindings:', 'japaneseFilter: YES keyBindings:'),
    'no yen signs in documents': ('document', 'japaneseFilter: YES keyBindings:', 'japaneseFilter: NO keyBindings:'),
    'no key bindings in documents': ('document', 'keyBindings: [self.document isDoAutoCompleteEnabled]]', 'keyBindings: NO]'),
    'key bindings while they are off': ('experiment', 'keyBindings: [self.document isDoAutoCompleteEnabled]]', 'keyBindings: YES]'),
    'key bindings not applied': ('category', 'TSApplyKeyBindings(pasted, bindings)', 'pasted'),
    'key bindings only with other filters': ('category', 'if (! filter && ! convertLF && bindings.count == 0)', 'if (! filter && ! convertLF)'),
    'rows with a placeholder applied': ('globaldata', ' || TSKeyBindingOutputHasPlaceholder(output)) continue;', ') continue;'),
    'marks are not placeholders': ('globaldata', '@"#PASTE#", @"•"]', '@"#PASTE#"]'),
    'inside a character': ('globaldata', 'if (end < length && [text rangeOfComposedCharacterSequenceAtIndex:end].location != end) continue;', ''),
    'not as AppKit pastes': ('category', '\tpaste(self, @selector(readSelectionFromPasteboard:type:), converted, NSPasteboardTypeString);', '\tif ([self shouldChangeTextInRange:self.selectedRange replacementString:string]) { [self replaceCharactersInRange:self.selectedRange withString:string]; [self didChangeText]; }'),
    'no smart paste': ('category', 'NSData *smart = [pboard availableTypeFromArray:@[smartType]] ? [pboard dataForType:smartType] : nil;', 'NSData *smart = nil;'),
    'nothing left is not deleted': ('category', '		if (selected) {', '		if (NO) {'),
    'nothing left deleted by hand': ('category', '			deleteSelection(self, @selector(delete:), nil);', '			NSArray<NSValue *> *ranges = [self selectedRanges]; NSMutableArray *empty = [NSMutableArray array]; while (empty.count < ranges.count) [empty addObject:@""]; if ([self shouldChangeTextInRanges:ranges replacementStrings:empty]) { for (NSInteger i = (NSInteger)ranges.count - 1; i >= 0; i--) [self replaceCharactersInRange:ranges[(NSUInteger)i].rangeValue withString:@""]; [self setSelectedRange:NSMakeRange(ranges.firstObject.rangeValue.location, 0)]; [self didChangeText]; }'),
    'empty clipboard filtered': ('category', '	if (pasted.length == 0)\n		return NO;', '	if (! pasted)\n		return NO;'),
    'high surrogates not found': ('globaldata', 'if (![starts containsIndex:[text characterAtIndex:index]]) { index++; continue; }', 'if (![starts containsIndex:[text characterAtIndex:index]] || CFStringIsSurrogateHighCharacter([text characterAtIndex:index])) { index++; continue; }'),
    'not for #PASTE#': ('extras', '        [clipboard replaceLineEndingsWithLF];\n', ''),
    '#PASTE# without ConvertLF': ('extras', 'if ([NSUserDefaults.standardUserDefaults boolForKey:@"ConvertLF"])', 'if (YES)'),
}


def run(parts, label):
    program = (harness.replace('FILTERS', filters).replace('CATEGORY', parts['category'])
               .replace('DOCUMENT_PASTE', parts['document']).replace('SCRAP_PASTE', parts['experiment']))
    with tempfile.TemporaryDirectory(prefix='texshop-paste-line-endings-') as folder:
        folder = Path(folder)
        (folder / 'test.m').write_text(program, encoding='utf-8')
        (folder / 'NSMutableString-Extras.m').write_text(parts['extras'], encoding='utf-8')
        (folder / 'GlobalData.m').write_text(parts['globaldata'], encoding='utf-8')
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-F', str(root / 'Frameworks'), '-framework', 'OgreKit',
                        '-I', str(root / 'Tests'), *include_args(root), str(folder / 'test.m'), str(folder / 'NSMutableString-Extras.m'), str(folder / 'GlobalData.m'),
                        '-o', str(folder / 'test')], check=True)
        if label == 'production':
            verify_embedded(program, [f for f in fragments])
        return subprocess.run([str(folder / 'test')], capture_output=True, text=True, timeout=120,
                              env=dict(os.environ, DYLD_FRAMEWORK_PATH=str(root / 'Frameworks')))


parts = {'category': category, 'document': document, 'experiment': experiment, 'extras': extras, 'globaldata': global_data}
result = run(parts, 'production')
print(result.stdout, end='')
if result.returncode:
    print(result.stderr, end='')
    raise SystemExit('FAIL: a paste keeps CRLF or CR line endings, or is converted wrongly')
if '--mutations' in sys.argv:
    for name, (where, before, after) in mutations.items():
        changed = dict(parts)
        assert changed[where].count(before) == 1, name
        changed[where] = changed[where].replace(before, after)
        r = run(changed, name)
        assert r.returncode and 'FAIL' in r.stderr, (name, r.stdout, r.stderr)
        print('DETECTED', name, r.stderr.strip().splitlines()[-1])
print('PASS: pastes and #PASTE# get LF line endings with ConvertLF, in documents and in the Experiment source;'
      ' pastes get the key bindings checked for pasting')
