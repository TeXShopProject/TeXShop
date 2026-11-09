#!/usr/bin/env python3
"""Learned-word lookup and Find Next runs, with a stand-in spell checker."""
import os, subprocess, tempfile
from pathlib import Path
from source_tree import include_args
root=Path(__file__).resolve().parents[1]
s='#import "SessionChecker.h"\n#define NSSpellChecker SessionChecker\n'+(root/'Sources/Editor/TSSpellSupport.m').read_text()
with tempfile.TemporaryDirectory(prefix='texshop-spell-support-') as td:
    t=Path(td);(t/'support.m').write_text(s)
    subprocess.run(['xcrun','clang','-fobjc-arc','-w','-DTSSPELL_STANDALONE_TEST',*include_args(root),
        '-I'+str(root/'Tests/SpellCheck'),'-framework','Cocoa',str(root/'Tests/SpellCheck/support.m'),str(t/'support.m'),
        str(root/'Sources/Editor/TSSpellExclusions.m'),'-o',str(t/'probe')],check=True)
    subprocess.run([str(t/'probe')],env=dict(os.environ,TSSPELL_RULES=str(root/'Resources/TeXShop/SpellCheck/SpellingExclusions.txt')),check=True,timeout=60)
