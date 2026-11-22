#!/usr/bin/env python3
"""TeX options as the engines write them, and the Shell Escape confirmation.

The usage of pdfTeX, XeTeX and the other web2c engines writes -file-line-error, -synctex=1 and
-shell-escape with one hyphen, that of LuaTeX with two; every engine accepts both. The factory
commands and the profiles follow the usage; settings written with the other number of hyphens still
match a profile. Confirm Shell Escape notices -shell-escape and --shell-escape (not -no-shell-escape),
and Omit Shell Escape removes either; a run from a script adds -interaction=nonstopmode with the
hyphens of its engine. A probe compiled against Sources/Typesetting/TSTeXOptions.h checks the
helpers; static checks cover TSDocument-Jobs.m and the factory defaults. With --mutation NAME the
harness runs mutated sources and must fail; --mutations runs them all."""
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
HEADER = 'Sources/Typesetting/TSTeXOptions.h'
JOBS = 'Sources/Typesetting/TSDocument-Jobs.m'
MUTATIONS = {
    # Only --shell-escape is noticed again.
    'two-hyphens-only': (HEADER, '@"(?<![^\\\\s\\"\'/])--?shell-escape(?![^\\\\s\\"\'/])"', '@"(?<![^\\\\s\\"\'/])--shell-escape(?![^\\\\s\\"\'/])"'),
    # -no-shell-escape counts as -shell-escape.
    'no-shell-escape-counts': (HEADER, '@"(?<![^\\\\s\\"\'/])--?shell-escape(?![^\\\\s\\"\'/])"', '@"--?shell-escape(?![^\\\\s\\"\'/])"'),
    # Every engine gets two hyphens.
    'two-for-all': (HEADER, '    return TSTeXCommandRunsLuaTeX(command) ? @"--" : @"-";', '    return @"--";'),
    # The confirmation looks for --shell-escape only.
    'confirmation-old': (JOBS, '		if (! TSTeXCommandHasShellEscape(myEngine))\n			warningGiven = YES;',
                         '		if ([myEngine rangeOfString:@"--shell-escape"].location == NSNotFound)\n			warningGiven = YES;'),
    # A script run adds --interaction for every engine.
    'interaction-two': (JOBS, '[myEngine stringByAppendingFormat:@" %@interaction=nonstopmode ", TSTeXOptionDashes(myEngine)]',
                        '[myEngine stringByAppendingString:@" --interaction=nonstopmode "]'),
}

PROBE = r'''
#import <Foundation/Foundation.h>
#import "TSTeXOptions.h"
static int failures = 0;
static void check(BOOL ok, NSString *what) { if (!ok) { printf("FAIL: %s\n", what.UTF8String); failures++; } }
int main(void) {
    @autoreleasepool {
        for (NSString *c in @[@"pdflatex -shell-escape -file-line-error", @"pdflatex --shell-escape", @"xelatex -file-line-error -shell-escape",
                              @"latexmk -pdf -e \"$pdflatex=q/pdflatex -shell-escape/\"", @"pdflatex \"-shell-escape\" x"])
            check(TSTeXCommandHasShellEscape(c), [NSString stringWithFormat:@"shell escape noticed in %@", c]);
        for (NSString *c in @[@"pdflatex -no-shell-escape", @"pdflatex --no-shell-escape", @"pdflatex -file-line-error -synctex=1",
                              @"pdflatex -shell-escaped", @"my-shell-escape-engine x", @""])
            check(!TSTeXCommandHasShellEscape(c), [NSString stringWithFormat:@"no shell escape in %@", c]);
        check([TSTeXCommandWithoutShellEscape(@"pdflatex -shell-escape -file-line-error") isEqualToString:@"pdflatex  -file-line-error"], @"-shell-escape removed");
        check([TSTeXCommandWithoutShellEscape(@"lualatex --shell-escape --synctex=1") isEqualToString:@"lualatex  --synctex=1"], @"--shell-escape removed");
        check([TSTeXCommandWithoutShellEscape(@"pdflatex -no-shell-escape") isEqualToString:@"pdflatex -no-shell-escape"], @"-no-shell-escape kept");
        for (NSString *c in @[@"lualatex -file-line-error", @"luatex x", @"/Library/TeX/texbin/luahbtex x", @"  lualatex-dev x"])
            check([TSTeXOptionDashes(c) isEqualToString:@"--"], [NSString stringWithFormat:@"two hyphens for %@", c]);
        for (NSString *c in @[@"pdflatex x", @"xelatex x", @"platex x", @"latexmk -lualatex", @"ptex2pdf -l", @"uplatex"])
            check([TSTeXOptionDashes(c) isEqualToString:@"-"], [NSString stringWithFormat:@"one hyphen for %@", c]);
        check([TSTeXCommandWithOneHyphenOptions(@"pdflatex --file-line-error --synctex=1") isEqualToString:@"pdflatex -file-line-error -synctex=1"], @"former profile command compared with one hyphen");
        check([TSTeXCommandWithOneHyphenOptions(@"latexmk -e \"$lualatex=q/lualatex --synctex=1 --file-line-error/\"") isEqualToString:@"latexmk -e \"$lualatex=q/lualatex -synctex=1 -file-line-error/\""], @"inside latexmk too");
        check([TSTeXCommandWithOneHyphenOptions(@"simpdftex latex --maxpfb --extratexopts \"-file-line-error\"") isEqualToString:@"simpdftex latex --maxpfb --extratexopts \"-file-line-error\""], @"options of simpdftex kept");
    }
    return failures ? 1 : 0;
}
'''

