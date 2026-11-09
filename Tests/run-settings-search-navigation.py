#!/usr/bin/env python3
"""Exercise the production search window without opening it or writing defaults."""
from pathlib import Path
import argparse, subprocess, tempfile
parser=argparse.ArgumentParser();parser.add_argument("--mutations",action="store_true");args=parser.parse_args()
r=Path(__file__).resolve().parents[1]
expected_failures={'back-clears-query': 'Back navigates while keeping search active', 'search-enables-forward': 'Search cannot enable unavailable forward navigation', 'clear-rewinds-category': 'Clearing search stays in the current pane and does not require a navigation commit', 'category-results': 'Two settings in one category produce separate results', 'highlight-first-result': 'A second result in the same pane changes the target without duplicating category history', 'search-does-not-persist': 'Search navigation persists its current category'}
with tempfile.TemporaryDirectory(prefix='texshop-search-navigation-') as directory:
    p=Path(directory)
    subprocess.run(['xcrun','ibtool','--compile',str(p/'SettingsWindow.nib'),str(r/'Resources/SettingsWindow.xib')],check=True)
    sources=sorted((r/'Sources').glob('TSSettings*.m'))+[r/'Sources/TSPrefPaneLayout.m']
    compile_command=['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Wno-unused-parameter','-Werror','-mmacosx-version-min=14.6','-I',str(r/'Sources'),'-I',str(r/'Tests'),'-framework','Cocoa',str(r/'Tests/SettingsSearchNavigation.m'),*map(str,sources),'-o',str(p/'probe')]
    subprocess.run(compile_command,check=True)
    subprocess.run([str(p/'probe'),str(p/'SettingsWindow.nib')],check=True,timeout=60)
    if args.mutations:
        mutations=[
            ('back-clears-query','TSSettingsWindowController.m','    [self.history goBack]; [self displayCurrentCategory];','    if (self.searchQuery.length) { [self setSettingsSearchQuery:@""]; return; } [self.history goBack]; [self displayCurrentCategory];'),
            ('search-enables-forward','TSSettingsWindowController.m','setEnabled:self.history.forwardIdentifier != nil','setEnabled:self.searchQuery.length || self.history.forwardIdentifier != nil'),
            ('clear-rewinds-category','TSSettingsWindowController.m','    if (!effective.length) {','    if (!effective.length) { [self.history goBack]; [self displayCurrentCategory];'),
            ('category-results','TSSettingsSearch.m',' : entry.targetIdentifier;', ' : category;'),
            ('highlight-first-result','TSSettingsWindowController.m','self.selectedSearchResult : nil;', 'self.searchResults.firstObject : nil;'),
            ('search-does-not-persist','TSSettingsWindowController.m','    [self.stateStore saveSelectedCategory:identifier];','    if (!self.searchQuery.length) [self.stateStore saveSelectedCategory:identifier];'),
        ]
        for name,filename,old,new in mutations:
            original=r/'Sources'/filename;text=original.read_text()
            assert text.count(old)==1,(name,text.count(old))
            changed=p/filename;changed.write_text(text.replace(old,new))
            command=[str(changed) if arg==str(original) else arg for arg in compile_command]
            subprocess.run(command,check=True)
            result=subprocess.run([str(p/'probe'),str(p/'SettingsWindow.nib')],capture_output=True,text=True,timeout=60)
            assert result.returncode and 'FAIL: '+expected_failures[name] in result.stderr,(name,result.returncode,result.stderr)
            print('DETECTED',name,result.stderr.strip(),flush=True)
        subprocess.run(compile_command,check=True)
        subprocess.run([str(p/'probe'),str(p/'SettingsWindow.nib')],check=True,timeout=60)
