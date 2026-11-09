#!/usr/bin/env python3
"""Run the document's verbatim window-opacity assignment on unordered real windows."""
from pathlib import Path
import argparse, subprocess, tempfile
from production_fragments import verify_embedded
from source_tree import include_args
r=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--mutations',action='store_true');args=p.parse_args()
s=(r/'Sources/Editor/TSDocument-Color.m').read_text();start=s.index('    self.pdfKitWindow.alphaValue = TSThemeWindowAlpha(');end=s.index('    myColor = ',start);body=s[start:end]

program=r'''
#import "TestAppKitIsolation.h"
#import "TSThemeAlpha.h"
static void Check(BOOL ok,NSString *message){if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
@interface Probe:NSObject { NSWindow *textWindow,*fullSplitWindow,*outputWindow; }
@property NSWindow *pdfKitWindow;
- (NSArray *)windows;
- (void)apply:(NSDictionary *)colorDictionary;
@end
@implementation Probe
- (instancetype)init { self=[super init];if(self){NSMutableArray *a=[NSMutableArray array];for(int i=0;i<4;i++)[a addObject:[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,100,100) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO]];self.pdfKitWindow=a[0];textWindow=a[1];fullSplitWindow=a[2];outputWindow=a[3];}return self;}
- (NSArray *)windows{return @[self.pdfKitWindow,textWindow,fullSplitWindow,outputWindow];}
- (void)apply:(NSDictionary *)colorDictionary {
BODY
}
@end
int main(void){@autoreleasepool{TSInstallAppKitIsolation();[NSApplication sharedApplication];Probe *probe=[Probe new];
 NSArray *keys=@[@"PreviewAlpha",@"SourceAlpha",@"SourceAlpha",@"ConsoleAlpha"];
 for(NSString *missing in @[@"all",@"PreviewAlpha",@"SourceAlpha",@"ConsoleAlpha"]){
  NSMutableDictionary *theme=[@{@"PreviewAlpha":@[@0,@0,@0,@0.41],@"SourceAlpha":@[@0,@0,@0,@0.62],@"ConsoleAlpha":@[@0,@0,@0,@0.83]} mutableCopy];
  if([missing isEqual:@"all"])[theme removeAllObjects];else [theme removeObjectForKey:missing];
  [probe apply:theme];
  for(NSUInteger i=0;i<4;i++){double expected=theme[keys[i]]?[theme[keys[i]][3] doubleValue]:1;Check(fabs([probe.windows[i] alphaValue]-expected)<0.00001,@"Document windows use full opacity for missing theme keys and preserve existing alpha");}
 }
 for(NSString *key in @[@"PreviewAlpha",@"SourceAlpha",@"ConsoleAlpha"]){
  for(id invalid in @[@"bad",@{},NSNull.null,@[@0],@[@0,@0,@0,@"0.5"],@[@0,@0,@0,NSNull.null],@[@0,@0,@0,@(-0.1)],@[@0,@0,@0,@1.1],@[@0,@0,@0,@(NAN)],@[@0,@0,@0,@(INFINITY)]]){
   @try{[probe apply:@{key:invalid}];}@catch(NSException *exception){Check(NO,@"Invalid document theme alpha is fully opaque");}for(NSWindow *window in probe.windows)Check(window.alphaValue==1,@"Invalid document theme alpha is fully opaque");
  }
  for(NSNumber *alpha in @[@0,@0.5,@1]){[probe apply:@{key:@[@0,@0,@0,alpha]}];for(NSUInteger i=0;i<4;i++)Check(fabs([probe.windows[i]alphaValue]-([keys[i]isEqual:key]?alpha.doubleValue:1))<0.00001,@"Valid document theme alpha and key routing are exact");}
 }
 puts("PASS: document opacity assignments, three missing keys, all missing, four unordered windows");
}return 0;}
'''
with tempfile.TemporaryDirectory(prefix='texshop-document-theme-alpha-') as tmp:
 d=Path(tmp)
 def run(code):
  generated=program.replace('BODY',code)
  if code==body:verify_embedded(generated,[('document alpha assignments',s,body)])
  (d/'probe.m').write_text(generated);subprocess.run(['xcrun','clang','-fobjc-arc','-I',str(d),*include_args(r),'-I',str(r/'Tests'),'-framework','Cocoa',str(d/'probe.m'),'-o',str(d/'probe')],check=True)
  return subprocess.run([str(d/'probe')],capture_output=True,text=True,timeout=20)
 result=run(body);assert result.returncode==0,result.stderr;print(result.stdout,flush=True)
 if args.mutations:
  original=(r/'Sources/Settings/TSThemeAlpha.h').read_text()
  cases=[('array-type','![value isKindOfClass:NSArray.class] || ','', 'Invalid document theme alpha'),('number-type','if (![alpha isKindOfClass:NSNumber.class]) return 1;','', 'Invalid document theme alpha'),('finite','isfinite(result) && result >= 0 && result <= 1','YES', 'Invalid document theme alpha'),('lower-bound','result >= 0','YES', 'Invalid document theme alpha'),('upper-bound','result <= 1','YES', 'Invalid document theme alpha')]
  for name,old,new,message in cases:
   assert original.count(old)==1
   (d/'TSThemeAlpha.h').write_text(original.replace(old,new))
   result=run(body)
   # Invalid object mutations may throw; the probe catches them at the action boundary.
   assert result.returncode and 'FAIL: '+message in result.stderr,(name,result.stderr)
   print('DETECTED',name,flush=True)
  (d/'TSThemeAlpha.h').write_text(original)
  for key in ['Preview','Source','Console']:
   changed=body.replace('TSTheme'+key+'AlphaKey','TSTheme'+('Source' if key!='Source' else 'Console')+'AlphaKey')
   result=run(changed);assert result.returncode and 'FAIL: Document windows use full opacity' in result.stderr,(key,result.stderr)
   print('DETECTED routing',key,flush=True)
  result=run(body);assert result.returncode==0,result.stderr;print('NORMAL CONTROL document alpha')
