#!/usr/bin/env python3
"""Exercise the legacy menu compatibility path in memory without loading user files."""
from pathlib import Path
import subprocess,tempfile
from source_tree import include_args
r=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-legacy-menu-') as td:
 p=Path(td)/'probe'
 source=(r/'Sources/App/TSAppDelegate.m').read_text(encoding='latin1');start=source.index('- (void)finishMenuKeyEquivalentsConfigure\n');method=source[start:source.index('\n}',start)+2]
 method=method.replace('[NSDictionary dictionaryWithContentsOfFile:path]','FixtureEntries(path)')
 assert 'dictionaryWithContentsOfFile' not in method
 program=(r/'Tests/LegacyMenuKeys.m').read_text().replace('// APPLICATION_ENTRY',method)
 test=Path(td)/'test.m';test.write_text(program)
 subprocess.run(['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Wno-unused-parameter','-Werror',*include_args(r),'-I',str(r/'Tests'),'-framework','Cocoa',str(test),'-o',str(p)],check=True)
 subprocess.run([str(p),str(r/'Tests/Fixtures/LegacyKeyBindingTitles.json')],check=True)
