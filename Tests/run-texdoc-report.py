#!/usr/bin/env python3
"""Help > Show Help for Package says why texdoc showed nothing.

Three cases: the folder of the TeX engines has no texdoc that can run; texdoc ran but failed (any status
other than 0 and 3, or a signal); texdoc found no documentation (status 3). In the last case the alert
names the TeX installation (kpsewhich -var-value SELFAUTOPARENT of the same folder) and the doc folders
of its TEXDOCS path, since another TeX installation on the Mac may have the documentation, and says where
the folder of the TeX engines is set. texdoc runs with that folder first on its PATH, so its texlua is the
one of the same installation. A probe compiled against Sources/App/TSTexdocReport.h runs a stand-in
kpsewhich in a temporary folder; no window is shown. With --mutation NAME the harness runs mutated sources
and must fail; --mutations runs them all."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
HEADER = 'Sources/App/TSTexdocReport.h'
SOURCE = 'Sources/App/HelpDocuments.m'
MUTATIONS = {
    # Status 3 is reported as a failure of texdoc, without the folders searched.
    'not-found-as-failure': (HEADER, 'static const int TSTexdocNothingFound = 3;', 'static const int TSTexdocNothingFound = 99;'),
    # The folders are not listed.
    'no-folders': (HEADER, 'arrayByAddingObjectsFromArray:folders ?: @[]]', 'arrayByAddingObjectsFromArray:@[]]'),
    # The kpathsea marks stay in the listed folders.
    'marks-kept': (HEADER, 'NSString *folder = [entry hasPrefix:@"!!"] ? [entry substringFromIndex:2] : entry;', 'NSString *folder = entry;'),
    # Without kpsewhich the installation is guessed again.
    'guessed': (HEADER, '    *installation = root.length ? root : nil;', '    *installation = root.length ? root : binPath.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent;'),
    # texdoc may ask questions again (it reads EOF and ends with status 1).
    'interactive': (SOURCE, 'args = [NSMutableArray arrayWithObject:@"-I"];', 'args = [NSMutableArray array];'),
    # A texdoc that is there but not executable is reported as missing.
    'not-executable-as-missing': (HEADER, '    if (exists)\n        return @[', '    if (NO)\n        return @['),
    # texdoc stopped by signal 3 is taken for "no documentation found".
    'signal-as-not-found': (HEADER, '    if (exited && status == TSTexdocNothingFound) {', '    if (status == TSTexdocNothingFound) {'),
    # texdoc runs with the TeX folder last on its PATH again.
    'path-last': (SOURCE, 'path = [[binPath stringByAppendingString:@":"] stringByAppendingString:path];',
                  'path = [[path stringByAppendingString:@":"] stringByAppendingString:binPath];'),
    # A folder without texdoc does nothing.
    'missing-silent': (SOURCE, '		[self showTexdocAlert:TSTexdocMissingTexts(binPath, binPath.length && [[NSFileManager defaultManager] fileExistsAtPath:enginePath])];\n		return;', '		return;'),
}

PROBE = r'''
#import <Foundation/Foundation.h>
#import "TSTexdocReport.h"
static void show(NSString *name, NSArray<NSString *> *texts)
{
    printf("== %s\n%s\n--\n%s\n", name.UTF8String, texts ? texts[0].UTF8String : "(none)", texts ? texts[1].UTF8String : "");
}
int main(int argc, const char **argv)
{
    @autoreleasepool {
        NSString *bin = @(argv[1]);
        NSString *installation = nil;
        NSArray<NSString *> *folders = nil;
        TSTexdocSearch(bin, NSProcessInfo.processInfo.environment, &installation, &folders);
        printf("installation=%s\n", installation.UTF8String);
        for (NSString *folder in folders) printf("folder=%s\n", folder.UTF8String);
        NSString *texdoc = [bin stringByAppendingPathComponent:@"texdoc"];
        show(@"found", TSTexdocFailureTexts(0, YES, @"amsmath", texdoc, @"", installation, folders));
        show(@"nothing", TSTexdocFailureTexts(3, YES, @"nosuchpkg", texdoc, @"Sorry, no local documentation found for \"nosuchpkg\".\nYou can try the online version of Texdoc at <https://texdoc.org>.\n", installation, folders));
        show(@"failed", TSTexdocFailureTexts(1, YES, @"amsmath", texdoc, @"module 'texdoclib' not found", nil, nil));
        show(@"signal", TSTexdocFailureTexts(9, NO, @"amsmath", texdoc, @"", nil, nil));
        show(@"signal3", TSTexdocFailureTexts(3, NO, @"amsmath", texdoc, @"", nil, nil));
        show(@"missing", TSTexdocMissingTexts(@"/nowhere/bin", NO));
        show(@"unset", TSTexdocMissingTexts(@"", NO));
        show(@"notexec", TSTexdocMissingTexts(@"/somewhere/bin", YES));
        // A folder without kpsewhich: neither the installation nor the folders are known, and the alert says so.
        NSString *other = nil; NSArray *none = nil;
        TSTexdocSearch(@"/Applications/Other/2025/bin/universal-darwin", @{}, &other, &none);
        printf("fallback=%s folders=%s\n", other ? other.UTF8String : "nil", none ? "list" : "nil");
        show(@"unknown", TSTexdocFailureTexts(3, YES, @"nosuchpkg", @"/Applications/Other/2025/bin/universal-darwin/texdoc", @"", other, none));
    }
    return 0;
}
'''

KPSEWHICH = '''#!/bin/sh
case "$1" in
  -var-value) [ "$2" = SELFAUTOPARENT ] && echo "/Applications/TeXLive/2026" && exit 0 ;;
  --expand-braces=*) echo "$DOCS/home/texmf/doc//:$DOCS/missing/doc//:!!$DOCS/dist/doc//:!!$DOCS/guides//:!!$DOCS/dist/doc//"; exit 0 ;;
esac
exit 1
'''

failures = []


def check(ok, message):
    if not ok:
        failures.append(message)


def run(texts):
    source = texts[SOURCE]
    start = source.index('- (IBAction)displayHelpForPackage:sender')
    body = source[start:source.index('- (void)showTexdocAlert:', start)]
    check('path = [[binPath stringByAppendingString:@":"] stringByAppendingString:path];' in body,
          'texdoc runs with the folder of the TeX engines first on its PATH')
    check('[self showTexdocAlert:TSTexdocMissingTexts(binPath, binPath.length && [[NSFileManager defaultManager] fileExistsAtPath:enginePath])];\n\t\treturn;' in body and 'isExecutableFileAtPath:enginePath' in body,
          'a folder without a texdoc that can run says so')
    check('args = [NSMutableArray arrayWithObject:@"-I"];' in body and 'setStandardInput:[NSFileHandle fileHandleWithNullDevice]' in body,
          'texdoc runs without interaction and without a terminal to read')
    check('TSTexdocFailureTexts(status, exited, packageString, enginePath, output, installation, folders)' in body,
          'the end of texdoc is reported')
    check('launchAndReturnError:&launchError' in body and 'launchError.localizedDescription' in body,
          'a texdoc that cannot be started says why')
    with tempfile.TemporaryDirectory(prefix='texdoc-report-') as tmp:
        tmp = Path(tmp)
        (tmp / 'Sources').mkdir()
        (tmp / 'Sources/TSTexdocReport.h').write_text(texts[HEADER])
        bin_dir = tmp / 'TeXLive/bin/universal-darwin'
        bin_dir.mkdir(parents=True)
        docs = str(tmp / 'docs')
        for folder in ('home/texmf/doc', 'dist/doc', 'guides'):
            (tmp / 'docs' / folder).mkdir(parents=True)
        (bin_dir / 'kpsewhich').write_text(KPSEWHICH)
        os.chmod(bin_dir / 'kpsewhich', 0o755)
        (tmp / 'probe.m').write_text(PROBE)
        built = subprocess.run(['clang', '-fobjc-arc', '-framework', 'Foundation', '-I', str(tmp / 'Sources'), str(tmp / 'probe.m'), '-o', str(tmp / 'probe')],
                               capture_output=True, text=True)
        if built.returncode:
            failures.append('probe did not compile: ' + built.stderr[-2000:])
            return
        out = subprocess.run([str(tmp / 'probe'), str(bin_dir)], capture_output=True, text=True, timeout=60,
                             env={**os.environ, 'HOME': str(tmp), 'CFFIXED_USER_HOME': str(tmp), 'TMPDIR': str(tmp) + '/', 'DOCS': docs}).stdout
    sections = {}
    for chunk in out.split('== ')[1:]:
        name, rest = chunk.split('\n', 1)
        message, _, details = rest.partition('\n--\n')
        sections[name] = (message, details.strip())
    head = out.split('== ')[0]
    check('installation=/Applications/TeXLive/2026' in head, 'the installation is the SELFAUTOPARENT of kpsewhich: ' + head)
    folders = [line[7:] for line in head.splitlines() if line.startswith('folder=')]
    check(folders == [f'{docs}/home/texmf/doc', f'{docs}/dist/doc', f'{docs}/guides'],
          f'the existing roots of TEXDOCS are listed, without !! and //, once each, also not named doc: {folders}')
    check('fallback=nil folders=nil' in out, 'without kpsewhich neither the installation nor the folders are guessed')
    message, details = sections.get('unknown', ('', ''))
    check(message == 'No documentation was found for “nosuchpkg”.' and 'The folders that /Applications/Other/2025/bin/universal-darwin/texdoc searched could not be determined.' in details,
          f'unknown folders are said to be unknown, naming texdoc: {details!r}')
    message, details = sections.get('notexec', ('', ''))
    check(message == 'texdoc cannot be run.' and '/somewhere/bin/texdoc is not executable.' in details, f'not executable: {message!r} {details!r}')
    check(sections.get('found', ('',))[0] == '(none)', 'nothing is said when texdoc showed the documentation')
    message, details = sections.get('nothing', ('', ''))
    check(message == 'No documentation was found for “nosuchpkg”.', f'status 3: {message!r}')
    check(f'texdoc of the TeX installation in /Applications/TeXLive/2026 looked in:\n{docs}/home/texmf/doc\n{docs}/dist/doc\n{docs}/guides' in details,
          f'status 3 names the installation and the folders: {details!r}')
    check('Another TeX installation on this Mac may have it.' in details and '› typesetting › group.typesetting.3.title › catalog.typesetting.3.0.title' in details,
          f'status 3 says where the TeX installation is chosen: {details!r}')
    check('https://texdoc.org' in details, 'texdoc\'s own hint is kept')
    for name, status in (('failed', '1'), ('signal', '9'), ('signal3', '3')):
        message, details = sections.get(name, ('', ''))
        check(message == 'texdoc could not show the documentation for “amsmath”.', f'{name}: {message!r}')
        check(f'ended with status {status}.' in details and '/texdoc' in details, f'{name} names texdoc and its status: {details!r}')
    check("module 'texdoclib' not found" in sections.get('failed', ('', ''))[1], 'the output of a failing texdoc is shown')
    for name, folder in (('missing', '/nowhere/bin'), ('unset', '—')):
        message, details = sections.get(name, ('', ''))
        check(message == 'texdoc was not found.' and f'There is no texdoc in {folder}, the folder set in Settings ›' in details,
              f'{name}: {message!r} {details!r}')


def main():
    args = sys.argv[1:]
    if args == ['--mutations']:
        bad = []
        for name in MUTATIONS:
            r = subprocess.run([sys.executable, __file__, '--mutation', name], capture_output=True, text=True)
            print(('PASS: detected' if r.returncode else 'FAIL: missed') + f' mutation {name}: ' + (r.stdout.strip().splitlines() or [''])[0])
            if not r.returncode:
                bad.append(name)
        sys.exit(1 if bad else 0)
    texts = {path: (root / path).read_text(encoding='utf-8') for path in (HEADER, SOURCE)}
    if args[:1] == ['--mutation']:
        path, old, new = MUTATIONS[args[1]]
        if texts[path].count(old) != 1:
            sys.exit(f'mutation {args[1]}: text not found')
        texts[path] = texts[path].replace(old, new)
    run(texts)
    if failures:
        for f in failures:
            print('FAIL:', f)
        sys.exit(1)
    print('PASS: Show Help for Package says when texdoc is missing, fails, or finds nothing, naming the TeX installation and its doc folders')


if __name__ == '__main__':
    main()
