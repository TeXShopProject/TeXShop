#!/usr/bin/env python3
"""About TeXShop: the credits start with a link to the TeXShop web site (#69).

The standard About panel shows the copyright as plain text, so the web site address moves out of the
copyright into the credits, where it is a link. A probe compiled against Sources/App/TSAboutCredits.h
builds the credits of every language from its Credits.rtf; no window is shown. Static checks cover the
About TeXShop action and the copyright strings. With --mutation NAME the harness runs against mutated
sources and must fail; --mutations runs them all."""
from pathlib import Path
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
HEADER = 'Sources/App/TSAboutCredits.h'
APP = 'Sources/App/TSApplication.m'
ADDRESS = 'https://texshop.app/'

MUTATIONS = {
    # The address is plain text, not a link.
    'no-link': (HEADER, '        NSLinkAttributeName: url,\n', ''),
    # The link goes after the credits, out of sight below them.
    'link-at-end': (HEADER, '    if (credits != nil)\n        [result appendAttributedString:credits];\n    return result;',
                    '    if (credits != nil)\n        [result insertAttributedString:credits atIndex:0];\n    return result;'),
    # The link opens another page.
    'wrong-url': (HEADER, 'NSURL *url = [NSURL URLWithString:TSAboutWebsiteAddress];',
                  'NSURL *url = [NSURL URLWithString:@"https://pages.uoregon.edu/koch/texshop/"];'),
    # The credits themselves are left out.
    'credits-dropped': (HEADER, '        [result appendAttributedString:credits];', '        ;'),
    # The link is in the system font, not in the font of the credits.
    'system-font': (HEADER, '    if (credits.length > 0)\n        font =', '    if (NO)\n        font ='),
    # The link is not centered like the credits.
    'left-aligned': (HEADER, 'centered.alignment = NSTextAlignmentCenter;', 'centered.alignment = NSTextAlignmentLeft;'),
    # About TeXShop shows the plain standard panel again.
    'no-override': (APP, '[self orderFrontStandardAboutPanelWithOptions:@{NSAboutPanelOptionCredits: credits}];',
                    '[super orderFrontStandardAboutPanel:sender];'),
    # The copyright keeps the address too.
    'copyright-keeps-url': ('Resources/Interfaces/ja.lproj/InfoPlist.strings', '© 2026 Yusuke Terada";',
                            '© 2026 Yusuke Terada\\nhttps://texshop.app/";'),
}

