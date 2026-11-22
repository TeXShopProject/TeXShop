#!/usr/bin/env python3
"""TeX options as the engines write them, and the Shell Escape confirmation.

The usage of pdfTeX, XeTeX and the other web2c engines writes -file-line-error, -synctex=1 and
-shell-escape with one hyphen, that of LuaTeX with two; every engine accepts both. The factory
commands and the profiles follow the usage; settings written with the other number of hyphens still
match a profile. Confirm Shell Escape notices -shell-escape and --shell-escape (not -no-shell-escape),
and Omit Shell Escape removes either; a run from a script adds -interaction=nonstopmode with the
hyphens of its engine. Commands are read as TeXShop runs them: a second program compares
TSTeXCommandArguments with -[TSDocument separate:into:] taken from TSDocument-Jobs.m. A probe
compiled against Sources/Typesetting/TSTeXOptions.h checks the helpers; static checks cover
TSDocument-Jobs.m and the factory defaults; both copies of Manual.pdf are read with pypdf, which is
required (--without-pypdf shows that the harness then fails). With --mutation NAME the
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
    'two-hyphens-only': (HEADER, '[value isEqualToString:@"-shell-escape"] || ', ''),
    # A path, a quoted file name or a longer name that contains the option counts as the option.
    'loose-boundaries': (HEADER, '        if (TSTeXArgumentIsShellEscape(argument))\n            return YES;',
                         '        if ([argument[TSTeXArgumentValue] containsString:@"-shell-escape"])\n            return YES;'),
    # A command started through env is not seen as LuaTeX.
    'env-ignored': (HEADER, '        if (!afterEnv && [name isEqualToString:@"env"]) { afterEnv = YES; continue; }\n', ''),
    # env -u NAME: NAME is taken for the program.
    'env-values': (HEADER, '            if ([withValue containsObject:word]) { if (words.count) [words removeObjectAtIndex:0]; continue; }\n', ''),
    # Options inside paths and longer names are written with one hyphen for the comparison too.
    'normalize-anywhere': (HEADER, '@"^--(?:(?:no-)?(?:file-line-error|shell-escape)|synctex=-?\\\\d+|interaction=[a-z]+)$"',
                           '@"--(?:(?:no-)?(?:file-line-error|shell-escape)|synctex=-?\\\\d+|interaction=[a-z]+)"'),
    # The commands inside any -e option are read, not only those given to latexmk.
    'latexmk-any-program': (HEADER, '    if (![TSTeXCommandProgram(command).lowercaseString hasPrefix:@"latexmk"])\n        return arguments;\n', ''),
    # The space that joins the words inside quotes is not given a place in the command.
    'joined-offsets': (HEADER, '                [middleOffsets addObject:@(location - 1)];\n', ''),
    # Words are split at every space, quotes or not.
    'quotes-ignored': (HEADER, "            } else if ([word characterAtIndex:0] == '\"') {", "            } else if (NO) {"),
    # Every engine gets two hyphens.
    'two-for-all': (HEADER, '    return TSTeXCommandRunsLuaTeX(command) ? @"--" : @"-";', '    return @"--";'),
    # The confirmation looks for --shell-escape only.
    'confirmation-old': (JOBS, '		if (! TSTeXCommandHasShellEscape(myEngine))\n			warningGiven = YES;',
                         '		if ([myEngine rangeOfString:@"--shell-escape"].location == NSNotFound)\n			warningGiven = YES;'),
    # The probe ends badly without printing anything.
    'probe-silent-exit': ('PROBE', '    return failures ? 1 : 0;', '    return 7;'),
    # A script run adds --interaction for every engine.
    'interaction-two': (JOBS, '[myEngine stringByAppendingFormat:@" %@interaction=nonstopmode ", TSTeXOptionDashes(myEngine)]',
                        '[myEngine stringByAppendingString:@" --interaction=nonstopmode "]'),
}

SPLIT = r'''
#import <Foundation/Foundation.h>
#import "TSTeXOptions.h"
@interface Splitter : NSObject @end
@implementation Splitter
SEPARATE
@end
int main(void) {
    int failures = 0;
    @autoreleasepool {
        Splitter *s = [Splitter new];
        for (NSString *c in @[@"pdflatex -file-line-error -synctex=1", @"  pdflatex  a   b ", @"prog \"a b\" c \"d\"", @"bibtex \"", @"bibtex \" x\"",
                              @"pdflatex -output-directory=\"Sample --file-line-error records\"", @"pdflatex \"-output-directory=Sample  --x  records\" y",
                              @"latexmk -e \"$pdflatex=q/pdflatex  -shell-escape/\"", @"a \"b \"c d\" e", @"a \"\" b", @"a \"open never closed", @"\"quoted program\" x", @""]) {
            NSMutableArray *args = [NSMutableArray array];
            NSString *program = [s separate:c into:args];
            NSArray *mine = TSTeXCommandArguments(c);
            NSMutableArray *values = [NSMutableArray array];
            for (NSDictionary *a in mine) [values addObject:a[TSTeXArgumentValue]];
            NSMutableArray *theirs = [NSMutableArray array];
            if (program) { [theirs addObject:program]; [theirs addObjectsFromArray:args]; }
            if (![values isEqualToArray:theirs]) { printf("FAIL: %s: separate:into: gives %s, TSTeXCommandArguments %s\n", c.UTF8String, theirs.description.UTF8String, values.description.UTF8String); failures++; }
            for (NSDictionary *a in mine) {
                NSArray *offsets = a[TSTeXArgumentOffsets]; NSString *v = a[TSTeXArgumentValue];
                for (NSUInteger i = 0; i < v.length; i++) {
                    unichar at = [c characterAtIndex:[offsets[i] unsignedIntegerValue]];
                    if (at != [v characterAtIndex:i]) { printf("FAIL: %s: character %lu of %s is not where it is said to be\n", c.UTF8String, (unsigned long)i, v.UTF8String); failures++; break; }
                }
            }
        }
    }
    return failures ? 1 : 0;
}
'''

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
        check([TSTeXCommandWithoutShellEscape(@"pdflatex \"-shell-escape\" x") isEqualToString:@"pdflatex  x"], @"a quoted -shell-escape goes with its quotes");
        check([TSTeXCommandWithoutShellEscape(@"latexmk -e \"$pdflatex=q/pdflatex -shell-escape/\"") isEqualToString:@"latexmk -e \"$pdflatex=q/pdflatex /\""], @"inside latexmk");
        for (NSString *c in @[@"pdflatex -output-directory=/tmp/-shell-escape x", @"pdflatex -kpathsea-debug=-shell-escape", @"pdflatex x/-shell-escape/y", @"pdflatex --shell-escape-extra"])
            check(!TSTeXCommandHasShellEscape(c), [NSString stringWithFormat:@"no shell escape in a path or longer name: %@", c]);
        check([TSTeXCommandWithoutShellEscape(@"pdflatex -output-directory=/tmp/-shell-escape -shell-escape x") isEqualToString:@"pdflatex -output-directory=/tmp/-shell-escape  x"], @"only the argument is removed, not the path");
        for (NSString *c in @[@"pdflatex --file-line-error-extra", @"pdflatex -output-directory=/x/--file-line-error", @"pdflatex --synctex=abc"])
            check([TSTeXCommandWithOneHyphenOptions(c) isEqualToString:c], [NSString stringWithFormat:@"other names, values and paths unchanged: %@", c]);
        for (NSString *c in @[@"lualatex -file-line-error", @"luatex x", @"/Library/TeX/texbin/luahbtex x", @"  lualatex-dev x", @"env TEXINPUTS=. lualatex x", @"/usr/bin/env -i lualatex x"])
            check([TSTeXOptionDashes(c) isEqualToString:@"--"], [NSString stringWithFormat:@"two hyphens for %@", c]);
        for (NSString *c in @[@"pdflatex x", @"xelatex x", @"platex x", @"latexmk -lualatex", @"ptex2pdf -l", @"uplatex", @"env LUAINPUTS=x pdflatex y"])
            check([TSTeXOptionDashes(c) isEqualToString:@"-"], [NSString stringWithFormat:@"one hyphen for %@", c]);
        check([TSTeXCommandWithOneHyphenOptions(@"pdflatex --file-line-error --synctex=1") isEqualToString:@"pdflatex -file-line-error -synctex=1"], @"former profile command compared with one hyphen");
        check([TSTeXCommandWithOneHyphenOptions(@"latexmk -e \"$lualatex=q/lualatex --synctex=1 --file-line-error/\"") isEqualToString:@"latexmk -e \"$lualatex=q/lualatex -synctex=1 -file-line-error/\""], @"inside latexmk too");
        check([TSTeXCommandWithOneHyphenOptions(@"simpdftex latex --maxpfb --extratexopts \"-file-line-error\"") isEqualToString:@"simpdftex latex --maxpfb --extratexopts \"-file-line-error\""], @"options of simpdftex kept");
        // Commands are read as TeXShop runs them (separate:into:): a word that starts with a quote runs to one that ends with it.
        for (NSString *c in @[@"pdflatex \"my -shell-escape file.tex\"", @"pdflatex \"my --shell-escape\"", @"pdflatex -e \"$pdflatex=q/pdflatex -shell-escape/\"",
                              @"pdflatex -pdflatex=\"pdflatex -shell-escape\""])
            check(!TSTeXCommandHasShellEscape(c), [NSString stringWithFormat:@"no shell escape inside a quoted argument: %@", c]);
        check([TSTeXCommandWithoutShellEscape(@"pdflatex \"my -shell-escape file\" -shell-escape x") isEqualToString:@"pdflatex \"my -shell-escape file\"  x"], @"a quoted file name is kept");
        check([TSTeXCommandWithOneHyphenOptions(@"pdflatex \"-output-directory=Sample --file-line-error records\" --file-line-error") isEqualToString:@"pdflatex \"-output-directory=Sample --file-line-error records\" -file-line-error"], @"a quoted directory name is kept");
        // A quote inside a word does not open an argument for TeXShop: here --file-line-error reaches TeX as an argument of its own.
        check([TSTeXCommandWithOneHyphenOptions(@"pdflatex -output-directory=\"Sample --file-line-error records\"") isEqualToString:@"pdflatex -output-directory=\"Sample -file-line-error records\""], @"an argument TeXShop passes on its own is compared as one");
        for (NSString *c in @[@"latexmk -pdf -pdflatex=\"pdflatex -shell-escape %O %S\"", @"latexmk -e \"$pdflatex=q/pdflatex  -shell-escape/\"", @"latexmk -e \"$lualatex=q/lualatex '--shell-escape'/\""])
            check(TSTeXCommandHasShellEscape(c), [NSString stringWithFormat:@"shell escape noticed in a command latexmk runs: %@", c]);
        check([TSTeXCommandWithoutShellEscape(@"latexmk -e \"$pdflatex=q/pdflatex  -shell-escape  -synctex=1/\"") isEqualToString:@"latexmk -e \"$pdflatex=q/pdflatex    -synctex=1/\""], @"removed where the quoted words were joined");
        check([TSTeXCommandWithoutShellEscape(@"latexmk -pdflatex=\"pdflatex -shell-escape %O %S\"") isEqualToString:@"latexmk -pdflatex=\"pdflatex  %O %S\""], @"removed from -pdflatex=");
        check([TSTeXCommandWithOneHyphenOptions(@"latexmk -e \"$lualatex=q/lualatex  --synctex=1/\"") isEqualToString:@"latexmk -e \"$lualatex=q/lualatex  -synctex=1/\""], @"compared where the quoted words were joined");
        for (NSString *c in @[@"/usr/bin/env -u TEXINPUTS lualatex x", @"env -P /usr/bin lualatex", @"env -S lualatex x", @"env -i -u A -u B LUA=1 lualatex"])
            check([TSTeXOptionDashes(c) isEqualToString:@"--"], [NSString stringWithFormat:@"two hyphens past the options of env: %@", c]);
        check([TSTeXCommandProgram(@"/usr/bin/env -u TEXINPUTS pdflatex") isEqualToString:@"pdflatex"], @"env -u takes a name");
    }
    return failures ? 1 : 0;
}
'''

failures = []
WITHOUT_PYPDF = False


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
    # The manual writes LuaTeX's form with two ASCII hyphens (TeX would join -- into a dash), in both copies.
    try:
        if WITHOUT_PYPDF:
            raise ImportError('pypdf hidden by --without-pypdf')
        import pypdf
    except ImportError:
        pypdf = None
        failures.append('pypdf is needed to read Manual.pdf; run with a Python that has it (python3 -m pip install pypdf)')
    if pypdf is not None:
        for copy in ('DocumentSources/Manual Source/Manual.pdf', 'Resources/Interfaces/Base.lproj/Manual.pdf'):
            text = ''.join(page.extract_text() or '' for page in pypdf.PdfReader(str(root / copy)).pages if 'LuaTeX writes them' in (page.extract_text() or ''))
            check('LuaTeX writes them with two (--file-line-error)' in text, f'{copy}: LuaTeX writes them with two (--file-line-error), in ASCII')
    with tempfile.TemporaryDirectory(prefix='tex-options-') as tmp:
        tmp = Path(tmp)
        (tmp / 'h').mkdir()
        (tmp / 'h/TSTeXOptions.h').write_text(texts[HEADER])
        (tmp / 'probe.m').write_text(texts['PROBE'])
        built = subprocess.run(['clang', '-fobjc-arc', '-framework', 'Foundation', '-I', str(tmp / 'h'), str(tmp / 'probe.m'), '-o', str(tmp / 'probe')], capture_output=True, text=True)
        if built.returncode:
            failures.append('probe did not compile: ' + built.stderr[-1500:])
            return
        # TSTeXCommandArguments reads a command as -[TSDocument separate:into:] does.
        start = texts[JOBS].index('- (NSString *) separate: (NSString *)myEngine into:(NSMutableArray *)args')
        (tmp / 'split.m').write_text(SPLIT.replace('SEPARATE', texts[JOBS][start:texts[JOBS].index('\n}\n', start) + 3]))
        built = subprocess.run(['clang', '-fobjc-arc', '-framework', 'Foundation', '-I', str(tmp / 'h'), str(tmp / 'split.m'), '-o', str(tmp / 'split')], capture_output=True, text=True)
        if built.returncode:
            failures.append('the comparison with separate:into: did not compile: ' + built.stderr[-1500:])
        else:
            split = subprocess.run([str(tmp / 'split')], capture_output=True, text=True, timeout=60)
            failures.extend(line[6:] if line.startswith('FAIL: ') else line for line in split.stdout.splitlines())
            if split.returncode and not split.stdout.strip():
                failures.append(f'the comparison with separate:into: ended with status {split.returncode}')
        out = subprocess.run([str(tmp / 'probe')], capture_output=True, text=True, timeout=60)
        for line in out.stdout.splitlines():
            failures.append(line[6:] if line.startswith('FAIL: ') else line)
        # A probe that ends badly without a word fails too.
        if out.returncode != 0 and not out.stdout.strip():
            failures.append(f'the probe ended with status {out.returncode}: {out.stderr[-500:]}')
        if out.returncode == 0 and out.stdout.strip():
            failures.append('the probe printed failures but ended with status 0')


def main():
    args = sys.argv[1:]
    if args == ['--mutations']:
        bad = []
        for name in MUTATIONS:
            r = subprocess.run([sys.executable, __file__, '--mutation', name], capture_output=True, text=True)
            print(('PASS: detected' if r.returncode else 'FAIL: missed') + f' mutation {name}: ' + (r.stdout.strip().splitlines() or [''])[0])
            if not r.returncode:
                bad.append(name)
        # Without pypdf the manual cannot be read, and the harness fails rather than skip it.
        r = subprocess.run([sys.executable, __file__, '--without-pypdf'], capture_output=True, text=True)
        print(('PASS: fails' if r.returncode else 'FAIL: passes') + ' without pypdf: ' + (r.stdout.strip().splitlines() or [''])[0])
        if not r.returncode:
            bad.append('without-pypdf')
        sys.exit(1 if bad else 0)
    global WITHOUT_PYPDF
    if args == ['--without-pypdf']:
        WITHOUT_PYPDF, args = True, []
    texts = {p: (root / p).read_text(encoding='utf-8') for p in (HEADER, JOBS)}
    texts['PROBE'] = PROBE
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
