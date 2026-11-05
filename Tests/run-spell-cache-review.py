#!/usr/bin/env python3
"""Exercise the text-view mask cache using the actual masking implementation.

Panes on one text storage must share one mask, edits and rule changes must
reach every pane, and a long text must not be masked again on every keystroke.
--mutation no-defer masks long texts again after each change, and
--mutation unshared gives each request its own cache; both must fail.
"""
from pathlib import Path
import argparse,subprocess,tempfile,os
root=Path(__file__).resolve().parents[1]
ap=argparse.ArgumentParser();ap.add_argument('--mutation',choices=['no-defer','unshared']);args=ap.parse_args()
s=(root/'Sources/TSTextView.m').read_text()
a=s.index('- (TSSpellMask *)spellMask');b=s.index('- (void)pasteAsComment:',a)
methods=s[a:b]
methods=methods.replace('TSTextView *weakView', 'ProbeView *weakView')
support='#import "SessionChecker.h"\n#define NSSpellChecker SessionChecker\n'+(root/'Sources/TSSpellSupport.m').read_text()
mutations={'no-defer':('static NSUInteger sDeferredLength = 200000;','static NSUInteger sDeferredLength = NSUIntegerMax;'),
           'unshared':('TSSpellMaskCache *cache = objc_getAssociatedObject(storage, &sCacheKey);','TSSpellMaskCache *cache = nil;')}
if args.mutation:
    old,new=mutations[args.mutation]; assert old in support; support=support.replace(old,new)
