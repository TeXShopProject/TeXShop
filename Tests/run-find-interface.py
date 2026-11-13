#!/usr/bin/env python3
"""Execute the document's production notification method on unordered text views.
The document lifetime is replaced; the method and registration are read verbatim.
"""
from pathlib import Path
import subprocess,tempfile,argparse
from source_tree import include_args
r=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--mutations',action='store_true');args=p.parse_args()
s=(r/'Sources/Document/TSDocument.m').read_text();start=s.index('- (void)findInterfacePreferencesChanged:');method=s[start:s.index('\n}',start)+2]
registration='[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(findInterfacePreferencesChanged:) name:TSFindMethodChangedNotification object:nil];'
assert s.count(registration)==1,'Production documents register for find-interface updates'
program=r'''
#import "TestAppKitIsolation.h"
#import "TSFindInterface.h"
#import "TSAdvancedFindPanelController.h"
#import "TSAdvancedFindHighlights.h"
#import "TSSettingsChangeNote.h"
#import "TSPreferenceKey.h"
#import "globals.h"
#undef SUD
#define SUD TSIsolatedAppKitDefaults
static void Check(BOOL ok,NSString *message){if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
@interface FindDocumentProbe:NSObject { NSTextView *textView1,*textView2,*outputText; }
@property NSTextView *logTextView;
- (NSArray<NSTextView *> *)views;
@end
@implementation FindDocumentProbe
- (instancetype)init {self=[super init];if(self){textView1=[NSTextView new];textView2=[NSTextView new];outputText=[NSTextView new];self.logTextView=[NSTextView new];REGISTRATION}return self;}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
- (NSArray<NSTextView *> *)views{return @[textView1,textView2,outputText,self.logTextView];}
METHOD
@end
int main(int argc,char **argv){@autoreleasepool{
 TSInstallAppKitIsolation();[NSApplication sharedApplication];
 NSInteger launch=argc>1?atoi(argv[1]):0;TSSettingsRememberLaunchValue(FindMethodKey,@(launch));
 NSArray *documents=@[[FindDocumentProbe new],[FindDocumentProbe new]];
 for(FindDocumentProbe *document in documents)for(NSTextView *view in document.views)TSConfigureFindInterface(view,launch,NO);
 NSMutableArray *scrollViews=[NSMutableArray array];
 for(FindDocumentProbe *document in documents)for(NSTextView *view in document.views){NSScrollView *scroll=[NSScrollView new];scroll.documentView=view;[scrollViews addObject:scroll];}
 NSInteger effective=launch;
 for(NSNumber *method in @[@1,@3,@0,@2,@0,@1,@3,@1])for(NSNumber *incremental in @[@YES,@NO]){
  for(FindDocumentProbe *document in documents)[TSAdvancedFindHighlights highlightsForTextStorage:document.views[0].textStorage].ranges=@[[NSValue valueWithRange:NSMakeRange(0,0)]];
  for(NSScrollView *scroll in scrollViews)scroll.findBarVisible=YES;
  [SUD setInteger:method.integerValue forKey:FindMethodKey];[SUD setBool:incremental.boolValue forKey:IncrementalSearchKey];
  [NSNotificationCenter.defaultCenter postNotificationName:TSFindMethodChangedNotification object:nil];
  if(launch!=2 && method.integerValue!=2)effective=method.integerValue;
  for(FindDocumentProbe *document in documents)for(NSTextView *view in document.views){
   if(launch!=2 && method.integerValue==0)Check(!view.enclosingScrollView.findBarVisible,@"Switching to the panel closes every visible find bar");
   Check(view.usesFindBar==(effective==1) && view.usesFindPanel==(effective!=1),@"All source split views, console and log follow the effective find interface");
   Check(([TSAdvancedFindHighlights existingHighlightsForTextStorage:document.views[0].textStorage].ranges.count==0)==(method.integerValue!=3),@"Leaving the Advanced Find panel removes its highlights");
   if(launch!=2 && method.integerValue!=2)Check(view.incrementalSearchingEnabled==(effective==1&&incremental.boolValue),@"Incremental searching is enabled only in the requested find bar");
  }
 }
 puts("PASS: extracted document observer and registration, two documents/four real text views, panel/bar/OgreKit and incremental state");
}return 0;}
'''.replace('REGISTRATION',registration).replace('METHOD',method)
with tempfile.TemporaryDirectory(prefix='texshop-find-interface-')as tmp:
 d=Path(tmp);source=d/'probe.m';header=d/'TSFindInterface.h';original=(r/'Sources/Editor/TSFindInterface.h').read_text()
 def run(body=program,interface=original):
  source.write_text(body);header.write_text(interface)
  subprocess.run(['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-I',str(d),*include_args(r),'-I',str(r/'Tests'),'-framework','Cocoa',str(source),str(r/'Sources/Settings/TSSettingsChangeNote.m'),str(r/'Sources/Settings/TSPrefPaneLayout.m'),str(r/'Sources/App/globals.m'),*map(str,sorted((r/'Sources/Find').glob('*.m'))),'-o',str(d/'probe')],check=True)
  results=[subprocess.run([str(d/'probe'),str(v)],capture_output=True,text=True,timeout=30)for v in [0,1,2]]
  return results
 for result in run():assert result.returncode==0,result.stderr;print(result.stdout,flush=True)
 if args.mutations:
  cases=[]
  for view in ['textView1','textView2','outputText','self.logTextView']:
   old='TSConfigureFindInterface('+view+', current, incremental);';assert program.count(old)==1;cases.append((view,program.replace(old,';'),original,'All source split views'))
  cases.append(('ignore-startup-ogre',program.replace('current == 2 || (initial != nil && initial.integerValue == 2)','current == 2 || (initial != nil && NO)'),original,'All source split views'))
  cases.append(('bar-flag',program,original.replace('view.usesFindBar = method == TSFindMethodFindBar;','view.usesFindBar = NO;'),'All source split views'))
  cases.append(('panel-flag',program,original.replace('view.usesFindPanel = method != TSFindMethodFindBar;','view.usesFindPanel = YES;'),'All source split views'))
  cases.append(('incremental',program,original.replace('method == TSFindMethodFindBar && incremental','NO && incremental'),'Incremental searching'))
  cases.append(('reverse-panel',program.replace('NSInteger current = [SUD integerForKey:FindMethodKey];','NSInteger current = [SUD integerForKey:FindMethodKey]; if (current == 0) return;'),original,'Switching to the panel closes every visible find bar'))
  cases.append(('visible-bar',program,original.replace('if (method != TSFindMethodFindBar) view.enclosingScrollView.findBarVisible = NO;',';'),'Switching to the panel closes every visible find bar'))
  cases.append(('keep-highlights',program.replace('[[TSAdvancedFindHighlights existingHighlightsForTextStorage:storage] removeAll];',';'),original,'Leaving the Advanced Find panel removes its highlights'))
  for name,body,interface,expected in cases:
   assert body!=program or interface!=original,(name,"No mutation applied")
   results=run(body,interface);assert any(x.returncode and 'FAIL: '+expected in x.stderr for x in results),(name,results);print('DETECTED',name,expected,flush=True)
  for result in run():assert result.returncode==0,result.stderr
  print('NORMAL CONTROL find interface')
