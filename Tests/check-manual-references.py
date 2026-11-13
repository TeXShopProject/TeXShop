#!/usr/bin/env python3
"""Check the cross-references of the TeXShop manual and its two copies of Manual.pdf.

Every \\ref, \\cref and \\Cref outside comments and verbatim text in Manual.tex names a
\\label that is also outside them, so a section that is commented out leaves no
reference to it behind. The Manual.pdf next to the source and the one in
Resources/Interfaces/Base.lproj are the same file. Nothing is typeset.
"""
import argparse, re, sys
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['ref-to-commented-label', 'label-removed', 'copies-differ'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = (root/'DocumentSources/Manual Source/Manual.tex').read_text(encoding='utf-8')
pdfs = [(root/'DocumentSources/Manual Source/Manual.pdf').read_bytes(),
        (root/'Resources/Interfaces/Base.lproj/Manual.pdf').read_bytes()]

commented = re.findall(r'^\s*%.*?\\label\{([^}]*)\}', source, flags=re.M)
assert commented, 'The manual keeps commented-out sections with labels'
if args.mutation == 'ref-to-commented-label':
    source += '\nSee \\cref{%s}.\n' % commented[0]
elif args.mutation == 'label-removed':
    # The label of the section on splitting windows, which other sections refer to.
    assert source.count('\\label{Splitting_Windows_Section}') == 1
    source = source.replace('\\label{Splitting_Windows_Section}', '')
elif args.mutation == 'copies-differ':
    pdfs[1] = pdfs[1] + b'\n'

def uncommented(text):
    return '\n'.join(re.split(r'(?<!\\)%', line, maxsplit=1)[0] for line in text.split('\n'))

text = re.sub(r'\\begin\{verbatim\}.*?\\end\{verbatim\}', '', uncommented(source), flags=re.S)
labels = set(re.findall(r'\\label\{([^}]*)\}', text))
refs = [name.strip() for group in re.findall(r'\\(?:ref|cref|Cref|pageref)\{([^}]*)\}', text) for name in group.split(',')]
failures = []
missing = sorted(set(refs) - labels)
if missing:
    failures.append('references to labels that are missing or commented out: ' + ', '.join(missing))
if pdfs[0] != pdfs[1]:
    failures.append('the two copies of Manual.pdf differ')

if args.mutation:
    assert failures, 'mutation not detected: ' + args.mutation
    print('PASS: detected mutation %s: %s' % (args.mutation, failures[0]))
elif failures:
    sys.exit('FAIL: ' + '; '.join(failures))
else:
    print('PASS: the %d references of the manual name %d labels outside comments; both copies of Manual.pdf are the same'
          % (len(refs), len(labels)))
