#!/usr/bin/env python3
"""Test independent review invalidation without opening the system spelling panel."""
import argparse, os, subprocess, tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--mutation',choices=['responder','text','selection','panel-responder','no-sole','preload-multiple']);args=p.parse_args()
s='#import "SessionChecker.h"\n#define NSSpellChecker SessionChecker\n'+(root/'Sources/TSSpellSupport.m').read_text()
removed={'responder':'view.window.firstResponder == view &&',
         'text':'[view.string isEqualToString:sReviewText] &&',
         'selection':'NSEqualRanges(view.selectedRange, sReviewSelection)'}
if args.mutation in removed:
    s=s.replace(removed[args.mutation], 'YES' if args.mutation=='selection' else '')
mutations = {
    'panel-responder': ('!panel.isVisible || table.window != panel ||',
                        '!panel.isVisible || table.window != panel || panel.firstResponder != table ||'),
    'no-sole': ('table.numberOfRows == 1 && table.numberOfSelectedRows == 1',
                'NO && table.numberOfRows == 1 && table.numberOfSelectedRows == 1'),
    'preload-multiple': ('table.numberOfRows == 1 && table.numberOfSelectedRows == 1',
                         'table.numberOfSelectedRows == 1'),
}
if args.mutation in mutations:
    old, new = mutations[args.mutation]
    assert old in s
    s=s.replace(old,new)
with tempfile.TemporaryDirectory(prefix='texshop-review-session-') as td:
    t=Path(td);(t/'support.m').write_text(s)
    subprocess.run(['xcrun','clang','-fobjc-arc','-DTSSPELL_STANDALONE_TEST','-I'+str(root/'Sources'),
        '-I'+str(root/'Tests/SpellCheck'),'-framework','Cocoa',str(root/'Tests/SpellCheck/session.m'),str(t/'support.m'),
        str(root/'Sources/TSSpellExclusions.m'),'-o',str(t/'probe')],check=True)
    subprocess.run([str(t/'probe')],env=dict(os.environ,TSSPELL_RULES=str(root/'Resources/TeXShop/SpellCheck/SpellingExclusions.txt')),check=True,timeout=15)
