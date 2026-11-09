#!/usr/bin/env python3
"""Masking must stay linear on unbalanced input and give the masks of the direct scans.

With --mutation reference the timing is done with the direct scans, which must
then fail it.
"""
import argparse, os, subprocess, tempfile
from pathlib import Path
from source_tree import include_args
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--mutation',choices=['reference']);args=p.parse_args()
rules=root/'Resources/TeXShop/SpellCheck/SpellingExclusions.txt'
fixtures=[root/'Tests/SpellCheck'/n for n in ('cases.tex','patterns.tex','macros.tex','languages.tex')]
with tempfile.TemporaryDirectory(prefix='ts-spell-linear-') as td:
    t=Path(td)
    text=rules.read_text()
    assert 'comments          yes' in text
    other=text.replace('comments          yes','comments          no')+'\nskip-body german\nlanguage-switch shorthandsoff\n'
    (t/'other.txt').write_text(other)
    subprocess.run(['xcrun','clang','-O2','-fobjc-arc','-w','-DTSSPELL_STANDALONE_TEST',*include_args(root),
        '-framework','Foundation',str(root/'Tests/SpellCheck/linear.m'),str(root/'Sources/Editor/TSSpellExclusions.m'),
        '-o',str(t/'linear')],check=True)
    command=[str(t/'linear'),str(rules),str(t/'other.txt')]+[str(f) for f in fixtures]
    if args.mutation: command.append('--reference')
    result=subprocess.run(command,timeout=1800)
    if args.mutation:
        if result.returncode==0: raise SystemExit('FAIL: the direct scans passed the timing checks')
        print('PASS: the direct scans fail the timing checks (mutation detected).')
    elif result.returncode!=0:
        raise SystemExit(result.returncode)
