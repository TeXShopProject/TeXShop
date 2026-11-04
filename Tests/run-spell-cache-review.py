#!/usr/bin/env python3
"""Exercise the submitted text-view cache using the actual masking implementation."""
from pathlib import Path
import subprocess,tempfile,os
root=Path(__file__).resolve().parents[1]
s=(root/'Sources/TSTextView.m').read_text()
a=s.index('- (TSSpellMask *)spellMask');b=s.index('- (void)pasteAsComment:',a)
methods=s[a:b]
methods=methods.replace('TSTextView *weakView', 'ProbeView *weakView')
program=r'''
#import <Cocoa/Cocoa.h>
#import "TSSpellExclusions.h"
@interface ProbeView:NSTextView { TSSpellMask *_spellMask; NSUInteger _spellMaskLength, _spellRulesGeneration; NSString *_spellMaskText; }
- (TSSpellMask *)spellMask;
- (TSSpellMask *)freshSpellMask;
- (void)invalidateSpellMask;
@end
@implementation ProbeView
METHODS
@end
static ProbeView *View(NSTextStorage *s) {
 ProbeView *v=[[ProbeView alloc] initWithFrame:NSMakeRect(0,0,500,500)];
 [v.layoutManager replaceTextStorage:s];return v;
}
int main(int argc,char **argv) { @autoreleasepool {
 [NSApplication sharedApplication];
 NSTextStorage *s=[[NSTextStorage alloc] initWithString:@"\\label{zzbad}"];
 ProbeView *a=View(s),*b=View(s);
 [a spellMask];[b spellMask];
 [s replaceCharactersInRange:NSMakeRange(0,s.length) withString:@"\\emph {zzbad}"];
 [a didChangeText];
 NSString *cached=[b spellMask].masked,*fresh=[b freshSpellMask].masked;
 printf("shared storage, same-length edit: cached=%s fresh=%s equal=%d\n",cached.UTF8String,fresh.UTF8String,[cached isEqualToString:fresh]);
 if(![cached isEqualToString:fresh]) return 2;
 [a setString:@"\\label{zzbad}"];[a spellMask];[b freshSpellMask];
 [@"command-names yes\ncheck-args label\n" writeToFile:@(getenv("TSSPELL_RULES")) atomically:YES encoding:NSUTF8StringEncoding error:NULL];
 [NSThread sleepForTimeInterval:1.1]; [a spellMask];
 cached=[b spellMask].masked;fresh=[b freshSpellMask].masked;
 printf("rules reload seen by another view: cached=%s fresh=%s equal=%d\n",cached.UTF8String,fresh.UTF8String,[cached isEqualToString:fresh]);
 if(![cached isEqualToString:fresh]) return 3;
 puts("PASS: shared text-storage edits and rule generations invalidate both caches.");
}return 0;}
'''.replace('METHODS',methods)
with tempfile.TemporaryDirectory(prefix='ts-spell-review-') as td:
 p=Path(td);(p/'test.m').write_text(program);rules=p/'rules.txt';rules.write_text('command-names yes\nskip-args 1 label\n')
 subprocess.run(['xcrun','clang','-fobjc-arc','-w','-DTSSPELL_STANDALONE_TEST','-I'+str(root/'Sources'),'-framework','Cocoa',str(p/'test.m'),str(root/'Sources/TSSpellExclusions.m'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],env=dict(os.environ,TSSPELL_RULES=str(rules),CFFIXED_USER_HOME=str(p/'home')),check=True)
 subprocess.run(['xcrun','clang','-fobjc-arc','-w','-DTSSPELL_STANDALONE_TEST','-I'+str(root/'Sources'),'-framework','Foundation',str(root/'Tests/SpellCheck/mask.m'),str(root/'Sources/TSSpellExclusions.m'),'-o',str(p/'mask')],check=True)
 result=subprocess.check_output([str(p/'mask'),str(root/'Resources/TeXShop/SpellCheck/SpellingExclusions.txt'),str(root/'Tests/SpellCheck/cases.tex')])
 assert result==(root/'Tests/SpellCheck/cases.expected.txt').read_bytes()
 print('PASS: submitted masking-engine fixture')
