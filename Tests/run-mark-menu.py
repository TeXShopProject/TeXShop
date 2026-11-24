#!/usr/bin/env python3
"""Edit › Mark in every language, and Insert Mark with Note."""
from pathlib import Path
import re, subprocess, sys, tempfile
from source_tree import include_args
root = Path(__file__).resolve().parents[1]
scrap = (root / 'Sources/Editor/ScrapTextView.m').read_text(encoding='utf-8', errors='replace')
start = scrap.index('// As -[TSDocument placeComment:]')
body = scrap[start:scrap.index('\n}\n', start) + 3]
document = (root / 'Sources/Document/TSDocument.m').read_text(encoding='utf-8', errors='replace')
dstart = document.index('- (void) placeComment: (id)sender\n{')
dbody = document[dstart:document.index('\n}\n', dstart) + 3]
# The document and the Experiment source insert marks with notes the same way.
normalize = lambda text: re.sub(r'\s+', ' ', text[text.index('{'):]).replace('[textView ', '[self ').replace(' textView ', ' self ').replace('[[textView ', '[[self ')
assert normalize(dbody) == normalize(body), 'TSDocument and ScrapTextView place marks with notes the same way'
delegate = (root / 'Sources/App/TSAppDelegate.m').read_text(encoding='utf-8', errors='replace')
launch = delegate[delegate.index('- (void)applicationDidFinishLaunching:'):]
assert launch.index('[TSMarkMenu installInMenu:NSApp.mainMenu];') < launch.index('startAfterLaunchWithConfiguration'), 'Marks move before shortcuts read the menus'
# Every help book has the section that How to Use Marks opens in its language.
books = sorted(p.parts[-3][:-6] for p in (root / 'Resources/Interfaces').glob('*.lproj/TeXShopHelp/pgs'))
assert books == sorted(['en', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN']), books
for lang in books:
    page = root / f'Resources/Interfaces/{lang}.lproj/TeXShopHelp/pgs/basic_commandcompletion.htm'
    assert 'name="marks"' in page.read_text(encoding='utf-8'), f'{page.relative_to(root)} has no section marks'
# The help and the manual name the menu as it is now (the history in whatisnew keeps the old names).
former = re.compile(r'Completion/Marks|Completion\}?\s*(?:&#8250;|›|->|→|\\To)\s*(?:\\mnu\{)?Marks|in the Completion submenu|コマンド補完\s*(?:→|＞|>)\s*マーク')
for page in [*root.glob('Resources/Interfaces/*.lproj/TeXShopHelp/pgs/*.htm'), root / 'DocumentSources/Manual Source/Manual.tex']:
    if page.name == 'whatisnew.htm':
        continue
    text = page.read_bytes().decode('utf-8' if 'TeXShopHelp' in page.parts or page.suffix == '.tex' else 'latin1')
    match = former.search(text)
    assert match is None, f'{page.relative_to(root)} names the former menu: {match.group(0) if match else ""}'
# Each help language names the menu as its interface shows it (Localizable.strings "Edit" and "Marks").
import html, json
# The books of fr, it, nl, pt, pt-PT, ro and zh_CN may write the menu with quotes or an arrow, but not in English.
NEW_BOOKS = ('fr', 'it', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN')
# Reported at the end, after the harness and the mutations, so that a book still in translation does not hide them.
wording = []
for lang, pages in {'en': ('basic_commandcompletion', 'configure_hidden'), 'ko': ('basic_commandcompletion', 'configure_hidden'),
                    'ja': ('basic_commandcompletion', 'configure_hidden'), 'de': ('basic_commandcompletion',), 'es': ('basic_commandcompletion',),
                    **{lang: ('basic_commandcompletion',) for lang in NEW_BOOKS}}.items():
    table = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(root / f'Resources/Interfaces/{"Base" if lang == "en" else lang}.lproj/Localizable.strings')]) or b'{}') if lang != 'en' else {}
    edit, marks = table.get('Edit', 'Edit'), table.get('Marks', 'Marks')
    wanted = f'「{edit}」→「{marks}」' if lang == 'ja' else f'{edit} › {marks}'
    for name in pages:
        page = root / f'Resources/Interfaces/{lang}.lproj/TeXShopHelp/pgs/{name}.htm'
        text = html.unescape(page.read_bytes().decode('utf-8'))
        if lang in NEW_BOOKS:
            quoted = lambda name: '[「“"«„]?\\s*' + re.escape(name) + '\\s*[」”"»“]?'
            found = re.search(quoted(edit) + r'\s*(?:›|→|&gt;|>|＞)\s*' + quoted(marks), text) is not None
        else:
            found = wanted in text
        if not found:
            wording.append(f'{page.relative_to(root)} does not name the menu as the interface shows it: {wanted}')
        if lang != 'en' and 'Edit › Marks' in text:
            wording.append(f'{page.relative_to(root)} names the English menu')
