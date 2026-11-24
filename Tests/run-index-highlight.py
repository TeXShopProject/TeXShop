#!/usr/bin/env python3
"""Source > Highlight Index Entries and Settings > Editor > Highlight Index Entries by Default.

Index highlighting colors the arguments of \\index and \\esindex. It is turned on and off for one document in
the Source menu, next to Highlight expl3 Code; the switch in the Syntax Highlighting group of the Editor
settings (the setting IndexColorStart) is the state a document opens with. The toolbar items ColorIndex and
ColorIndexSplit, and the check boxes of TSDocument.nib behind them, are gone.

The checks:
- the menu item in the MainMenu of all 12 languages, right after Highlight expl3 Code, and the compiled nibs
  built from the same XML; the Settings row, its strings and the search entry;
- the production methods toggleIndexColor:, its menu validation and indexColorState, run on two documents:
  each has its own state, the menu shows the state of the document that validates it, a toggle colors the
  source again only while syntax highlighting is on, and a document opens with IndexColorStart;
- the production action of the Settings switch writes IndexColorStart and asks for the recolor effect, which the
  macro editor and the Advanced Find fields follow;
- nothing is left of the toolbar items, the nib check boxes, their strings or the hidden-setting documentation.
Three mutations of the production source must be noticed."""
from pathlib import Path
import json, plistlib, re, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
from source_tree import include_args, source_file

R = Path(__file__).resolve().parents[1]
UI = R / 'Resources/Interfaces'
LANGS = ['Base', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt-PT', 'pt', 'ro', 'zh_CN']
MENU = {'Base': 'Highlight Index Entries', 'de': 'Indexeinträge hervorheben', 'es': 'Resaltar las entradas del índice',
        'fr': "Surligner les entrées d'index", 'it': "Evidenzia le voci dell'indice", 'ja': '索引をハイライト',
        'ko': '색인 항목 하이라이트', 'nl': 'Indexitems markeren', 'pt-PT': 'Destacar as entradas do índice',
        'pt': 'Destacar as entradas do índice', 'ro': 'Evidențiază intrările de index', 'zh_CN': '高亮索引条目'}
SETTING = {'Base': 'Highlight Index Entries by Default', 'de': 'Indexeinträge standardmäßig hervorheben',
           'es': 'Resaltar las entradas del índice por omisión', 'fr': "Surligner les entrées d'index par défaut",
           'it': "Evidenzia le voci dell'indice di default", 'ja': '索引を既定でハイライト', 'ko': '기본으로 색인 항목 하이라이트',
           'nl': 'Indexitems standaard markeren', 'pt-PT': 'Destacar as entradas do índice por predefinição',
           'pt': 'Destacar as entradas do índice por padrão', 'ro': 'Evidențiază intrările de index implicit',
           'zh_CN': '默认高亮索引条目'}
# The label of the former toolbar item in each language.
FORMER = {'Base': 'Color Index', 'de': 'Farbindex', 'es': 'Colorear índice', 'fr': 'Index des couleurs', 'it': 'Colora indice',
          'ja': '索引の色づけ', 'ko': '색인 색상', 'nl': 'Kleurindex', 'pt-PT': 'Colorir índice', 'pt': 'Índice de cores',
          'ro': 'Index de culori', 'zh_CN': '索引着色'}
failures = []


def check(ok, message):
    print(('PASS: ' if ok else 'FAIL: ') + message)
    if not ok:
        failures.append(message)


def read(path):
    return Path(path).read_text(encoding='utf-8')


def strings(path):
    out = subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(path)], capture_output=True, text=True, check=True).stdout
    return json.loads(out)


# The menu item.
for lang in LANGS:
    tree = ET.parse(UI / f'{lang}.lproj/MainMenu.nib/designable.nib')
    found = None
    for menu in tree.iter('items'):
        items = menu.findall('menuItem')
        for i, item in enumerate(items):
            if item.get('identifier') == 'TSShortcut.toggleExplColor:.0':
                found = (items, i)
    check(found is not None, f'{lang}: Source has Highlight expl3 Code')
    if not found:
        continue
    items, i = found
    nxt = items[i + 1] if i + 1 < len(items) else None
    action = nxt.find('connections/action') if nxt is not None else None
    check(nxt is not None and nxt.get('identifier') == 'TSShortcut.toggleIndexColor:.0' and action is not None
          and action.get('selector') == 'toggleIndexColor:' and action.get('target') == '-1'
          and not nxt.get('keyEquivalent') and nxt.get('title') == MENU[lang],
          f'{lang}: "{MENU[lang]}" follows Highlight expl3 Code, sends toggleIndexColor: to the first responder, no key')
    check(sum(1 for a in tree.iter('action') if a.get('selector') == 'toggleIndexColor:') == 1, f'{lang}: one item sends toggleIndexColor:')