failures = []


def check(ok, message):
    if not ok:
        failures.append(message)


def run(texts):
    jobs = texts[JOBS]
    check('if (! TSTeXCommandHasShellEscape(myEngine))\n\t\t\twarningGiven = YES;' in jobs, 'the confirmation notices both spellings')
    check('myEngine = TSTeXCommandWithoutShellEscape(myEngine);' in jobs, 'Omit Shell Escape removes either spelling')
    check('[myEngine stringByAppendingFormat:@" %@interaction=nonstopmode ", TSTeXOptionDashes(myEngine)]' in jobs, 'a script run adds -interaction with the hyphens of its engine')
    check('--shell-escape"' not in jobs, 'no search for --shell-escape alone')
    factory = plistlib.loads((root / 'Resources/Defaults/FactoryDefaults.plist').read_bytes())
    check(factory.get('LatexCommand') == 'pdflatex -file-line-error -synctex=1', f"factory LaTeX command: {factory.get('LatexCommand')!r}")
    check(factory.get('TexCommand') == 'pdftex -file-line-error -synctex=1', f"factory TeX command: {factory.get('TexCommand')!r}")
    for note in sorted((root / 'Resources/Interfaces').glob('*.lproj/SettingsCategories.strings')):
        line = [l for l in note.read_text(encoding='utf-8').splitlines() if l.startswith('"catalog.typesetting.4.2.note"')]
        check(line and '-shell-escape' in line[0] and '--shell-escape' not in line[0], f'{note.parent.name}: the note writes -shell-escape: {line}')
    with tempfile.TemporaryDirectory(prefix='tex-options-') as tmp:
        tmp = Path(tmp)
        (tmp / 'h').mkdir()
        (tmp / 'h/TSTeXOptions.h').write_text(texts[HEADER])
        (tmp / 'probe.m').write_text(PROBE)
        built = subprocess.run(['clang', '-fobjc-arc', '-framework', 'Foundation', '-I', str(tmp / 'h'), str(tmp / 'probe.m'), '-o', str(tmp / 'probe')], capture_output=True, text=True)
        if built.returncode:
            failures.append('probe did not compile: ' + built.stderr[-1500:])
            return
        out = subprocess.run([str(tmp / 'probe')], capture_output=True, text=True, timeout=60)
        for line in out.stdout.splitlines():
            failures.append(line[6:] if line.startswith('FAIL: ') else line)


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
    texts = {p: (root / p).read_text(encoding='utf-8') for p in (HEADER, JOBS)}
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
    print('PASS: TeX options are written as the engines write them; Confirm Shell Escape notices -shell-escape and --shell-escape')


if __name__ == '__main__':
    main()