PROBE = r'''
#import <AppKit/AppKit.h>
#import "TSAboutCredits.h"

static void report(NSString *name, NSAttributedString *credits)
{
    NSAttributedString *shown = TSAboutCreditsWithWebsiteLink(credits);
    NSString *text = shown.string;
    NSRange line = [text lineRangeForRange:NSMakeRange(0, 0)];
    NSRange linkRange = NSMakeRange(0, 0);
    id link = shown.length ? [shown attribute:NSLinkAttributeName atIndex:0 effectiveRange:&linkRange] : nil;
    NSFont *font = shown.length ? [shown attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] : nil;
    NSFont *creditsFont = credits.length ? [credits attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] : nil;
    NSParagraphStyle *style = shown.length ? [shown attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL] : nil;
    __block NSUInteger links = 0;
    [shown enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0, shown.length) options:0
                   usingBlock:^(id value, NSRange range, BOOL *stop) {
        if (value != nil && [[value description] isEqualToString:TSAboutWebsiteAddress]) links++;
    }];
    BOOL keepsCredits = credits == nil || [shown.string hasSuffix:credits.string];
    BOOL creditsUnchanged = YES;
    if (credits != nil && keepsCredits) {
        NSAttributedString *tail = [shown attributedSubstringFromRange:NSMakeRange(shown.length - credits.length, credits.length)];
        creditsUnchanged = [tail isEqualToAttributedString:credits];
    }
    printf("%s\tfirst=%s\tlink=%s\tlinkclass=%s\tlinkrange=%lu,%lu\tlinks=%lu\tcentered=%d\tfont=%s\tcreditsfont=%s\tblank=%d\tkeeps=%d\tunchanged=%d\n",
        name.UTF8String,
        [[text substringWithRange:line] stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet].UTF8String,
        [[link description] ?: @"" UTF8String],
        NSStringFromClass([link class]).UTF8String,
        (unsigned long)linkRange.location, (unsigned long)linkRange.length, (unsigned long)links,
        style.alignment == NSTextAlignmentCenter,
        [NSString stringWithFormat:@"%@ %g", font.fontName, font.pointSize].UTF8String,
        [NSString stringWithFormat:@"%@ %g", creditsFont.fontName, creditsFont.pointSize].UTF8String,
        [text hasPrefix:[TSAboutWebsiteAddress stringByAppendingString:@"\n\n"]],
        keepsCredits, creditsUnchanged);
}

int main(int argc, const char **argv)
{
    @autoreleasepool {
        for (int i = 1; i < argc; i++) {
            NSString *path = @(argv[i]);
            NSBundle *bundle = [NSBundle bundleWithPath:path];
            NSString *language = path.lastPathComponent.stringByDeletingPathExtension;
            NSAttributedString *credits = nil;
            // The probe bundle holds one language; read it the way the application reads its own.
            NSURL *url = [bundle URLForResource:@"Credits" withExtension:@"rtf" subdirectory:nil localization:language];
            if (url != nil)
                credits = [[NSAttributedString alloc] initWithURL:url options:@{} documentAttributes:NULL error:NULL];
            if (credits == nil) { printf("%s\tunreadable\n", language.UTF8String); continue; }
            report(language, credits);
        }
        report(@"(none)", nil);
        // TSAboutBundleCredits reads the localized Credits.rtf of a bundle.
        NSString *first = @(argv[1]);
        NSBundle *bundle = [NSBundle bundleWithPath:first];
        NSAttributedString *read = TSAboutBundleCredits(bundle);
        printf("bundle-credits\tread=%d\n", read.length > 0);
    }
    return 0;
}
'''

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def strings_value(path, key):
    data = path.read_bytes()
    try:
        return plistlib.loads(data).get(key)
    except Exception:
        text = data.decode('utf-8')
        m = re.search(r'^\s*' + key + r'\s*=\s*"((?:[^"\\]|\\.)*)";', text, re.M)
        return m.group(1).encode().decode('unicode_escape').encode('latin-1').decode('utf-8') if m else None