# The compiled nibs are built from this XML (TSDocument and MainMenu compile byte for byte the same).
with tempfile.TemporaryDirectory(prefix='index-highlight-nibs-') as td:
    for name in ('MainMenu', 'TSDocument'):
        for lang in LANGS:
            folder = UI / f'{lang}.lproj/{name}.nib'
            xib = Path(td) / 'input.xib'; out = Path(td) / f'{name}-{lang}.nib'
            xib.write_bytes((folder / 'designable.nib').read_bytes())
            subprocess.run(['xcrun', 'ibtool', '--compile', str(out), str(xib)], check=True, capture_output=True)
            built = sorted(out.glob('keyedobjects*.nib')) if out.is_dir() else [out]
            same = all((folder / (b.name if out.is_dir() else 'keyedobjects.nib')).read_bytes() == b.read_bytes() for b in built)
            check(same, f'{lang}: the compiled {name}.nib is the one its designable.nib compiles to')

# The check boxes of the document nib and the toolbar items are gone.
for lang in LANGS:
    text = read(UI / f'{lang}.lproj/TSDocument.nib/designable.nib')
    check('indexColor' not in text and 'showIndexColor:' not in text, f'{lang}: TSDocument.nib has no index color check boxes')
controller = read(source_file(R, 'TSToolbarController.m'))
check('ColorIndex' not in controller and 'indexColor' not in controller, 'TSToolbarController makes no ColorIndex items')
for f in sorted(UI.glob('*.lproj/ToolbarItems.strings')):
    check(not any('ColorIndex' in k for k in strings(f)), f'{f.parent.name}: ToolbarItems.strings has no ColorIndex labels')
for f in sorted(UI.glob('*.lproj/Localizable.strings')):
    check('Color Index' not in strings(f), f'{f.parent.name}: Localizable.strings has no "Color Index"')
sources = '\n'.join(read(p) for p in (R / 'Sources').rglob('*') if p.suffix in ('.m', '.h', '.inc'))
check(not re.search(r'flipIndexColor|showIndexColor:|indexColorBox|indexColorSplitBox', sources), 'no source refers to the old toggles or check boxes')

# Settings.
layout = read(source_file(R, 'TSSettingsCatalogLayout.inc'))
start = layout.index('@"id": @"group.editor.3"')
group = layout[start:layout.index('@"id": @"group.', start + 1)]
rows = re.findall(r'@"id": @"(catalog\.editor\.3\.\d)"', group)
check(rows == ['catalog.editor.3.0', 'catalog.editor.3.1', 'catalog.editor.3.3', 'catalog.editor.3.2'],
      'Syntax Highlighting: the new row comes after Highlight expl3 Code by Default: ' + ', '.join(rows))
check(re.search(r'@"id": @"catalog\.editor\.3\.3", @"kind": @"switch", @"title": @"catalog\.editor\.3\.3\.title", @"note": @""[^}]*@"controls": @\[@"settings\.index-highlight-button"\]', group) is not None,
      'the row is a switch with no note, made of settings.index-highlight-button')
check('add(TSSettingsCategoryEditor, @"row.catalog.editor.3.3", @"SettingsCategories", @"catalog.editor.3.3.title", TSSettingsSearchWeightLabel);'
      in read(source_file(R, 'TSSettingsSearchCatalog.inc')), 'Search Settings finds the row')
check('@"settings.index-highlight-button"] kind:TSSettingsRowControls' in read(source_file(R, 'TSSettingsPaneComposition.inc')), 'the pane lays the switch out')
for lang in LANGS:
    table = strings(UI / f'{lang}.lproj/SettingsCategories.strings')
    check(table.get('catalog.editor.3.3.title') == SETTING[lang], f'{lang}: the row reads "{SETTING[lang]}"')
    check(table.get('catalog.editor.3.3.former') == FORMER[lang], f'{lang}: searching for the former tool name "{FORMER[lang]}" finds the row')
check('add(TSSettingsCategoryEditor, @"row.catalog.editor.3.3", @"SettingsCategories", @"catalog.editor.3.3.former", TSSettingsSearchWeightDescription);'
      in read(source_file(R, 'TSSettingsSearchCatalog.inc')), 'Search Settings also knows the former tool name')
xib = ET.parse(UI / 'Base.lproj/SettingsEditor.xib')
button = next((b for b in xib.iter('button') if b.get('identifier') == 'settings.index-highlight-button'), None)
outlet = next((o for o in xib.iter('outlet') if o.get('property') == 'indexColorStartButton'), None)
check(button is not None and button.find('connections/action').get('selector') == 'indexColorStartChanged:'
      and outlet is not None and outlet.get('destination') == button.get('id'), 'SettingsEditor.xib: the switch and its outlet and action')
