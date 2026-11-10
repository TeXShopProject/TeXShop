#!/usr/bin/env python3
"""Check the default spelling exclusions for common packages.

Tests/SpellCheck/packages.tex uses the commands and environments of amsmath,
mathtools, graphicx, xcolor, tikz, geometry, fancyhdr, microtype, booktabs,
tabularx, enumitem, hyperref, cleveref, biblatex, natbib and siunitx. Words
starting with skipqzx are not prose and must be masked by the shipped
SpellingExclusions.txt; words starting with keepqzx are prose and must stay.

A second document defines commands with the names of package commands, such as
\\unit and \\qty: package-args must leave them to the document's own definition,
while rules of the user's own (skip-args, skip-args-matching) still apply. It
also puts arguments on the next line, after a comment or a CRLF line end, which
are still arguments, and after a blank line, which is not.
"""
from pathlib import Path
import argparse,re,subprocess,sys,tempfile
from source_tree import include_args
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation',choices=['package-args-as-skip-args','defined-ignored','user-rules-yield',
                                          'no-newline','two-line-ends','no-comment'])
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
rules=root/'Resources/TeXShop/SpellCheck/SpellingExclusions.txt'
source=root/'Tests/SpellCheck/packages.tex'
engine=(root/'Sources/Editor/TSSpellExclusions.m').read_text()
rules_text=rules.read_text()
engine_mutations={
    'defined-ignored':('if (!count && ![m->definedCommands containsObject:name]) count = rules.packageArgs[name];',
                       'if (!count) count = rules.packageArgs[name];'),
    'user-rules-yield':('            NSNumber *count = rules.skipArgs[name];\n',
                        '            NSNumber *count = [m->definedCommands containsObject:name] ? nil : rules.skipArgs[name];\n'),
    'no-newline':('    if (k < n && IsNewline(src[k])) {','    if (NO) {'),
    'two-line-ends':("        while (k < n && (src[k] == ' ' || src[k] == '\\t')) k++;\n        if (k < n && (src[k] == '{' || src[k] == '[')) return k;",
                     "        while (k < n && (src[k] == ' ' || src[k] == '\\t' || IsNewline(src[k]))) k++;\n        if (k < n && (src[k] == '{' || src[k] == '[')) return k;"),
    'no-comment':("    if (k < n && src[k] == '%') while (k < n && !IsNewline(src[k])) k++;\n",''),
}
if args.mutation in engine_mutations:
    old,new=engine_mutations[args.mutation]
    assert engine.count(old)==1,args.mutation
    engine=engine.replace(old,new)
if args.mutation=='package-args-as-skip-args':
    assert rules_text.count('\npackage-args  ')>10
    rules_text=rules_text.replace('\npackage-args  ','\nskip-args  ')
conflicts=('% Commands that packages define, defined by the document itself: their text is\n'
           '% checked. Words beginning skipqzx are not prose; words beginning keepqzx are.\n'
           '\\newcommand{\\unit}[1]{#1}\n'
           '\\newcommand{\\num}[1]{\\textbf{#1}}\n'
           '\\newcommand{\\tag}[1]{#1}\n'
           '\\newcommand{\\qty}[1]{#1}\n'
           '\\def\\si#1{#1}\n'
           '\\unit{keepqzx1 text} \\num{keepqzx2 bold} \\tag{keepqzx3 tagged} \\si{keepqzx4 defined}\n'
           '\\qty{keepqzx5 first} {keepqzx6 second}\n'
           '% A macro of the document that hands its argument to a reference is still skipped.\n'
           '\\newcommand{\\ang}[1]{see \\ref{#1}}\n'
           '\\ang{skipqzx1}\n'
           '% Package commands that the document does not define keep their rules.\n'
           '\\SI{skipqzx2}{skipqzx3} \\textcolor{skipqzx4}{keepqzx7 coloured} \\crefname{skipqzx5}{skipqzx6}{skipqzx7}\n'
           '% Rules of the user\'s own still apply to a command the document defines.\n'
           '\\renewcommand{\\label}[1]{#1}\\label{skipqzx8}\n'
           '\\newcommand{\\myref}[1]{#1}\\myref{skipqzx9}\n'
           '% Arguments on the next line, after a comment, or after a CRLF line end.\n'
           '\\begin{tabularx}{\\linewidth}\n'
           '{skipqzx10}keepqzx8 & keepqzx9\\\\\n'
           '\\end{tabularx}\n'
           '\\begin{tabularx}{\\linewidth}% a comment\n'
           '  {skipqzx11} keepqzx10\n'
           '\\end{tabularx}\n'
           '\\begin{tabulary}{skipqzx12}\r\n'
           '{skipqzx13} keepqzx11\r\n'
           '\\end{tabulary}\n'
           '\\SI{skipqzx14}\n'
           '[skipqzx15]{skipqzx16} keepqzx12\n'
           '% A blank line ends the arguments.\n'
           '\\SI{skipqzx17}\n'
           '\n'
           '{keepqzx13 new paragraph}\n'
           '\\begin{tabularx}{skipqzx18}\n'
           '\n'
           '{keepqzx14 after a blank line}\n'
           '\\end{tabularx}\n'
           '\\num{keepqzx15 used again}\n')
failures=[]
with tempfile.TemporaryDirectory() as t:
    t=Path(t)
    (t/'TSSpellExclusions.m').write_text(engine)
    (t/'rules.txt').write_text(rules_text)
    (t/'conflicts.tex').write_bytes(conflicts.encode())
    exe=t/'mask'
    subprocess.run(['xcrun','clang','-I',str(root/'Tests'),'-fobjc-arc','-w','-DTSSPELL_STANDALONE_TEST',
                    *include_args(root),'-framework','Foundation',str(root/'Tests/SpellCheck/mask.m'),
                    str(t/'TSSpellExclusions.m'),'-o',str(exe)],check=True)
    for name,path in (('packages.tex',source),('conflicts',t/'conflicts.tex')):
        run=subprocess.run([str(exe),str(t/'rules.txt'),str(path)],capture_output=True,text=True,check=True)
        if run.stderr.strip():
            sys.exit('rules file problems:\n'+run.stderr)
        masked=run.stdout
        text=path.read_bytes().decode()
        leaked=sorted(set(re.findall(r'skipqzx\d*[a-z]*',masked)))
        wanted=sorted(set(re.findall(r'keepqzx\d+',text)))
        lost=[w for w in wanted if not re.search(re.escape(w)+r'(?!\d)',masked)]
        if leaked or lost:
            failures.append('%s: not masked: %s; masked wrongly: %s'%(name,', '.join(leaked) or '-',', '.join(lost) or '-'))
        else:
            print('PASS: %s: %d non-prose words masked, %d prose words kept'%(
                name,len(set(re.findall(r'skipqzx\d+',text))),len(wanted)))
if args.mutation:
    assert failures, 'mutation %s not detected'%args.mutation
    print('PASS: detected mutation %s: %s'%(args.mutation,failures[0]))
elif failures:
    sys.exit('\n'.join(failures))