def run(src, work):
    languages = sorted(p.name for p in (src / 'Resources/Interfaces').glob('*.lproj') if (p / 'Credits.rtf').exists())
    check(len(languages) >= 12, f'Credits.rtf in {len(languages)} languages')

    # One bundle per language, so that the probe reads each Credits.rtf as the application would.
    bundles = []
    for language in languages:
        bundle = work / 'bundles' / language
        (bundle / 'Contents/Resources' / language).mkdir(parents=True)
        shutil.copy(src / 'Resources/Interfaces' / language / 'Credits.rtf', bundle / 'Contents/Resources' / language / 'Credits.rtf')
        with open(bundle / 'Contents/Info.plist', 'wb') as f:
            plistlib.dump({'CFBundleIdentifier': 'org.texshop.about-probe.' + language.replace('_', '-').split('.')[0],
                           'CFBundleDevelopmentRegion': language.split('.')[0]}, f)
        bundles.append(str(bundle))

    probe = work / 'probe.m'
    probe.write_text(PROBE)
    binary = work / 'probe'
    built = subprocess.run(['clang', '-fobjc-arc', '-framework', 'AppKit', '-I', str(src / 'Sources/App'),
                            str(probe), '-o', str(binary)], capture_output=True, text=True)
    if built.returncode != 0:
        failures.append('probe did not compile:\n' + built.stderr[-3000:])
        return
    out = subprocess.run([str(binary)] + bundles, capture_output=True, text=True, timeout=120,
                         env={**os.environ, 'HOME': str(work / 'home'), 'CFFIXED_USER_HOME': str(work / 'home'), 'TMPDIR': str(work) + '/'})
    check(out.returncode == 0, 'probe failed: ' + out.stderr[-2000:])
    rows = {}
    for line in out.stdout.splitlines():
        name, *fields = line.split('\t')
        rows[name] = dict(f.split('=', 1) if '=' in f else (f, '') for f in fields)

    for language in languages + ['(none)']:
        r = rows.get(language.split('.')[0] if language != '(none)' else language)
        if r is None or 'unreadable' in r:
            failures.append(f'{language}: credits not read')
            continue
        check(r['first'] == ADDRESS, f'{language}: the credits start with the web site address (first line {r["first"]!r})')
        check(r['link'] == ADDRESS and r['linkclass'].endswith('URL'), f'{language}: the address is a link to {ADDRESS} (got {r["link"]!r})')
        check(r['linkrange'] == f'0,{len(ADDRESS)}', f'{language}: the link covers the address only ({r["linkrange"]})')
        check(r['links'] == '1', f'{language}: one link to the web site ({r["links"]})')
        check(r['centered'] == '1', f'{language}: the address is centered like the credits')
        check(r['blank'] == '1', f'{language}: an empty line separates the address from the credits')
        check(r['keeps'] == '1' and r['unchanged'] == '1', f'{language}: the credits follow unchanged')
        if language != '(none)':
            check(r['font'] == r['creditsfont'], f'{language}: the address is in the font of the credits ({r["font"]} vs {r["creditsfont"]})')
    check(rows.get('bundle-credits', {}).get('read') == '1', 'TSAboutBundleCredits reads the Credits.rtf of a bundle')

    # About TeXShop builds the credits with the link and shows them in the standard panel.
    app = (src / APP).read_text()
    m = re.search(r'- \(void\)orderFrontStandardAboutPanel:\(id\)sender\s*\{(.*?)\n\}', app, re.S)
    check(m is not None, 'TSApplication handles About TeXShop')
    if m:
        body = m.group(1)
        check('TSAboutCreditsWithWebsiteLink(TSAboutBundleCredits([NSBundle mainBundle]))' in body,
              'About TeXShop credits are the bundle credits led by the link')
        check('[self orderFrontStandardAboutPanelWithOptions:@{NSAboutPanelOptionCredits: credits}]' in body,
              'About TeXShop shows the standard panel with those credits')
    nib = (src / 'Resources/Interfaces/Base.lproj/MainMenu.nib/designable.nib').read_text()
    check(re.search(r'<menuItem title="About TeXShop"[^>]*>\s*<connections>\s*<action selector="orderFrontStandardAboutPanel:" target="-2"', nib) is not None,
          'the About TeXShop menu item still sends orderFrontStandardAboutPanel: to the application')
    plist = plistlib.loads((src / 'Resources/Info.plist').read_bytes())
    check(plist.get('NSPrincipalClass') == 'TSApplication', 'TSApplication is the principal class')

    # The copyright no longer carries the address; it ends with the current developer.
    files = [src / 'Resources/Info.plist'] + sorted((src / 'Resources/Interfaces').glob('*.lproj/InfoPlist.strings'))
    check(len(files) >= 13, f'{len(files)} copyright files')
    for file in files:
        text = strings_value(file, 'NSHumanReadableCopyright')
        name = file.relative_to(src).as_posix()
        check(text is not None, f'{name}: has a copyright')
        if text is None:
            continue
        check('texshop.app' not in text and 'http' not in text, f'{name}: the copyright has no web address')
        check(text.endswith('© 2026 Yusuke Terada'), f'{name}: the copyright ends with the current developer ({text[-40:]!r})')


def mutate(src, name):
    path, old, new = MUTATIONS[name]
    file = src / path
    text = file.read_text()
    if old not in text:
        raise SystemExit(f'mutation {name}: text not found in {path}')
    file.write_text(text.replace(old, new, 1))


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
    with tempfile.TemporaryDirectory(prefix='about-link-') as tmp:
        work = Path(tmp)
        (work / 'home').mkdir()
        src = root
        if args[:1] == ['--mutation']:
            src = work / 'src'
            for part in ('Sources/App', 'Resources/Interfaces'):
                shutil.copytree(root / part, src / part)
            shutil.copy(root / 'Resources/Info.plist', src / 'Resources/Info.plist')
            mutate(src, args[1])
        run(src, work)
    if failures:
        for f in failures:
            print('FAIL:', f)
        sys.exit(1)
    print('PASS: About TeXShop credits start with a link to the web site; the copyright has no address')


if __name__ == '__main__':
    main()
