#!/usr/bin/env python3
"""Test independent review invalidation without opening the system spelling panel."""
import argparse, os, subprocess, tempfile
from pathlib import Path
from source_tree import include_args
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--mutation',choices=['responder','text','selection','panel-responder','no-sole','preload-multiple','all-editors','same-event','up-arrow','auto-hidden','auto-review','auto-accessory','auto-column','auto-guesses','change-view','change-current','change-no-review','change-status','end-review']);args=p.parse_args()
s='#import "SessionChecker.h"\n#define NSSpellChecker SessionChecker\n'+(root/'Sources/Editor/TSSpellSupport.m').read_text()
removed={'responder':'view.window.firstResponder == view &&',
         'text':'[view.string isEqualToString:sReviewText] &&',
         'selection':'NSEqualRanges(view.selectedRange, sReviewSelection)'}
if args.mutation in removed:
    s=s.replace(removed[args.mutation], 'YES' if args.mutation=='selection' else '')
mutations = {
    'change-view': ('textView == sReviewView && ReviewIsCurrent(textView)', 'ReviewIsCurrent(textView)'),
    'change-current': ('textView == sReviewView && ReviewIsCurrent(textView)', 'textView == sReviewView'),
    'change-no-review': ('sReviewWord.length == 0 || (textView', '(textView'),
    'change-status': ('ReviewIsCurrent(textView))) return NO;\n    sReplacementStatus.stringValue', 'ReviewIsCurrent(textView))) return NO;\n    if (0) sReplacementStatus.stringValue'),
    'end-review': ('    sReviewWord = nil;\n    sReviewText = nil;\n    sReplacementField.stringValue', '    sReviewText = nil;\n    sReplacementField.stringValue'),
    'all-editors': ('(sReplacementField.currentEditor &&\n             panel.firstResponder == sReplacementField.currentEditor)', '[panel.firstResponder isKindOfClass:NSTextView.class]'),
    'same-event': ('event == sPanelUpdateEvent ||', ''),
    'up-arrow': ('[keys characterAtIndex:0] != NSUpArrowFunctionKey &&', ''),
    'auto-hidden': ('checker.spellingPanel.isVisible &&', ''),
    'auto-review': ('ReviewIsCurrent(tv) &&', ''),
    'auto-accessory': ('checker.accessoryView == sReplacementField.superview &&', ''),
    'auto-column': ('table.tableColumns.count != 1 ||\n        ![source respondsToSelector:', '![source respondsToSelector:'),
    'auto-guesses': ('guesses.count == 1 && [guesses.firstObject isEqualToString:selected]', 'selected != nil'),
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
    subprocess.run(['xcrun','clang','-fobjc-arc','-DTSSPELL_STANDALONE_TEST',*include_args(root),
        '-I'+str(root/'Tests/SpellCheck'),'-framework','Cocoa',str(root/'Tests/SpellCheck/session.m'),str(t/'support.m'),
        str(root/'Sources/Editor/TSSpellExclusions.m'),'-o',str(t/'probe')],check=True)
    subprocess.run([str(t/'probe')],env=dict(os.environ,TSSPELL_RULES=str(root/'Resources/TeXShop/SpellCheck/SpellingExclusions.txt')),check=True,timeout=15)
