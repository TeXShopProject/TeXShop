#!/usr/bin/env python3
"""The commands of the Advanced Find panel in the Find submenu (Sources/Find/TSAdvancedFindMenu.m).

Builds Tests/AdvancedFindMenu.m with the Find sources and the production shortcut units into a small application
bundle with the 12 languages' AdvancedFind.strings, and runs it on all 36 compiled MainMenu nibs (each in its own
language) and once for the behavior through the menu. Also checks the strings, the launch order in TSAppDelegate and
that the five keys are free in every shipped nib. Nothing is displayed.

--mutations breaks one rule at a time in a copy of the sources and checks that the test notices."""
from pathlib import Path
import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from source_tree import include_args, advanced_find_syntax_sources, source_file
from shortcut_sources import production_source, companion_sources

root = Path(__file__).resolve().parents[1]
LANGUAGES = ['en', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN']
KEYS = ['FindAll', 'SelectAll', 'SetReplaceString', 'Replace', 'ReplaceAndFind', 'ReplaceAll', 'Highlight', 'Unhighlight']
# Find and Replace… of each language's MainMenu (only the Base menu had it before 6.00)
FIND_AND_REPLACE = {'en': 'Find and Replace…', 'de': 'Suchen und ersetzen...', 'es': 'Buscar y reemplazar…', 'fr': 'Rechercher et remplacer...',
                    'it': 'Trova e sostituisci…', 'ja': '検索と置換…', 'ko': '찾기 및 대치...', 'nl': 'Zoek en vervang…', 'pt': 'Buscar e Substituir…',
                    'pt-PT': 'Procurar e substituir…', 'ro': 'Găsiți și înlocuiți…', 'zh_CN': '查找和替换...'}
# The user's names (2026-11-14), those of CotEditor's Japanese Find menu
JAPANESE = {'FindAll': 'すべて検索', 'SelectAll': 'すべての一致を選択', 'SetReplaceString': '選択部分を置換に使用', 'Replace': '置換',
            'ReplaceAndFind': '置換して次を検索', 'ReplaceAll': 'すべて置換', 'Highlight': 'すべてハイライト', 'Unhighlight': 'ハイライトを削除'}

MUTATIONS = {
    'the commands are added for every method': ('TSAdvancedFindMenu.m',
        'BOOL wanted = findMethod == TSFindMethodAdvancedPanel;', 'BOOL wanted = YES;'),
    'switching away leaves the separators': ('TSAdvancedFindMenu.m',
        '        if ([item.representedObject isEqual:TSAddedItemMark])', '        if (!item.separatorItem && [item.representedObject isEqual:TSAddedItemMark])'),
    'Find All has no Shift': ('TSAdvancedFindMenu.m', 'TSCommandItem(TSAdvancedFindActionFindAll, "F", TSShiftCommand)', 'TSCommandItem(TSAdvancedFindActionFindAll, "f", TSCommand)'),
    'Replace and Find has no Option': ('TSAdvancedFindMenu.m', '"g", NSEventModifierFlagOption | TSCommand)', '"g", TSShiftCommand)'),
    'Remove Highlights has no Control': ('TSAdvancedFindMenu.m', '"H", NSEventModifierFlagControl | TSShiftCommand)', '"h", NSEventModifierFlagControl | TSCommand)'),
    'Select All Matches does Replace All': ('TSAdvancedFindMenu.m',
        'TSCommandItem(TSAdvancedFindActionSelectAll, "", 0)', 'TSCommandItem(TSAdvancedFindActionReplaceAll, "", 0)'),
    'the replacing commands come after Multiple Replace': ('TSAdvancedFindMenu.m', '        index = multiple;\n', '        index = multiple + 2;\n'),
    'OgreKit\'s menu gets the commands': ('TSAdvancedFindMenu.m',
        '        if (item.action == @selector(performFindPanelAction:) && item.tag == NSFindPanelActionShowFindPanel)\n            return menu;\n        NSMenu *found = item.submenu ? TSAppKitFindSubmenu',
        '        if ((item.action == @selector(performFindPanelAction:) && item.tag == NSFindPanelActionShowFindPanel) || item.action == NSSelectorFromString(@"showFindPanel:"))\n            return menu;\n        NSMenu *found = item.submenu ? TSAppKitFindSubmenu'),
    'a title reads another key': ('TSAdvancedFindMenu.m', '@"AdvancedFind.Menu.ReplaceAll"', '@"AdvancedFind.ReplaceAll"'),
    'the commands have no identifier': ('TSAdvancedFindMenu.m', '    item.identifier = TSCommandIdentifier(action);\n', ''),
    'switching away takes out the menu\'s own Find and Replace…': ('TSAdvancedFindMenu.m',
        '        if ([item.representedObject isEqual:TSAddedItemMark])', '        if ([item.representedObject isEqual:TSAddedItemMark] || [item.identifier isEqualToString:@"TSShortcut.performTextFinderAction:.12"])'),
}


def strings(language):
    text = (root / 'Resources/Interfaces' / f'{language}.lproj/AdvancedFind.strings').read_text(encoding='utf-8')
    return dict(re.findall(r'^"([^"]+)" = "((?:[^"\\]|\\.)*)";$', text, re.M))


def check_strings():
    english = None
    for language in LANGUAGES:
        table = strings(language)
        titles = {key: table.get(f'AdvancedFind.Menu.{key}', '') for key in KEYS}
        assert all(titles.values()), (language, titles)
        assert len(set(titles.values())) == len(KEYS), (language, 'two commands share a title', titles)
        if language == 'en':
            english = titles
        if language == 'ja':
            assert titles == JAPANESE, titles
        if language not in ('en',):
            assert titles != english, language
    code = (root / 'Sources/Find/TSAdvancedFindMenu.m').read_text(encoding='utf-8')
    for key in KEYS:
        assert f'TSLocalized(@"AdvancedFind.Menu.{key}", @"{english[key]}")' in code, key
    print('PASS: the eight titles in 12 languages, the Japanese of CotEditor, the English in the code')


def check_launch(delegate):
    """The commands join the Find submenu with Multiple Replace, after OgreKit, before the shortcuts are read."""
    start = delegate.index('- (void)applicationDidFinishLaunching:')
    body = delegate[start:delegate.index('\n}\n', start)]
    install = body.find('[TSMultipleReplaceMenu installInMainMenu:')
    follow = body.find('[TSAdvancedFindMenu startFollowingFindMethod];')
    queued = body.rfind('dispatch_async(dispatch_get_main_queue()', 0, install)
    closing = body.find('});', install)
    reading = body.find('startAfterLaunchWithConfiguration:')
    return 0 <= queued < install < follow < closing < reading


def check_nib_keys():
    """In every shipped nib, no item has one of the five keys (IB writes a Shift key as its capital)."""
    wanted = {('F', ''), ('E', ''), ('g', 'option'), ('H', ''), ('H', 'control')}
    paths = sorted((root / 'Resources/Interfaces').glob('*.lproj/*.nib/designable.nib')) + sorted((root / 'Resources/Interfaces').glob('*.lproj/*.xib'))
    for path in paths:
        text = path.read_text(encoding='utf-8')
        for match in re.finditer(r'<menuItem [^>]*keyEquivalent="([^"]*)"[^>]*?(?:/>|>(.*?)</menuItem>)', text, re.S):
            key, body = match.group(1), match.group(2) or ''
            mask = re.search(r'<modifierMask key="keyEquivalentModifierMask"([^/]*)/>', body[:800])
            mods = mask.group(1) if mask else ''
            if mask and 'command="YES"' not in mods:
                continue
            extra = 'option' if 'option="YES"' in mods and 'control="YES"' not in mods else 'control' if 'control="YES"' in mods and 'option="YES"' not in mods else ''
            if 'option="YES"' in mods and 'control="YES"' in mods:
                continue
            shifted = key if key != key.lower() or 'shift="YES"' not in mods else key.upper()
            assert (shifted, extra) not in wanted, (str(path), key, mods)
    print(f'PASS: the five keys are free in {len(paths)} shipped nibs and xibs')


def build(tmp, sources):
    app = tmp / 'Probe.app'
    resources = app / 'Contents/Resources'
    (app / 'Contents/MacOS').mkdir(parents=True)
    for language in LANGUAGES:
        (resources / f'{language}.lproj').mkdir(parents=True)
        for table in ['AdvancedFind.strings', 'AdvancedFindEngine.strings']:
            shutil.copy(root / 'Resources/Interfaces' / f'{language}.lproj' / table, resources / f'{language}.lproj' / table)
    localizations = ''.join(f'<string>{l}</string>' for l in LANGUAGES)
    (app / 'Contents/Info.plist').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.texshop.test.AdvancedFindMenu</string>
<key>CFBundleExecutable</key><string>probe</string><key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string><key>CFBundleLocalizations</key><array>{localizations}</array></dict></plist>''')
    macro = source_file(root, 'TSMacroMenuController.m').read_text(encoding='latin-1')
    (tmp / 'MacroKeyProduction.inc').write_text(macro[macro.index('NSString *getKeyEquivalentFromString('):])
    (tmp / 'TSKeyboardShortcuts.m').write_text(production_source(root))
    probe = app / 'Contents/MacOS/probe'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-mmacosx-version-min=14.6', '-w', '-I', str(tmp), '-I', str(sources),
                    *include_args(root), '-I', str(root / 'Tests'), '-framework', 'Cocoa', '-framework', 'Carbon',
                    str(root / 'Tests/AdvancedFindMenu.m'), *map(str, sorted(sources.glob('*.m'))), *map(str, advanced_find_syntax_sources(root)),
                    *companion_sources(root), '-o', str(probe)], check=True)
    return probe


def copy_sources(tmp):
    sources = tmp / 'sources'
    sources.mkdir()
    for path in (root / 'Sources/Find').glob('*.[mh]'):
        shutil.copy(path, sources / path.name)
    return sources


def run_all(probe, quiet=False):
    """None when everything passed, else what failed."""
    result = subprocess.run([str(probe), 'behavior', '-AppleLanguages', '(en)'], capture_output=True, text=True, timeout=300)
    if not quiet:
        print(result.stdout + result.stderr, end='')
    if result.returncode:
        return 'behavior'
    macros = root / 'Resources/TeXShop/Macros/Macros_Latex.plist'
    nibs = sorted((root / 'Resources/Interfaces').glob('*.lproj/MainMenu.nib/keyedobjects*.nib'))
    assert len(nibs) == 36, len(nibs)
    for nib in nibs:
        lproj = nib.parts[-3][:-len('.lproj')]
        language = 'en' if lproj == 'Base' else lproj
        table = strings(language)
        titles = {key: table[f'AdvancedFind.Menu.{key}'] for key in KEYS}
        titles['FindAndReplace'] = FIND_AND_REPLACE[language]
        result = subprocess.run([str(probe), 'nib', str(nib), str(macros), json.dumps(titles, ensure_ascii=False), '-AppleLanguages', f'({language})'],
                                capture_output=True, text=True, timeout=120)
        if result.returncode:
            if not quiet:
                print(result.stdout + result.stderr, end='')
            return f'{nib.parts[-3]}/{nib.name}'
    if not quiet:
        print(f'PASS: {len(nibs)} compiled MainMenu nibs: order, titles and keys with the Advanced Find panel, the menu unchanged with the '
              'other methods and after switching back, no key twice, no bundled macro key, Settings › Keyboard keeps a changed key')
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mutations', action='store_true')
    args = parser.parse_args()
    check_strings()
    delegate = (root / 'Sources/App/TSAppDelegate.m').read_text(encoding='latin1')
    if not check_launch(delegate):
        sys.exit('FAIL: the commands join the Find submenu with Multiple Replace, before the shortcuts are read')
    moved = delegate.replace('        [TSAdvancedFindMenu startFollowingFindMethod];\n    });', '    });\n        [TSAdvancedFindMenu startFollowingFindMethod];', 1)
    if moved == delegate or check_launch(moved):
        sys.exit('FAIL: the launch check does not notice a call outside the queued block')
    print('PASS: launch order (with Multiple Replace, after OgreKit, before the shortcuts are read)')
    check_nib_keys()
    with tempfile.TemporaryDirectory(prefix='texshop-advanced-find-menu-') as tmp:
        tmp = Path(tmp)
        failed = run_all(build(tmp, copy_sources(tmp)))
        if failed:
            sys.exit(f'FAIL: the Find submenu ({failed})')
        if args.mutations:
            for name, (file, old, new) in MUTATIONS.items():
                with tempfile.TemporaryDirectory(prefix='texshop-advanced-find-menu-mutation-') as mtmp:
                    mtmp = Path(mtmp)
                    sources = copy_sources(mtmp)
                    text = (sources / file).read_text()
                    if text.count(old) != 1:
                        sys.exit(f'FAIL: mutation {name!r} does not apply')
                    (sources / file).write_text(text.replace(old, new))
                    if run_all(build(mtmp, sources), quiet=True) is None:
                        sys.exit(f'FAIL: mutation {name!r} was not detected')
                    print(f'PASS: detected mutation {name!r}')


if __name__ == '__main__':
    main()