refresh = read(source_file(R, 'TSSettingsPaneRefresh.inc'))
check('[_indexColorStartButton setState:[defaults boolForKey:IndexColorStartKey] ? NSControlStateValueOn : NSControlStateValueOff];' in refresh,
      'the switch shows IndexColorStart')
effects = read(source_file(R, 'TSPreferenceEffects.h'))
recolor = re.search(r'TSPreferenceNeedsRecolorNotification: @\[([^\]]*)\]', effects).group(1)
check('IndexColorStartKey' in recolor, 'changing IndexColorStart colors the macro editor and the Advanced Find fields again')
check('options.colorsIndex = [SUD boolForKey:IndexColorStartKey];' in read(source_file(R, 'TSMacroEditor.m'))
      and 'options.colorsIndex = [SUD boolForKey:IndexColorStartKey];' in read(source_file(R, 'TSAppDelegate.m')),
      'the macro editor and the Advanced Find fields color index entries by IndexColorStart')
defaults = plistlib.loads((R / 'Resources/Defaults/FactoryDefaults.plist').read_bytes())
check(defaults.get('IndexColorStart') in (False, 'NO'), 'IndexColorStart is off by default')

# Documentation: no longer a hidden setting, and no toolbar tool.
check('IndexColorStart' not in read(R / 'DocumentSources/CommentLinesRevised/CommentLines.tex'), 'the hidden settings document no longer lists IndexColorStart')
manual = read(R / 'DocumentSources/Manual Source/Manual.tex')
check('IndexColorStart' not in manual and 'ColorIndex' not in manual
      and '\\mnu{Source}\\To\\mnu{Highlight Index Entries}' in manual and 'Highlight Index Entries by Default' in manual,
      'the manual describes the menu item and the switch by their names, not the tool or the former hidden setting')
check('ColorIndex' not in read(UI / 'en.lproj/TeXShopHelp/pgs/basic_miscellaneous.htm'), 'the English help has no ColorIndex tool')

# The production methods, on two documents.
document = read(source_file(R, 'TSDocument.m'))
preferences = read(source_file(R, 'TSPreferences.m'))


def method(source, signature):
    start = source.index('\n' + signature) + 1
    end = re.compile(r'\n\}\n').search(source, start)
    return source[start:end.end()]


def validation(source):
    start = source.index('    if ([anItem action] == @selector(toggleIndexColor:))')
    end = source.index(';\n', start) + 1
    return source[start:end]


def opening(source):
    """The lines of windowControllerDidLoadNib that read the per-document coloring settings."""
    m = re.search(r'\n    self\.syntaxColor = \[SUD boolForKey: SyntaxColoringEnabledKey\];\n(?:    .*\n)*?(?=    \[self applyInvisibleCharactersShowing\])', source)
    return m.group(0) if m else ''


