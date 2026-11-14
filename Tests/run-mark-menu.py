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
# The English help has the section that every language opens.
assert 'name="marks"' in (root / 'Resources/Interfaces/en.lproj/TeXShopHelp/pgs/basic_commandcompletion.htm').read_text(encoding='latin1')
# The interface has these languages; the test checks every one but English.
assert sorted(p.name[:-6] for p in (root / 'Resources/Interfaces').glob('*.lproj') if (p / 'MainMenu.nib').exists()) == sorted(['Base', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN'])
mutations = {
    'every language opens the help book': ('    if ([localization isEqualToString:@"en"])\n        return nil;', '    return nil;', 'Sources/Editor/TSMarkMenu.m'),
    'Korean opens its help book': ('    if ([localization isEqualToString:@"en"])\n        return nil;', '    if ([localization isEqualToString:@"en"] || [localization isEqualToString:@"ko"])\n        return nil;', 'Sources/Editor/TSMarkMenu.m'),
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
        # A bundle with the English help page that How to Use Marks opens in the other languages.
        bundle = tmp / 'Help.bundle'
        pages = bundle / 'Contents/Resources/en.lproj/TeXShopHelp/pgs'
        pages.mkdir(parents=True)
        (pages / 'basic_commandcompletion.htm').write_bytes((root / 'Resources/Interfaces/en.lproj/TeXShopHelp/pgs/basic_commandcompletion.htm').read_bytes())
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
