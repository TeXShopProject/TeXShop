#!/usr/bin/env python3
"""Every engine profile, with and without latexmk, typesets a sample document into a PDF with SyncTeX data.

The commands come from the product table (TSEngineProfileValues) and are split into arguments by the product's own
-[TSDocument separate:into:], as TeXShop does before it appends the file name. A TeX installation is required; without
one the test says SKIP. The dvips profile also needs Ghostscript."""
from pathlib import Path
import json, os, re, shutil, subprocess, sys, tempfile
from source_tree import include_args, source_file

R = Path(__file__).resolve().parents[1]


def tex_bin():
    candidates = [Path('/Library/TeX/texbin')]
    for root in ('/Applications/TeXLive', '/usr/local/texlive'):
        for year in sorted(Path(root).glob('[0-9][0-9][0-9][0-9]'), reverse=True):
            candidates += [year / 'bin/universal-darwin', year / 'bin/arm64-darwin', year / 'bin/x86_64-darwin']
    return next((c for c in candidates if (c / 'pdflatex').exists() and (c / 'uplatex').exists() and (c / 'latexmk').exists()), None)


def gs_bin():
    for c in ('/usr/local/bin', '/opt/homebrew/bin', '/usr/local/teTeX/bin', '/opt/local/bin'):
        if (Path(c) / 'gs').exists() and (Path(c) / 'ps2pdf').exists():
            return Path(c)
    return None


TEX, GS = tex_bin(), gs_bin()
if TEX is None:
    print('SKIP: no TeX installation with pdflatex, uplatex and latexmk')
    sys.exit(0)

jobs = source_file(R, 'TSDocument-Jobs.m').read_text(encoding='latin1')
start = jobs.index('- (NSString *) separate: (NSString *)myEngine into:(NSMutableArray *)args')
separate = jobs[start:jobs.index('\n}\n', start) + 3]
PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import "TSPreferenceProfile.h"
@interface Splitter : NSObject @end
@implementation Splitter
SEPARATE
@end
int main(void) { @autoreleasepool {
    NSMutableArray *out = [NSMutableArray array];
    Splitter *splitter = [Splitter new];
    for (NSArray<NSNumber *> *section in TSEngineProfileMenuSections()) for (NSNumber *p in section) for (NSNumber *mk in @[@NO, @YES]) {
        NSDictionary *values = TSEngineProfileValues(p.integerValue, mk.boolValue);
        for (NSString *key in @[@"LatexCommand", @"LatexGSCommand", @"TexCommand", @"TexGSCommand"]) {
            if (values[key] == nil) continue;
            NSMutableArray *args = [NSMutableArray array];
            NSString *program = [splitter separate:values[key] into:args];
            [out addObject:@{@"profile": p, @"latexmk": mk, @"key": key, @"program": program, @"args": args}];
        }
    }
    printf("%s", [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:out options:0 error:NULL] encoding:NSUTF8StringEncoding].UTF8String);
} return 0; }
'''.replace('SEPARATE', separate)

LATEX = r'''\documentclass{article}
\begin{document}
Text \cite{x}. \index{text}
\bibliographystyle{plain}\bibliography{refs}
\end{document}
'''
PLATEX = r'''\documentclass{jsarticle}
\begin{document}
日本語の文 \cite{x}.
\bibliographystyle{jplain}\bibliography{refs}
\end{document}
'''
LUALATEXJA = PLATEX.replace('jsarticle', 'ltjsarticle')
PLAIN = 'Plain \\TeX\\bye\n'
BIB = '@book{x, author={A. Author}, title={Title}, publisher={P}, year={2020}}\n'
DOCUMENTS = {1: LATEX, 2: LATEX, 3: LATEX, 4: LATEX, 5: LUALATEXJA, 6: PLATEX, 7: PLATEX, 8: LATEX}

with tempfile.TemporaryDirectory(prefix='texshop-engine-typeset-') as temp:
    t = Path(temp)
    (t / 'probe.m').write_text(PROGRAM)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', *include_args(R), '-framework', 'Cocoa', str(t / 'probe.m'),
                    str(source_file(R, 'TSPreferenceProfile.m')), str(source_file(R, 'globals.m')), '-o', str(t / 'probe')], check=True)
    commands = json.loads(subprocess.run([str(t / 'probe')], capture_output=True, text=True, check=True).stdout)
    assert len(commands) == 8 * 2 * 2, len(commands)
    home = t / 'home'
    (home / 'Library').mkdir(parents=True)
    path = ':'.join(str(p) for p in (TEX, GS) if p) + ':/usr/bin:/bin:/usr/sbin:/sbin'
    env = {'PATH': path, 'HOME': str(home), 'LANG': 'en_US.UTF-8', 'TMPDIR': str(t)}
    failures, passed, skipped = [], 0, []
    for c in commands:
        name = 'p%d-%s-%s' % (c['profile'], 'mk' if c['latexmk'] else 'once', c['key'])
        if c['profile'] == 8 and GS is None:
            skipped.append(name)
            continue
        plain = c['key'].startswith('Tex')
        if plain and c['latexmk']:
            # The TeX commands do not change with latexmk; the first pass already ran them.
            continue
        work = t / name
        work.mkdir()
        (work / 'doc.tex').write_text(PLAIN if plain else DOCUMENTS[c['profile']])
        (work / 'refs.bib').write_text(BIB)
        executable = shutil.which(c['program'], path=path)
        if executable is None:
            failures.append((name, 'program not found: ' + c['program']))
            continue
        run = subprocess.run([executable, *c['args'], 'doc.tex'], cwd=work, env=env, capture_output=True, text=True,
                             stdin=subprocess.DEVNULL, timeout=300)
        pdf, synctex = work / 'doc.pdf', work / 'doc.synctex.gz'
        if run.returncode or not pdf.exists() or pdf.stat().st_size == 0 or not synctex.exists():
            failures.append((name, (run.stdout + run.stderr)[-1500:]))
            continue
        if not plain and c['latexmk']:
            # latexmk ran BibTeX: the citation is resolved.
            bbl = work / 'doc.bbl'
            if not bbl.exists() or 'Author' not in bbl.read_text(errors='replace'):
                failures.append((name, 'latexmk did not run BibTeX'))
                continue
        passed += 1
        print('OK', name, flush=True)
    for name, why in failures:
        print('FAIL', name, '\n', why, file=sys.stderr)
    if skipped:
        print('SKIP (no Ghostscript):', ', '.join(skipped))
    if failures:
        sys.exit(1)
    print('PASS: %d typesetting commands made a PDF with SyncTeX data using %s%s' % (passed, TEX, ' and ' + str(GS) if GS else ''))
