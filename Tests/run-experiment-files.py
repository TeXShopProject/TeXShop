#!/usr/bin/env python3
"""Experiment typesetting finds the document's files and references (#8).

The Experiment folder holds copy-on-write clones of the items next to the
document, so \\includegraphics{./Norms.pdf} and \\graphicspath{{./figs/}}, which
TeX does not look up in TEXINPUTS, work as in the document, while whatever TeX,
Lua or shell commands write there leaves the document's folder alone. Symbolic
links that lead out of the Experiment folder are removed. A copy of the
document's .aux, up to its last complete line, is read with @ as a letter at the
start of every run, also when latexmk typesets more than once.

The folder preparation is compiled from TSExperimentJob.m, and the line that
reads the .aux is taken from TSDocument-Scrap.m. With TeX Live, the document is
typeset first to produce a real .aux (hyperref, \\include, a bibliography); then
pdflatex, lualatex and latexmk typeset fragments from the Experiment folder, as
the Experiment does, and every item of the document's folder is compared before
and after.
"""
from pathlib import Path
import argparse, hashlib, os, re, shutil, subprocess, tempfile
from source_tree import include_args

MUTATIONS = {
    'no-clone': ('        if (clonefile(from.fileSystemRepresentation, to.fileSystemRepresentation, CLONE_NOFOLLOW | CLONE_NOOWNERCOPY) == 0)\n',
                 '        if (NO)\n'),
    'keeps-outward-links': ('    for (NSString *path in outward) [manager removeItemAtPath:path error:NULL];\n', ''),
    'clones-experiment-files': ('''        if ([excluded containsObject:lower] || [lower hasPrefix:@"file."]) continue;\n''', ''),
    'case-sensitive': ('''        NSString *lower = item.lowercaseString;\n''', '''        NSString *lower = item;\n'''),
    'no-limit': ('        if (++total > TSExperimentMaximumClonedItems) return 0;\n', '        ++total;\n'),
    'whole-aux': ("    while (end > 0 && bytes[end - 1] != '\\n') end--;\n", ''),
    'aux-catcode': None,
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
job = (root / 'Sources/Typesetting/TSExperimentJob.m').read_text()
if args.mutation and MUTATIONS[args.mutation]:
    old, new = MUTATIONS[args.mutation]
    assert job.count(old) == 1, args.mutation
    job = job.replace(old, new)
scrap = (root / 'Sources/Document/TSDocument-Scrap.m').read_text(encoding='latin1')
match = re.search(r'readAux = \[NSString stringWithFormat:@"((?:[^"\\]|\\.)*)",', scrap)
assert match, 'the line that reads the .aux is found in TSDocument-Scrap.m'
read_aux = match.group(1).replace('\\\\', '\\')
assert read_aux.count('%@') == 1
if args.mutation == 'aux-catcode':
    read_aux = read_aux.replace('\\begingroup\\makeatletter', '').replace('\\endgroup', '')

program = r'''
#import <Foundation/Foundation.h>
#import "TSExperimentJob.h"
static void check(BOOL ok, const char *message) { if (!ok) { fprintf(stderr, "FAIL: %s\n", message); exit(1); } }
int main(int argc, char **argv) { @autoreleasepool {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *doc = [NSURL fileURLWithPath:@(argv[1]) isDirectory:YES], *exp = [NSURL fileURLWithPath:@(argv[2]) isDirectory:YES];
    NSString *e = exp.path;
    NSUInteger count = [TSExperimentJob cloneItemsOfDirectory:doc intoDirectory:exp exceptNames:@[@"file", @"TeXShop-document.aux"]];
    NSDictionary *norms = [fm attributesOfItemAtPath:[e stringByAppendingPathComponent:@"Norms.pdf"] error:NULL];
    check([norms[NSFileType] isEqual:NSFileTypeRegular], "a file next to the document is cloned, not linked");
    check([[fm attributesOfItemAtPath:[e stringByAppendingPathComponent:@"figs"] error:NULL][NSFileType] isEqual:NSFileTypeDirectory] &&
          [fm fileExistsAtPath:[e stringByAppendingPathComponent:@"figs/Plot.pdf"]], "a subfolder is cloned with its contents");
    check(![fm fileExistsAtPath:[e stringByAppendingPathComponent:@"file.tex"]] && ![fm fileExistsAtPath:[e stringByAppendingPathComponent:@"file.aux"]] &&
          ![fm fileExistsAtPath:[e stringByAppendingPathComponent:@"TeXShop-document.aux"]], "the Experiment's own names are left out");
    check(![[fm contentsOfDirectoryAtPath:e error:NULL] containsObject:@"File.Log"], "names are compared ignoring case");
    check(![fm attributesOfItemAtPath:[e stringByAppendingPathComponent:@"outward"] error:NULL] &&
          ![fm attributesOfItemAtPath:[e stringByAppendingPathComponent:@"figs/outward"] error:NULL], "links that lead out of the folder are removed");
    check([[fm destinationOfSymbolicLinkAtPath:[e stringByAppendingPathComponent:@"figs/inward"] error:NULL] isEqualToString:@"../Norms.pdf"],
          "a link within the clones stays");
    [@"written in the Experiment\n" writeToFile:[e stringByAppendingPathComponent:@"figs/cache.dat"] atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    check([[NSString stringWithContentsOfURL:[doc URLByAppendingPathComponent:@"figs/cache.dat"] encoding:NSUTF8StringEncoding error:NULL]
              isEqualToString:@"the document's cache\n"], "writing a clone leaves the document's file alone");
    [@"the document's cache\n" writeToFile:[e stringByAppendingPathComponent:@"figs/cache.dat"] atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    check(count >= 6, "the other items are cloned");
    check([TSExperimentJob copyAuxiliaryFile:[doc URLByAppendingPathComponent:@"half.aux"]
                                       toURL:[exp URLByAppendingPathComponent:@"half-copy.aux"]], "an .aux is copied");
    NSString *aux = [NSString stringWithContentsOfURL:[exp URLByAppendingPathComponent:@"half-copy.aux"] encoding:NSUTF8StringEncoding error:NULL];
    check([aux hasSuffix:@"{{3}{7}}\n"] && ![aux containsString:@"half"], "the copy ends with the last complete line");
    [fm removeItemAtURL:[exp URLByAppendingPathComponent:@"half-copy.aux"] error:NULL];
    check(![TSExperimentJob copyAuxiliaryFile:[doc URLByAppendingPathComponent:@"missing.aux"] toURL:[exp URLByAppendingPathComponent:@"x.aux"]],
          "a missing .aux is not copied");
    NSURL *crowded = [NSURL fileURLWithPath:@(argv[3]) isDirectory:YES], *other = [NSURL fileURLWithPath:@(argv[4]) isDirectory:YES];
    check([TSExperimentJob cloneItemsOfDirectory:crowded intoDirectory:other exceptNames:@[@"file"]] == 0 &&
          [fm contentsOfDirectoryAtPath:other.path error:NULL].count == 0, "a folder of too many items is not cloned");
    return 0;
}}
'''

def digest(folder):
    """Content of every file and the kind of every other item under `folder`, following no link."""
    result = {}
    for path in sorted(folder.rglob('*')):
        key = str(path.relative_to(folder))
        result[key] = ('link:' + os.readlink(path)) if path.is_symlink() else 'dir' if path.is_dir() \
            else hashlib.sha256(path.read_bytes()).hexdigest()
    return result

with tempfile.TemporaryDirectory(prefix='texshop-experiment-files-') as directory:
    t = Path(directory)
    (t / 'TSExperimentJob.m').write_text(job)
    (t / 'probe.m').write_text(program)
    exe = t / 'probe'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation', *include_args(root),
                    str(t / 'probe.m'), str(t / 'TSExperimentJob.m'), '-o', str(exe)], check=True)
    doc, exp, crowded, other, outside = t / 'doc', t / 'exp', t / 'crowded', t / 'other', t / 'outside'
    for d in (doc / 'figs', doc / 'chapters', exp, crowded, other, outside):
        d.mkdir(parents=True)
    pdf = (b'%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj '
           b'3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 100 50]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n')
    (doc / 'Norms.pdf').write_bytes(pdf)
    (doc / 'figs' / 'Plot.pdf').write_bytes(pdf)
    (doc / 'figs' / 'cache.dat').write_text('the document\'s cache\n')
    (doc / 'cache.dat').write_text('the document\'s cache\n')
    (doc / 'File.Log').write_text('the document\'s File.Log\n')
    (doc / 'file.tex').write_text('the document\'s own file.tex\n')
    (doc / 'file.aux').write_text('\\relax\n\\newlabel{own}{{99}{99}}\n')
    (doc / 'TeXShop-document.aux').write_text('not to be cloned\n')
    (outside / 'target.txt').write_text('outside\n')
    os.symlink('../outside', doc / 'outward')
    os.symlink('../../outside/target.txt', doc / 'figs' / 'outward')
    os.symlink('../Norms.pdf', doc / 'figs' / 'inward')
    # Written while the document is typeset: the last line is not finished yet.
    (doc / 'half.aux').write_text('\\relax\n\\newlabel{shared}{{3}{7}}\n\\newlabel{half}{{')
    for k in range(5001):
        (crowded / f'item{k}').write_text('')
    run = subprocess.run([str(exe), str(doc), str(exp), str(crowded), str(other)], capture_output=True, text=True)
    if args.mutation and args.mutation != 'aux-catcode':
        assert run.returncode == 1, (args.mutation, run.stdout, run.stderr)
        print(f'PASS: detected mutation {args.mutation}: {run.stderr.strip()}')
        raise SystemExit(0)
    if run.returncode:
        raise SystemExit(run.stderr)
    texbin = '/Applications/TeXLive/2026/bin/universal-darwin'
    tex = shutil.which('pdflatex', path=texbin + ':' + os.environ.get('PATH', ''))
    if not tex:
        print('SKIP: no pdflatex for the typesetting checks')
        raise SystemExit(0)
    texdir = str(Path(tex).parent)
    env = dict(os.environ, PATH=texdir + ':' + os.environ.get('PATH', ''), TEXINPUTS=f'.:{doc}:')
    # The document, typeset twice, writes a real .aux with hyperref, \include and a bibliography.
    (doc / 'chapters' / 'a.tex').write_text('Chapter text.\\label{inchapter}\n')
    (doc / 'main.tex').write_text('\\documentclass{article}\\usepackage{hyperref}\\begin{document}\n'
                                  '\\section{Introduction}\\label{shared}See \\cite{key}.\n\\include{chapters/a}\n'
                                  '\\begin{thebibliography}{9}\\bibitem{key} A. Author.\\end{thebibliography}\n\\end{document}\n')
    for _ in range(2):
        subprocess.run([tex, '-interaction=batchmode', 'main.tex'], cwd=doc, env=env, capture_output=True, timeout=120)
    assert '\\@input{chapters/a.aux}' in (doc / 'main.aux').read_text(), 'the document produced a real .aux'
    shutil.rmtree(exp); exp.mkdir()
    subprocess.run([str(exe), str(doc), str(exp), str(crowded), str(other)], capture_output=True, text=True, check=True)
    shutil.copy(doc / 'main.aux', exp / 'TeXShop-document.aux')
    before = digest(doc)

    def fragment(body, preamble='\\usepackage{graphicx}\\usepackage{hyperref}'):
        # As typesetScrap writes it: the .aux copy is read on the line of \begin{document}.
        line = read_aux.replace('%@', str(exp / 'TeXShop-document.aux'))
        (exp / 'file.tex').write_text('\\documentclass{article}' + preamble + '\n' + line + '\\begin{document}\n' + body + '\n\\end{document}\n')
        for name in ('file.aux', 'file.log', 'file.pdf', 'file.fls', 'file.fdb_latexmk', 'file.out'):
            (exp / name).unlink(missing_ok=True)

    def typeset(program, *options):
        return subprocess.run([shutil.which(program, path=texdir), '-interaction=nonstopmode', *options, 'file.tex'],
                              cwd=exp, env=env, capture_output=True, text=True, timeout=240)

    def log():
        return (exp / 'file.log').read_text(errors='replace')

    def typesetting_checks():
        fragment('\\includegraphics[width=1cm]{./Norms.pdf}\n{\\graphicspath{{./figs/}}\\includegraphics[width=1cm]{Plot.pdf}}\n'
                 'See \\ref{shared} on page \\pageref{inchapter} and \\cite{key}.\n\\include{chapters/a}\n'
                 '\\newwrite\\w\\immediate\\openout\\w=figs/cache.dat \\immediate\\write\\w{TeX}\\immediate\\closeout\\w\n'
                 '\\immediate\\write18{printf shell > cache.dat}\n')
        result = typeset('pdflatex', '-shell-escape')
        assert result.returncode == 0, 'pdflatex typesets the fragment:\n' + result.stdout[-1500:]
        assert 'not found' not in log(), 'images next to the document, also with ./, are found'
        assert 'undefined' not in log().lower(), 'references, page references and citations of the document resolve'
        assert (exp / 'figs' / 'cache.dat').read_text() == 'TeX\n' and (exp / 'cache.dat').read_text() == 'shell', \
            'what TeX and shell commands write goes to the Experiment folder'
        assert digest(doc) == before, 'pdflatex leaves every item of the document\'s folder unchanged'
        if shutil.which('lualatex', path=texdir):
            fragment('\\directlua{local f=assert(io.open("cache.dat","w")); f:write("lua"); f:close()}See \\ref{shared}.', preamble='')
            result = typeset('lualatex')
            assert result.returncode == 0 and (exp / 'cache.dat').read_text() == 'lua', 'lualatex writes into the Experiment folder'
            assert digest(doc) == before, 'Lua leaves every item of the document\'s folder unchanged'
        # The Experiment's own file.aux, not the document's of the same name, is read.
        fragment('\\section{A}\\label{own}Own: \\ref{own}.', preamble='')
        for _ in range(2):
            result = typeset('pdflatex')
        assert result.returncode == 0 and '{own}{{1}' in (exp / 'file.aux').read_text(), 'the Experiment reads its own file.aux'
        # latexmk typesets more than once; every run reads the copy of the document's .aux.
        if shutil.which('latexmk', path=texdir):
            fragment('See \\ref{shared}, \\pageref{inchapter} and \\cite{key}. \\section{B}\\label{mine}\\ref{mine}')
            result = subprocess.run([shutil.which('latexmk', path=texdir), '-pdf', '-g', '-interaction=nonstopmode', 'file.tex'],
                                    cwd=exp, env=env, capture_output=True, text=True, timeout=240)
            runs = (result.stdout + result.stderr).count('Run number')
            assert result.returncode == 0 and runs >= 2, f'latexmk typesets more than once ({runs} runs):\n' + result.stdout[-1500:]
            assert 'undefined' not in log().lower(), 'references of the document resolve in the last latexmk run'
        assert digest(doc) == before, 'every item of the document\'s folder is unchanged'

    if args.mutation == 'aux-catcode':
        try:
            typesetting_checks()
        except AssertionError as failure:
            print('PASS: detected mutation aux-catcode: ' + str(failure).splitlines()[0])
            raise SystemExit(0)
        raise SystemExit('mutation aux-catcode not detected')
    typesetting_checks()
    # A fragment with an error fails, so that a passing typesetting check means a clean run.
    fragment('\\errmessage{intentional error}', preamble='')
    assert typeset('pdflatex').returncode != 0, 'a TeX error makes the typesetting check fail'
    print('PASS: Experiment clones the document\'s folder, finds ./ and \\graphicspath files, resolves references of a real .aux '
          'with pdflatex and latexmk, and TeX, Lua and shell writes leave the document\'s folder unchanged')
