#!/usr/bin/env python3
"""Help > TeX Live Documentation opens a document in every language.

TeXLiveDocumentation.pdf exists only in some languages. The others (Japanese, German, ...) found
nothing and only beeped; they now open the English document. The action of HelpDocuments.m is
compiled into a probe application whose Resources mirror the localizations of the real bundle
(the PDFs are stand-ins), and the probe runs once per language with -AppleLanguages. No window is
shown. With --mutation NAME the harness runs against a mutated source and must fail; --mutations
runs them all."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
SOURCE = 'Sources/App/HelpDocuments.m'
INTERFACES = root / 'Resources/Interfaces'

MUTATIONS = {
    # No fallback: languages without a copy find nothing again.
    'no-fallback': ('    if (fileName == nil)\n        fileName =', '    if (NO)\n        fileName ='),
    # The fallback opens another translation instead of the English document.
    'french-fallback': ('inDirectory:nil forLocalization:@"en"]', 'inDirectory:nil forLocalization:@"fr"]'),
    # The English document always wins, also where a translation exists.
    'english-always': ('    fileName = [[NSBundle mainBundle] pathForResource:@"TeXLiveDocumentation" ofType:@"pdf"];\n',
                       '    fileName = nil;\n'),
}

PROBE = r'''
#import <Cocoa/Cocoa.h>
@interface HelpDocuments : NSObject
- (void)displayFile:(NSString *)fileName;
- (IBAction)displayTeXLiveDocumentation:sender;
@end
@implementation HelpDocuments
- (void)displayFile:(NSString *)fileName
{
    NSString *where = fileName == nil ? @"(nil)" : [[fileName stringByDeletingLastPathComponent] lastPathComponent];
    printf("%s\t%s\n", [NSBundle.mainBundle.preferredLocalizations.firstObject UTF8String], where.UTF8String);
}
%METHOD%
@end
int main(int argc, const char **argv)
{
    @autoreleasepool {
        [[HelpDocuments new] displayTeXLiveDocumentation:nil];
    }
    return 0;
}
'''

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def run(source_text, work):
    m = re.search(r'^- \(IBAction\)displayTeXLiveDocumentation:sender\s*\{.*?^\}', source_text, re.S | re.M)
    if m is None:
        failures.append('displayTeXLiveDocumentation: not found')
        return
    app = work / 'Probe.app'
    resources = app / 'Contents/Resources'
    (app / 'Contents/MacOS').mkdir(parents=True)
    languages = sorted(p.name for p in INTERFACES.glob('*.lproj'))
    with_copy = sorted(l[:-6] for l in languages if (INTERFACES / l / 'TeXLiveDocumentation.pdf').exists())
    check('en' in with_copy, 'the English document exists')
    check(not (INTERFACES / 'Base.lproj/TeXLiveDocumentation.pdf').exists() and not (root / 'Resources/TeXLiveDocumentation.pdf').exists(),
          'no language-independent copy (the case this test covers)')
    for language in languages:
        (resources / language).mkdir(parents=True)
        if (INTERFACES / language / 'TeXLiveDocumentation.pdf').exists():
            (resources / language / 'TeXLiveDocumentation.pdf').write_bytes(b'%PDF-1.4\n%stand-in\n')
    (app / 'Contents/Info.plist').write_text('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.texshop.texlive-documentation-probe</string>
<key>CFBundleExecutable</key><string>probe</string>
<key>CFBundleDevelopmentRegion</key><string>English</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
''')
    probe = work / 'probe.m'
    probe.write_text(PROBE.replace('%METHOD%', m.group(0)))
    built = subprocess.run(['clang', '-fobjc-arc', '-framework', 'Cocoa', str(probe), '-o', str(app / 'Contents/MacOS/probe')],
                           capture_output=True, text=True)
    if built.returncode != 0:
        failures.append('probe did not compile:\n' + built.stderr[-3000:])
        return
    env = {**os.environ, 'HOME': str(work / 'home'), 'CFFIXED_USER_HOME': str(work / 'home'), 'TMPDIR': str(work) + '/'}
    for language in languages:
        name = language[:-6]
        if name == 'Base':
            continue
        out = subprocess.run([str(app / 'Contents/MacOS/probe'), '-AppleLanguages', f'({name})'],
                             capture_output=True, text=True, timeout=60, env=env)
        line = out.stdout.strip()
        if '\t' not in line:
            failures.append(f'{name}: probe printed {line!r} {out.stderr[-500:]!r}')
            continue
        preferred, opened = line.split('\t')
        check(preferred == name, f'{name}: the probe runs in {name} (got {preferred})')
        if name in with_copy:
            check(opened == f'{name}.lproj', f'{name}: opens its own document (got {opened})')
        elif name.split('-')[0] in with_copy:
            # pt-PT has no copy of its own; macOS falls back to Portuguese.
            check(opened == name.split('-')[0] + '.lproj', f'{name}: opens the document of {name.split("-")[0]} (got {opened})')
        else:
            check(opened == 'en.lproj', f'{name}: opens the English document (got {opened})')


def spelling():
    """TeX Live is written with a space in every text TeXShop shows: menu titles, other interface
    strings and the bundled macros (names and the comments shown in the macro editor)."""
    wrong = re.compile(r'TeXLive(?!Documentation)')
    files = sorted(INTERFACES.glob('*.lproj/*.nib/designable.nib')) + sorted(INTERFACES.glob('*.lproj/*.xib'))
    files += sorted(INTERFACES.glob('*.lproj/*.strings')) + sorted((root / 'Resources/TeXShop/Macros').glob('*.plist'))
    check(len(files) > 50, f'{len(files)} interface and macro files')
    for file in files:
        text = file.read_text(encoding='utf-8', errors='replace')
        for line in text.splitlines():
            # Folder names such as /Applications/TeXLive are paths, not text.
            for m in wrong.finditer(line):
                if line[max(0, m.start() - 1)] == '/' and m.start() > 0:
                    continue
                check(False, f'{file.relative_to(root)}: "TeX Live" without the space: {line.strip()[:120]}')


def main():
    args = sys.argv[1:]
    if args == ['--mutations']:
        bad = []
        for name in MUTATIONS:
            r = subprocess.run([sys.executable, __file__, '--mutation', name], capture_output=True, text=True)
            ok = r.returncode != 0
            print(('PASS: detected' if ok else 'FAIL: missed') + f' mutation {name}: ' + (r.stdout.strip().splitlines() or [''])[0])
            if not ok:
                bad.append(name)
        sys.exit(1 if bad else 0)
    text = (root / SOURCE).read_text()
    if args[:1] == ['--mutation']:
        old, new = MUTATIONS[args[1]]
        if old not in text:
            raise SystemExit(f'mutation {args[1]}: text not found')
        text = text.replace(old, new, 1)
    spelling()
    with tempfile.TemporaryDirectory(prefix='texlive-doc-') as tmp:
        work = Path(tmp)
        (work / 'home').mkdir()
        run(text, work)
    if failures:
        for f in failures:
            print('FAIL:', f)
        sys.exit(1)
    print('PASS: TeX Live Documentation opens a document in every language, the English one where there is no translation')


if __name__ == '__main__':
    main()