HARNESS = r'''
#import <Cocoa/Cocoa.h>
static int failures = 0;
static void Check(BOOL ok, NSString *message) { printf("%s: %s\n", ok ? "PASS" : "FAIL", message.UTF8String); if (!ok) failures++; }
NSString *IndexColorStartKey = @"IndexColorStart", *SyntaxColoringEnabledKey = @"SyntaxColoringEnabled", *expl3SyntaxColoringKey = @"expl3SyntaxColoring";
@interface FakeDefaults : NSObject
@property (strong) NSMutableDictionary *values;
@end
@implementation FakeDefaults
- (instancetype)init { if ((self = [super init])) _values = [NSMutableDictionary dictionary]; return self; }
- (BOOL)boolForKey:(NSString *)key { return [_values[key] boolValue]; }
- (void)setBool:(BOOL)value forKey:(NSString *)key { _values[key] = @(value); }
@end
static FakeDefaults *fake;
#define SUD fake

@interface TSDocument : NSObject {
    @public
    BOOL showIndexColor;
    NSInteger recolors;
}
@property BOOL syntaxColor, useExplColor;
@end
@implementation TSDocument
- (void)reColor:(NSNotification *)notification { recolors++; }
- (void)opened {
@@OPENING@@
}
@@TOGGLE@@
@@STATE@@
- (BOOL)validateMenuItem:(NSMenuItem *)anItem {
@@VALIDATION@@
    return YES;
}
@end

@interface TSPreferences : NSObject { @public NSSet *effects; }
@end
@implementation TSPreferences
- (void)applyEffectsForPreferenceKeys:(NSSet *)keys { effects = keys; }
@@SETTING@@
@end

int main(void) { @autoreleasepool {
    fake = [FakeDefaults new];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Highlight Index Entries" action:@selector(toggleIndexColor:) keyEquivalent:@""];

    [fake setBool:NO forKey:IndexColorStartKey]; [fake setBool:YES forKey:SyntaxColoringEnabledKey];
    TSDocument *a = [TSDocument new]; [a opened];
    [fake setBool:YES forKey:IndexColorStartKey];
    TSDocument *b = [TSDocument new]; [b opened];
    Check(![a indexColorState] && [b indexColorState], @"a document opens with IndexColorStart");

    [a validateMenuItem:item];
    Check(item.state == NSControlStateValueOff, @"the menu shows the state of the active document (off)");
    [b validateMenuItem:item];
    Check(item.state == NSControlStateValueOn, @"the menu shows the state of the active document (on)");

    [a toggleIndexColor:item];
    Check([a indexColorState] && [b indexColorState] && item.state == NSControlStateValueOn && a->recolors == 1,
          @"turning it on for one document colors that document again and leaves the other alone");
    [b toggleIndexColor:item];
    Check([a indexColorState] && ![b indexColorState] && item.state == NSControlStateValueOff && b->recolors == 1,
          @"turning it off for the other document leaves the first alone");
    [a validateMenuItem:item];
    Check(item.state == NSControlStateValueOn, @"back in the first document, the menu shows it on");

    a.syntaxColor = NO;
    [a toggleIndexColor:item];
    Check(![a indexColorState] && a->recolors == 1, @"with syntax highlighting off, the state changes and nothing is colored");

    TSPreferences *settings = [TSPreferences new];
    NSButton *box = [NSButton checkboxWithTitle:@"" target:nil action:nil];
    box.state = NSControlStateValueOn; [settings indexColorStartChanged:box];
    Check([fake boolForKey:IndexColorStartKey] && [settings->effects isEqual:[NSSet setWithObject:IndexColorStartKey]],
          @"the Settings switch turns IndexColorStart on and asks for its effects");
    box.state = NSControlStateValueOff; [settings indexColorStartChanged:box];
    Check(![fake boolForKey:IndexColorStartKey] && [a indexColorState] == NO && [b indexColorState] == NO,
          @"the Settings switch turns IndexColorStart off; open documents keep their own state");
    return failures ? 1 : 0;
}}
'''


def harness_source(doc, prefs):
    return (HARNESS.replace('@@OPENING@@', opening(doc))
            .replace('@@TOGGLE@@', method(doc, '- (IBAction)toggleIndexColor:sender {'))
            .replace('@@STATE@@', method(doc, '- (BOOL)indexColorState'))
            .replace('@@VALIDATION@@', validation(doc))
            .replace('@@SETTING@@', method(prefs, '- (IBAction)indexColorStartChanged:(NSButton *)sender')))


def run_harness(doc, prefs, tmp, name):
    src = Path(tmp) / f'{name}.m'; exe = Path(tmp) / name
    src.write_text(harness_source(doc, prefs))
    built = subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', str(src), '-o', str(exe)], capture_output=True, text=True)
    if built.returncode:
        sys.exit(built.stderr)
    return subprocess.run([str(exe)], capture_output=True, text=True)


check('showIndexColor = [SUD boolForKey: IndexColorStartKey];' in opening(document), 'windowControllerDidLoadNib reads IndexColorStart with the other coloring settings')
MUTATIONS = {
    'the toggle does not color again': (document, '    if (self.syntaxColor)\n        [self reColor:nil];\n}\n\n- (IBAction)toggleSyntaxColorEntry',
                                        '}\n\n- (IBAction)toggleSyntaxColorEntry', 'doc'),
    'the menu shows no state': (document, '        [anItem setState: showIndexColor ? NSControlStateValueOn : NSControlStateValueOff];',
                                '        ;', 'doc'),
    'a document opens with it off': (document, '    showIndexColor = [SUD boolForKey: IndexColorStartKey];\n', '    showIndexColor = NO;\n', 'doc'),
}
with tempfile.TemporaryDirectory(prefix='index-highlight-') as tmp:
    result = run_harness(document, preferences, tmp, 'production')
    print(result.stdout, end='')
    check(result.returncode == 0, 'the production methods behave as above')
    for name, (source, old, new, kind) in MUTATIONS.items():
        assert source.count(old) == 1, name
        mutated = source.replace(old, new)
        r = run_harness(mutated, preferences, tmp, 'mutant')
        check(r.returncode != 0, f'mutation noticed: {name}')

print('FAILED: %d' % len(failures) if failures else 'PASS: index highlighting is a Source menu item with a default in Settings')
sys.exit(1 if failures else 0)
