#!/usr/bin/env python3
"""Check the default spelling exclusions for common packages.

Tests/SpellCheck/packages.tex uses the commands and environments of amsmath,
mathtools, graphicx, xcolor, tikz, geometry, fancyhdr, microtype, booktabs,
tabularx, enumitem, hyperref, cleveref, biblatex, natbib and siunitx. Words
starting with skipqzx are not prose and must be masked by the shipped
SpellingExclusions.txt; words starting with keepqzx are prose and must stay.
"""
from pathlib import Path
import re,subprocess,sys,tempfile
from source_tree import include_args
root=Path(__file__).resolve().parents[1]
rules=root/'Resources/TeXShop/SpellCheck/SpellingExclusions.txt'
source=root/'Tests/SpellCheck/packages.tex'
with tempfile.TemporaryDirectory() as t:
    exe=Path(t)/'mask'
    subprocess.run(['xcrun','clang','-I',str(root/'Tests'),'-fobjc-arc','-w','-DTSSPELL_STANDALONE_TEST',
                    *include_args(root),'-framework','Foundation',str(root/'Tests/SpellCheck/mask.m'),
                    str(root/'Sources/Editor/TSSpellExclusions.m'),'-o',str(exe)],check=True)
    run=subprocess.run([str(exe),str(rules),str(source)],capture_output=True,text=True,check=True)
if run.stderr.strip():
    sys.exit('rules file problems:\n'+run.stderr)
masked=run.stdout
text=source.read_text()
leaked=sorted(set(re.findall(r'skipqzx\d*[a-z]*',masked)))
wanted=sorted(set(re.findall(r'keepqzx\d+',text)))
lost=[w for w in wanted if not re.search(re.escape(w)+r'(?!\d)',masked)]
if leaked or lost:
    sys.exit('not masked: %s\nmasked wrongly: %s'%(', '.join(leaked) or '-',', '.join(lost) or '-'))
print('PASS: %d non-prose words masked, %d prose words kept'%(len(set(re.findall(r'skipqzx\d+',text))),len(wanted)))