program=r'''
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import "TSSpellExclusions.h"
#import "TSSpellSupport.h"
#import "SessionChecker.h"
@implementation SessionChecker
+ (instancetype)sharedSpellChecker { static SessionChecker *checker; if(!checker) checker=[self new]; return checker; }
- (BOOL)hasLearnedWord:(NSString *)word { abort(); }
- (void)unlearnWord:(NSString *)word { abort(); }
- (NSString *)language { return @"en"; }
- (NSArray *)availableLanguages { return @[@"en"]; }
- (void)updateSpellingPanelWithMisspelledWord:(NSString *)word {}
- (NSRange)checkSpellingOfString:(NSString *)s startingAt:(NSInteger)start language:(NSString *)language
                          wrap:(BOOL)wrap inSpellDocumentWithTag:(NSInteger)tag wordCount:(NSInteger *)count { return NSMakeRange(NSNotFound,0); }
@end
@interface ProbeView:NSTextView { __weak TSSpellMask *_spellMask; }
- (TSSpellMask *)spellMask;
- (TSSpellMask *)spellMaskForCheckingRange:(NSRange)range;
- (TSSpellMask *)freshSpellMask;
- (void)invalidateSpellMask;
- (void)showSpellingRulesProblems:(NSString *)problems;
@end
@implementation ProbeView
- (BOOL)usesTeXAwareSpellChecking { return YES; }
METHODS
@end
// Count the masks made, on any thread.
static atomic_ulong sMasks;
static IMP sMaskForText;
static TSSpellMask *CountingMaskForText(id self, SEL _cmd, NSString *text) {
 atomic_fetch_add(&sMasks,1); return ((TSSpellMask *(*)(id,SEL,NSString *))sMaskForText)(self,_cmd,text);
}
static ProbeView *View(NSTextStorage *s) {
 ProbeView *v=[[ProbeView alloc] initWithFrame:NSMakeRect(0,0,500,500)];
 v.continuousSpellCheckingEnabled=NO;v.grammarCheckingEnabled=NO;
 [v.layoutManager replaceTextStorage:s];return v;
}
static void Spin(double seconds) {
 NSDate *until=[NSDate dateWithTimeIntervalSinceNow:seconds];
 while(until.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
}
// Wait until the deferred masking of a long text has been installed.
static TSSpellMask *WaitForMask(ProbeView *v) {
 for(int k=0;k<500;k++){TSSpellMask *m=[v spellMask];if(m)return m;Spin(.02);}
 return nil;
}
static id SpellingState(NSTextView *v, NSUInteger i) {
 return [v.layoutManager temporaryAttribute:NSSpellingStateAttributeName atCharacterIndex:i effectiveRange:NULL];
}
int main(int argc,char **argv) { @autoreleasepool {
 [NSApplication sharedApplication];
 Method method=class_getInstanceMethod(TSSpellExclusions.class,@selector(maskForText:));
 sMaskForText=method_setImplementation(method,(IMP)CountingMaskForText);
 NSTextStorage *s=[[NSTextStorage alloc] initWithString:@"\\label{zzbad}"];
 ProbeView *a=View(s),*b=View(s);
 [a spellMask];[b spellMask];
 [s replaceCharactersInRange:NSMakeRange(0,s.length) withString:@"\\emph {zzbad}"];
 [a didChangeText];
 NSString *cached=[b spellMask].masked,*fresh=[b freshSpellMask].masked;
 printf("shared storage, same-length edit: cached=%s fresh=%s equal=%d\n",cached.UTF8String,fresh.UTF8String,[cached isEqualToString:fresh]);
 if(![cached isEqualToString:fresh]) return 2;

 // Panes share one mask, made once per change.
 atomic_store(&sMasks,0);
 [s replaceCharactersInRange:NSMakeRange(0,0) withString:@"x"];
 TSSpellMask *ma=[a spellMask],*mb=[b spellMask];
 printf("two panes after an edit: same mask=%d, masks made=%lu\n",ma==mb,(unsigned long)atomic_load(&sMasks));
 if(ma!=mb||atomic_load(&sMasks)!=1) { puts("FAIL: panes do not share one mask"); return 6; }
 for(int k=0;k<20;k++){
  [s replaceCharactersInRange:NSMakeRange(s.length,0) withString:@" \\ref{zzkey} word"];
  if(![[a spellMask].masked isEqualToString:[[TSSpellExclusions sharedExclusions] maskForText:s.string].masked]) { puts("FAIL: short text mask out of date"); return 7; }
 }

 [a setString:@"\\label{zzbad}"];[a spellMask];[b freshSpellMask];
 [@"command-names yes\ncheck-args label\n" writeToFile:@(getenv("TSSPELL_RULES")) atomically:YES encoding:NSUTF8StringEncoding error:NULL];
 [NSThread sleepForTimeInterval:1.1]; [a spellMask];
 cached=[b spellMask].masked;fresh=[b freshSpellMask].masked;
 printf("rules reload seen by another view: cached=%s fresh=%s equal=%d\n",cached.UTF8String,fresh.UTF8String,[cached isEqualToString:fresh]);
 if(![cached isEqualToString:fresh]) return 3;
 [@"command-names yes\nskip-args 1 label\n" writeToFile:@(getenv("TSSPELL_RULES")) atomically:YES encoding:NSUTF8StringEncoding error:NULL];
 [NSThread sleepForTimeInterval:1.1];

 // A long text: masked when editing pauses, not on every keystroke.
 NSMutableString *large=[NSMutableString string];
 while(large.length<1000000) [large appendString:@"ordinary text \\label{zzlabel} "];
 [s.mutableString setString:large];
 if(!WaitForMask(b)) { puts("FAIL: long text never masked"); return 8; }
 CFAbsoluteTime start=CFAbsoluteTimeGetCurrent();
 for(int i=0;i<120;i++) [b spellMask];
 printf("120 cached checks / 1M characters: %.3f ms\n",(CFAbsoluteTimeGetCurrent()-start)*1000);
 NSRange label=[s.string rangeOfString:@"zzlabel"], word=[s.string rangeOfString:@"ordinary"];
 atomic_store(&sMasks,0);
 double slowest=0;
 for(int k=0;k<50;k++){
  [s replaceCharactersInRange:NSMakeRange(s.length,0) withString:@"y"];
  CFAbsoluteTime t=CFAbsoluteTimeGetCurrent();
  TSSpellMask *pa=[a spellMaskForCheckingRange:label],*pb=[b spellMaskForCheckingRange:word];
  slowest=MAX(slowest,CFAbsoluteTimeGetCurrent()-t);
  if(pa||pb) { puts("FAIL: long text masked again at once"); return 9; }
  Spin(.01);
 }
 // What the check while typing marks meanwhile (no mask: as without TeX-aware spelling).
 for(ProbeView *v in @[a,b]) { [v setSpellingState:NSSpellingStateSpellingFlag range:label]; [v setSpellingState:NSSpellingStateSpellingFlag range:word]; }
 unsigned long during=atomic_load(&sMasks);
 printf("50 keystrokes in 1M characters, two panes: masks made while typing=%lu, slowest check %.3f ms\n",during,slowest*1000);
 if(during!=0) { puts("FAIL: long text masked again per keystroke"); return 10; }
 TSSpellMask *after=WaitForMask(a);
 unsigned long made=atomic_load(&sMasks);
 printf("after the pause: masks made=%lu, same in both panes=%d\n",made,after==[b spellMask]);
 if(!after||made!=1||after!=[b spellMask]) { puts("FAIL: one mask expected after the pause"); return 11; }
 if(![after.masked isEqualToString:[[TSSpellExclusions sharedExclusions] maskForText:s.string].masked]) { puts("FAIL: deferred mask out of date"); return 12; }
 BOOL cleared=!SpellingState(a,label.location)&&!SpellingState(b,label.location);
 BOOL kept=SpellingState(a,word.location)&&SpellingState(b,word.location);
 printf("marks set without a mask: excluded removed=%d, ordinary kept=%d\n",cleared,kept);
 if(!cleared||!kept) { puts("FAIL: marks not brought in line with the mask"); return 13; }

 [s.mutableString replaceCharactersInRange:NSMakeRange(0,5) withString:@"other"];
 if([b spellMask]) { puts("FAIL: stale mask returned"); return 4; }
 cached=WaitForMask(b).masked;fresh=[b freshSpellMask].masked;
 if(![cached isEqualToString:fresh]) return 4;
 NSTextStorage *replacement=[[NSTextStorage alloc] initWithString:@"replacement"];
 [b.layoutManager replaceTextStorage:replacement];
 cached=[b spellMask].masked;fresh=[b freshSpellMask].masked;
 if(![cached isEqualToString:fresh]) return 5;
 puts("PASS: panes share one mask; edits and rule generations reach both; long texts are masked when typing pauses.");
}return 0;}
'''.replace('METHODS',methods)
with tempfile.TemporaryDirectory(prefix='ts-spell-review-') as td:
 p=Path(td);(p/'test.m').write_text(program);(p/'support.m').write_text(support)
 rules=p/'rules.txt';rules.write_text('command-names yes\nskip-args 1 label\n')
 subprocess.run(['xcrun','clang','-fobjc-arc','-w','-DTSSPELL_STANDALONE_TEST','-I'+str(root/'Sources'),'-I'+str(root/'Tests/SpellCheck'),
     '-framework','Cocoa',str(p/'test.m'),str(p/'support.m'),str(root/'Sources/TSSpellExclusions.m'),'-o',str(p/'test')],check=True)
 result=subprocess.run([str(p/'test')],env=dict(os.environ,TSSPELL_RULES=str(rules)),timeout=120)
 if args.mutation:
  if result.returncode==0: raise SystemExit('FAIL: mutation %s was not detected'%args.mutation)
  print('PASS: mutation %s detected (exit %d).'%(args.mutation,result.returncode))
  raise SystemExit(0)
 if result.returncode!=0: raise SystemExit(result.returncode)
 subprocess.run(['xcrun','clang','-fobjc-arc','-w','-DTSSPELL_STANDALONE_TEST','-I'+str(root/'Sources'),'-framework','Foundation',str(root/'Tests/SpellCheck/mask.m'),str(root/'Sources/TSSpellExclusions.m'),'-o',str(p/'mask')],check=True)
 result=subprocess.check_output([str(p/'mask'),str(root/'Resources/TeXShop/SpellCheck/SpellingExclusions.txt'),str(root/'Tests/SpellCheck/cases.tex')])
 if result!=(root/'Tests/SpellCheck/cases.expected.txt').read_bytes(): raise SystemExit('FAIL: masking fixture')
 print('PASS: submitted masking-engine fixture')
