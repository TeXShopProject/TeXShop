#!/usr/bin/env python3
"""Run the document's verbatim window-opacity assignment on unordered real windows."""
from pathlib import Path
import argparse, subprocess, tempfile
r=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--mutations',action='store_true');args=p.parse_args()
s=(r/'Sources/TSDocument-Color.m').read_text();start=s.index('    myArray = [colorDictionary objectForKey:@"PreviewAlpha"];');end=s.index('    myColor = ',start);body=s[start:end]
program=r'''
#import "TestAppKitIsolation.h"
static void Check(BOOL ok,NSString *message){if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
@interface Probe:NSObject { NSWindow *textWindow,*fullSplitWindow,*outputWindow; }
@property NSWindow *pdfKitWindow;
- (NSArray *)windows;
- (void)apply:(NSDictionary *)colorDictionary;
@end
@implementation Probe
- (instancetype)init { self=[super init];if(self){NSMutableArray *a=[NSMutableArray array];for(int i=0;i<4;i++)[a addObject:[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,100,100) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO]];self.pdfKitWindow=a[0];textWindow=a[1];fullSplitWindow=a[2];outputWindow=a[3];}return self;}
- (NSArray *)windows{return @[self.pdfKitWindow,textWindow,fullSplitWindow,outputWindow];}
- (void)apply:(NSDictionary *)colorDictionary {NSArray *myArray;NSNumber *myNumber;
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
 puts("PASS: document opacity assignments, three missing keys, all missing, four unordered windows");
}return 0;}
'''
with tempfile.TemporaryDirectory(prefix='texshop-document-theme-alpha-') as tmp:
 d=Path(tmp)
 def run(code):
  (d/'probe.m').write_text(program.replace('BODY',code));subprocess.run(['xcrun','clang','-fobjc-arc','-I',str(r/'Tests'),'-framework','Cocoa',str(d/'probe.m'),'-o',str(d/'probe')],check=True)
  return subprocess.run([str(d/'probe')],capture_output=True,text=True,timeout=20)
 result=run(body);assert result.returncode==0,result.stderr;print(result.stdout,flush=True)
 if args.mutations:
  for key in ['PreviewAlpha','SourceAlpha','ConsoleAlpha']:
   old='myArray = [colorDictionary objectForKey:@"'+key+'"];\n    myNumber = myArray.count >= 4 ? myArray[3] : @1;';assert body.count(old)==1
   result=run(body.replace(old,old.replace(' : @1;',' : @0;')));assert result.returncode and 'FAIL: Document windows use full opacity for missing theme keys' in result.stderr,(key,result.stderr);print('DETECTED',key,flush=True)
  result=run(body);assert result.returncode==0,result.stderr;print('NORMAL CONTROL document alpha')
