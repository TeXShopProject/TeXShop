#!/usr/bin/env python3
"""Experiment typesetting finds the document's files and references (#8).

The Experiment folder gets symbolic links to the items of the document's folder,
so that \\includegraphics{./Norms.pdf} and \\graphicspath{{./figs/}}, which TeX
does not look up in TEXINPUTS, work as in the document; names beginning with
"file." are left to the Experiment. The document's .aux is copied up to its last
complete line, so that \\ref resolves. Removing the folder leaves the document's
files alone. With TeX Live, pdflatex typesets a real Experiment file.
"""
from pathlib import Path
import argparse, os, shutil, subprocess, tempfile
from source_tree import include_args

MUTATIONS = {
    'no-links': ('    if (items.count > TSExperimentMaximumLinks) return 0;\n',
                 '    if (items.count > TSExperimentMaximumLinks || YES) return 0;\n'),
    'links-experiment-files': ('        if ([item isEqualToString:name] || [item hasPrefix:prefix]) continue;\n', ''),
    'no-limit': ('    if (items.count > TSExperimentMaximumLinks) return 0;\n', ''),
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
scrap = (root / 'Sources/Document/TSDocument-Scrap.m').read_text(encoding='latin1')
assert 'linkItemsOfDirectory:[NSURL fileURLWithPath:fileLocation isDirectory:YES]' in scrap, 'Experiment links the folder'
assert 'URLByAppendingPathExtension:@"aux"]' in scrap and 'URLByAppendingPathComponent:@"file.aux"]' in scrap, 'Experiment copies the .aux'

program = r'''
#import <Foundation/Foundation.h>
#import "TSExperimentJob.h"
static void check(BOOL ok, const char *message) { if (!ok) { fprintf(stderr, "FAIL: %s\n", message); exit(1); } }
int main(int argc, char **argv) { @autoreleasepool {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *doc = [NSURL fileURLWithPath:@(argv[1]) isDirectory:YES], *exp = [NSURL fileURLWithPath:@(argv[2]) isDirectory:YES];
    NSUInteger count = [TSExperimentJob linkItemsOfDirectory:doc intoDirectory:exp exceptName:@"file"];
    NSDictionary *norms = [fm attributesOfItemAtPath:[exp URLByAppendingPathComponent:@"Norms.pdf"].path error:NULL];
    check([norms[NSFileType] isEqual:NSFileTypeSymbolicLink], "a file of the document's folder is linked");
    check([[fm destinationOfSymbolicLinkAtPath:[exp URLByAppendingPathComponent:@"figs"].path error:NULL]
              isEqualToString:[doc URLByAppendingPathComponent:@"figs"].path], "a subfolder is linked to the document's");
    check(![fm fileExistsAtPath:[exp URLByAppendingPathComponent:@"file.aux"].path], "names beginning with file. are not linked");
    check(![[fm attributesOfItemAtPath:[exp URLByAppendingPathComponent:@"file.tex"].path error:NULL][NSFileType] isEqual:NSFileTypeSymbolicLink],
          "the Experiment's own file.tex is kept");
    check(count == 4, "every other item is linked");
    check([TSExperimentJob copyAuxiliaryFile:[doc URLByAppendingPathComponent:@"main.aux"] toURL:[exp URLByAppendingPathComponent:@"file.aux"]],
          "the document's .aux is copied");
    NSString *aux = [NSString stringWithContentsOfURL:[exp URLByAppendingPathComponent:@"file.aux"] encoding:NSUTF8StringEncoding error:NULL];
    check([aux hasPrefix:@"\\relax"] && [aux hasSuffix:@"{{3}{7}}\n"], "the copy ends with the last complete line");
    check(![TSExperimentJob copyAuxiliaryFile:[doc URLByAppendingPathComponent:@"missing.aux"] toURL:[exp URLByAppendingPathComponent:@"x.aux"]],
          "a missing .aux is not copied");
    NSURL *crowded = [NSURL fileURLWithPath:@(argv[3]) isDirectory:YES], *other = [NSURL fileURLWithPath:@(argv[4]) isDirectory:YES];
    check([TSExperimentJob linkItemsOfDirectory:crowded intoDirectory:other exceptName:@"file"] == 0 &&
          [fm contentsOfDirectoryAtPath:other.path error:NULL].count == 0, "a folder with too many items is not mirrored");
    printf("linked %lu\n", (unsigned long)count);
    return 0;
}}
'''
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
    (doc / 'main.tex').write_text('main\n')
    # Written while the document is typeset: the last line is not finished yet.
    (doc / 'main.aux').write_text('\\relax\n\\newlabel{x}{{3}{7}}\n\\newlabel{half}{{')
    (doc / 'file.aux').write_text('not the Experiment\'s\n')
    (doc / 'file.tex').write_text('the document\'s own file.tex\n')
    experiment = ('\\documentclass{article}\\usepackage{graphicx}\\begin{document}\n'
                  '\\includegraphics[width=1cm]{./Norms.pdf}\n'
                  '{\\graphicspath{{./figs/}}\\includegraphics[width=1cm]{Plot.pdf}}\n'
                  'See section \\ref{x} on page \\pageref{x}.\n\\end{document}\n')
    (exp / 'file.tex').write_text(experiment)
    for k in range(2001):
        (crowded / f'item{k}').write_text('')
    run = subprocess.run([str(exe), str(doc), str(exp), str(crowded), str(other)], capture_output=True, text=True)
    if args.mutation:
        assert run.returncode == 1, (args.mutation, run.stdout, run.stderr)
        print(f'PASS: detected mutation {args.mutation}: {run.stderr.strip()}')
        raise SystemExit(0)
    if run.returncode:
        raise SystemExit(run.stderr)
    tex = shutil.which('pdflatex', path='/Applications/TeXLive/2026/bin/universal-darwin:' + os.environ.get('PATH', ''))
    if tex:
        env = dict(os.environ, TEXINPUTS=f'.:{doc}:')
        result = subprocess.run([tex, '-interaction=nonstopmode', 'file.tex'], cwd=exp, env=env,
                                capture_output=True, text=True, timeout=120)
        log = (exp / 'file.log').read_text(errors='replace')
        assert 'not found' not in log, 'images relative to the document are found'
        assert 'undefined' not in log and 'Reference' not in log, 'references from the document resolve'
        assert (exp / 'file.pdf').exists(), result.stdout[-2000:]
        print('PASS: pdflatex finds ./ and \\graphicspath images and resolves \\ref and \\pageref from the .aux')
    else:
        print('SKIP: no pdflatex for the typesetting check')
    # Removing the Experiment folder the way the console does removes only the links.
    remover = t / 'remove.m'
    remover.write_text('#import <Foundation/Foundation.h>\nint main(int c,char**v){@autoreleasepool{'
                       'return [NSFileManager.defaultManager removeItemAtURL:[NSURL fileURLWithPath:@(v[1])] error:NULL] ? 0 : 1;}}\n')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation', str(remover), '-o', str(t / 'remove')], check=True)
    subprocess.run([str(t / 'remove'), str(exp)], check=True)
    assert not exp.exists(), 'the Experiment folder is removed'
    assert (doc / 'Norms.pdf').read_bytes() == pdf and (doc / 'figs' / 'Plot.pdf').read_bytes() == pdf \
        and (doc / 'file.tex').exists() and (doc / 'main.aux').exists(), 'removing the folder leaves the document\'s files'
    print('PASS: Experiment folder links the document\'s items, copies its .aux and removes only the links')