# The interface has these languages; the test checks every one but English.
assert sorted(p.name[:-6] for p in (root / 'Resources/Interfaces').glob('*.lproj') if (p / 'MainMenu.nib').exists()) == sorted(['Base', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN'])
mutations = {
    'a language without a book opens the help book': ('    if ([bundle URLForResource:@"basic_commandcompletion" withExtension:@"htm" subdirectory:@"TeXShopHelp/pgs" localization:localization])\n        return nil;', '    return nil;', 'Sources/Editor/TSMarkMenu.m'),
    'only English opens its help book': ('    if ([bundle URLForResource:@"basic_commandcompletion" withExtension:@"htm" subdirectory:@"TeXShopHelp/pgs" localization:localization])\n', '    if ([localization isEqualToString:@"en"])\n', 'Sources/Editor/TSMarkMenu.m'),
    'the page without the section': ('    components.fragment = @"marks";\n', '', 'Sources/Editor/TSMarkMenu.m'),
    'no-help': ('    if (TSItemWithAction(marks, @selector(showMarkHelp:)) == nil) {', '    if (NO) {', 'Sources/Editor/TSMarkMenu.m'),
    'note-ignored': ('NSString *mark = [NSString stringWithFormat:@"%@%@%@", startcommentString, note, endcommentString];', 'NSString *mark = [NSString stringWithFormat:@"%@%@", startcommentString, endcommentString];', 'inc'),
    'no-tooltips': ('        if (tip) item.toolTip = tip;', '', 'Sources/Editor/TSMarkMenu.m'),
}
def run(inc, menu_source):
    with tempfile.TemporaryDirectory(prefix='texshop-mark-menu-') as tmp:
        tmp = Path(tmp)
        (tmp / 'PlaceComment.inc').write_text(inc)
        (tmp / 'TSMarkMenu.m').write_text(menu_source)
        binary = tmp / 'test'
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-I', str(tmp), '-I', str(root / 'Tests'), *include_args(root),
                        str(root / 'Tests/MarkMenu.m'), str(tmp / 'TSMarkMenu.m'), '-o', str(binary)], check=True)
        nibs = sorted(str(p) for p in (root / 'Resources/Interfaces').glob('*.lproj/MainMenu.nib/keyedobjects.nib'))
        assert len(nibs) == 12, nibs
        # A bundle with the page of every help book; How to Use Marks opens the English one in a language without a book.
        bundle = tmp / 'Help.bundle'
        for source in (root / 'Resources/Interfaces').glob('*.lproj/TeXShopHelp/pgs/basic_commandcompletion.htm'):
            pages = bundle / 'Contents/Resources' / source.parts[-4] / 'TeXShopHelp/pgs'
            pages.mkdir(parents=True)
            (pages / 'basic_commandcompletion.htm').write_bytes(source.read_bytes())
        (bundle / 'Contents/Info.plist').write_text('<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.texshop.test.MarkHelp</string><key>CFBundleDevelopmentRegion</key><string>en</string></dict></plist>')
        import os
        return subprocess.run([str(binary), *nibs], capture_output=True, text=True, timeout=300, env=dict(os.environ, MARK_HELP_BUNDLE=str(bundle)))
menu = (root / 'Sources/Editor/TSMarkMenu.m').read_text()
result = run(body, menu); print(result.stdout, end=''); assert result.returncode == 0, result.stderr
if '--mutations' in sys.argv:
    for name, (before, after, where) in mutations.items():
        inc, src = body, menu
        if where == 'inc': assert inc.count(before) == 1; inc = inc.replace(before, after)
        else: assert src.count(before) == 1; src = src.replace(before, after)
        result = run(inc, src)
        assert result.returncode and 'FAIL' in result.stderr, (name, result.stderr[-500:])
        print('DETECTED', name, result.stderr.strip().splitlines()[-1])
assert not wording, '\n'.join(wording)
