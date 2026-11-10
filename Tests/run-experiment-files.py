#!/usr/bin/env python3
"""Experiment typesetting finds the document's files and references (#8).

A TeX program from Settings runs from the document's folder with
-output-directory set to the Experiment folder, so \\includegraphics{./Norms.pdf}
and \\graphicspath{{./figs/}}, which TeX does not look up in TEXINPUTS, work as in
the document, while everything TeX writes goes to the Experiment folder. Empty
folders named like the document's subfolders exist there, so writes into them
succeed. A copy of the document's .aux, up to its last complete line, is read at
the start of every run, also when latexmk typesets more than once.

The folder preparation is compiled from TSExperimentJob.m. With TeX Live,
pdflatex and latexmk typeset a fragment written as typesetScrap writes it, and
every file of the document's folder is compared before and after.
"""
from pathlib import Path
import argparse, hashlib, os, shutil, subprocess, tempfile
from source_tree import include_args

MUTATIONS = {
    'no-subfolders': ('    if (names.count > TSExperimentMaximumFolders) return 0;\n',
                      '    if (names.count > TSExperimentMaximumFolders || YES) return 0;\n'),
    'no-limit': ('    if (names.count > TSExperimentMaximumFolders) return 0;\n', ''),
    'whole-aux': ("    while (end > 0 && bytes[end - 1] != '\\n') end--;\n", ''),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
job = (root / 'Sources/Typesetting/TSExperimentJob.m').read_text()
if args.mutation:
    old, new = MUTATIONS[args.mutation]
    assert job.count(old) == 1, args.mutation
    job = job.replace(old, new)

program = r'''
#import <Foundation/Foundation.h>
#import "TSExperimentJob.h"
static void check(BOOL ok, const char *message) { if (!ok) { fprintf(stderr, "FAIL: %s\n", message); exit(1); } }
int main(int argc, char **argv) { @autoreleasepool {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *doc = [NSURL fileURLWithPath:@(argv[1]) isDirectory:YES], *exp = [NSURL fileURLWithPath:@(argv[2]) isDirectory:YES];
    NSUInteger count = [TSExperimentJob createSubdirectoriesOf:doc inDirectory:exp];
    NSDictionary *figs = [fm attributesOfItemAtPath:[exp URLByAppendingPathComponent:@"figs"].path error:NULL];
    check([figs[NSFileType] isEqual:NSFileTypeDirectory], "a subfolder of the document's folder exists as a real folder");
    check([fm contentsOfDirectoryAtPath:[exp URLByAppendingPathComponent:@"figs"].path error:NULL].count == 0,
          "the folder is empty: nothing of the document is linked or copied");
    check(![fm fileExistsAtPath:[exp URLByAppendingPathComponent:@"Norms.pdf"].path], "files of the document's folder are not linked");
    check(count == 1, "only folders are created");
    check([TSExperimentJob copyAuxiliaryFile:[doc URLByAppendingPathComponent:@"main.aux"]
                                       toURL:[exp URLByAppendingPathComponent:@"TeXShop-document.aux"]], "the document's .aux is copied");
    NSString *aux = [NSString stringWithContentsOfURL:[exp URLByAppendingPathComponent:@"TeXShop-document.aux"] encoding:NSUTF8StringEncoding error:NULL];
    check([aux hasPrefix:@"\\relax"] && [aux hasSuffix:@"{{3}{7}}\n"], "the copy ends with the last complete line");
    check(![TSExperimentJob copyAuxiliaryFile:[doc URLByAppendingPathComponent:@"missing.aux"] toURL:[exp URLByAppendingPathComponent:@"x.aux"]],
          "a missing .aux is not copied");
    NSURL *crowded = [NSURL fileURLWithPath:@(argv[3]) isDirectory:YES], *other = [NSURL fileURLWithPath:@(argv[4]) isDirectory:YES];
    check([TSExperimentJob createSubdirectoriesOf:crowded inDirectory:other] == 0 &&
          [fm contentsOfDirectoryAtPath:other.path error:NULL].count == 0, "a folder with too many subfolders is not mirrored");
    return 0;
}}
'''

def digest(folder):
    """Content and type of every item under `folder`, following nothing."""
    result = {}
    for path in sorted(folder.rglob('*')):
        key = str(path.relative_to(folder))
        result[key] = 'link' if path.is_symlink() else 'dir' if path.is_dir() else hashlib.sha256(path.read_bytes()).hexdigest()
    return result

with tempfile.TemporaryDirectory(prefix='texshop-experiment-files-') as directory:
    t = Path(directory)
    (t / 'TSExperimentJob.m').write_text(job)
    (t / 'probe.m').write_text(program)
    exe = t / 'probe'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation', *include_args(root),
                    str(t / 'probe.m'), str(t / 'TSExperimentJob.m'), '-o', str(exe)], check=True)
    doc, exp, crowded, other = t / 'doc', t / 'exp', t / 'crowded', t / 'other'
    for d in (doc / 'figs', exp, crowded, other):
        d.mkdir(parents=True)
    pdf = (b'%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj '
           b'3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 100 50]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n')
    (doc / 'Norms.pdf').write_bytes(pdf)
    (doc / 'figs' / 'Plot.pdf').write_bytes(pdf)
    (doc / 'figs' / 'cache.dat').write_text('the document\'s cache\n')
    (doc / 'chapter.tex').write_text('Chapter text.\\label{inchapter}\n')
    (doc / 'chapter.aux').write_text('the document\'s chapter.aux\n')
    (doc / 'File.log').write_text('the document\'s File.log\n')
    (doc / 'file.tex').write_text('the document\'s own file.tex\n')
    (doc / 'file.aux').write_text('\\relax\n\\newlabel{own}{{99}{99}}\n')
    # Written while the document is typeset: the last line is not finished yet.
    (doc / 'main.aux').write_text('\\relax\n\\newlabel{shared}{{3}{7}}\n\\newlabel{half}{{')
    for k in range(501):
        (crowded / f'folder{k}').mkdir()
    run = subprocess.run([str(exe), str(doc), str(exp), str(crowded), str(other)], capture_output=True, text=True)
    if args.mutation:
        assert run.returncode == 1, (args.mutation, run.stdout, run.stderr)
        print(f'PASS: detected mutation {args.mutation}: {run.stderr.strip()}')
        raise SystemExit(0)
    if run.returncode:
        raise SystemExit(run.stderr)
    before = digest(doc)
    texbin = '/Applications/TeXLive/2026/bin/universal-darwin'
    tex = shutil.which('pdflatex', path=texbin + ':' + os.environ.get('PATH', ''))
    if not tex:
        print('SKIP: no pdflatex for the typesetting checks')
        raise SystemExit(0)
    texdir = str(Path(tex).parent)
    env = dict(os.environ, TEXINPUTS=f'.:{doc}:', PATH=texdir + ':' + os.environ.get('PATH', ''))

    def fragment(body, read_aux=True):
        # As typesetScrap writes it: the .aux copy is read on the line of \begin{document}.
        line = f'\\AtBeginDocument{{\\csname @input\\endcsname{{{exp}/TeXShop-document.aux}}}}' if read_aux else ''
        (exp / 'file.tex').write_text('\\documentclass{article}\\usepackage{graphicx}\n' + line +
                                      '\\begin{document}\n' + body + '\n\\end{document}\n')
        for name in ('file.aux', 'file.log', 'file.pdf', 'file.fls', 'file.fdb_latexmk', 'chapter.aux'):
            (exp / name).unlink(missing_ok=True)

    def pdflatex():
        # As typesetFile runs a TeX program from Settings.
        return subprocess.run([tex, '--file-line-error', '-interaction=nonstopmode', f'-output-directory={exp}',
                               str(exp / 'file.tex')], cwd=doc, env=env, capture_output=True, text=True, timeout=120)

    body = ('\\includegraphics[width=1cm]{./Norms.pdf}\n{\\graphicspath{{./figs/}}\\includegraphics[width=1cm]{Plot.pdf}}\n'
            'See section \\ref{shared} on page \\pageref{shared}.\n\\include{chapter}\n'
            '\\newwrite\\w\\immediate\\openout\\w=figs/cache.dat \\immediate\\write\\w{experiment}\\immediate\\closeout\\w\n'
            '\\newwrite\\v\\immediate\\openout\\v=File.log \\immediate\\write\\v{experiment}\\immediate\\closeout\\v\n')
    fragment(body)
    result = pdflatex()
    log = (exp / 'file.log').read_text(errors='replace')
    assert result.returncode == 0, 'pdflatex typesets the fragment:\n' + result.stdout[-1500:]
    assert 'not found' not in log, 'images relative to the document, also with ./, are found'
    assert 'undefined' not in log, 'references from the document resolve'
    assert (exp / 'figs' / 'cache.dat').read_text() == 'experiment\n' and (exp / 'chapter.aux').exists(), \
        'what TeX writes goes to the Experiment folder'
    assert digest(doc) == before, 'pdflatex leaves every file of the document\'s folder unchanged'
    # The Experiment's own file.aux, not the document's file.aux of the same name, is read.
    fragment('\\section{A}\\label{own}Own: \\ref{own}.', read_aux=False)
    for _ in range(2):
        result = pdflatex()
    assert result.returncode == 0 and '{own}{{1}' in (exp / 'file.aux').read_text(), 'the Experiment reads its own file.aux'
    assert digest(doc) == before, 'the document\'s file.aux of the same name is left alone'
    # latexmk typesets more than once; every run reads the copy of the document's .aux.
    latexmk = shutil.which('latexmk', path=texdir)
    if latexmk:
        fragment('See section \\ref{shared} on page \\pageref{shared}. \\section{B}\\label{mine}\\ref{mine}')
        result = subprocess.run([latexmk, '-pdf', '-g', '-interaction=nonstopmode', f'-outdir={exp}', str(exp / 'file.tex')],
                                cwd=doc, env=env, capture_output=True, text=True, timeout=240)
        runs = (result.stdout + result.stderr).count('Run number')
        log = (exp / 'file.log').read_text(errors='replace')
        assert result.returncode == 0 and runs >= 2, f'latexmk typesets more than once ({runs} runs)'
        assert 'undefined' not in log, 'references from the document resolve in the last latexmk run'
        assert digest(doc) == before, 'latexmk leaves every file of the document\'s folder unchanged'
    # A fragment with an error fails, so that a passing typesetting check means a clean run.
    fragment('\\errmessage{intentional error}')
    assert pdflatex().returncode != 0, 'a TeX error makes the typesetting check fail'
    print('PASS: Experiment runs from the document\'s folder, finds ./ and \\graphicspath files, resolves the document\'s '
          'references with pdflatex' + (' and latexmk' if latexmk else '') + ', and writes only into its own folder')
