#!/usr/bin/env python3
"""Exercise production initial and typesetting PDF loads with two actual PDFViews.
300 MB PDF generated once; compare URL baseline and watched file snapshots in
separate processes. No TeXShop preferences or visible application windows.
"""
import ast, re, subprocess, tempfile, sys
from pathlib import Path
root = Path(__file__).resolve().parents[1]
s = (root/'Sources/MyPDFKitView.m').read_text(encoding='latin1')
def method(sig):
    a=s.rindex(sig); return s[a:s.index('\n}',a)+2]
tree=ast.parse((root/'Tests/run-pdf-recovery.py').read_text())
fixture=max((n.value for n in ast.walk(tree) if isinstance(n,ast.Constant) and isinstance(n.value,str)),key=len)
fixture=fixture[:fixture.index('static void check(')]
fixture=fixture.replace('NSInteger pageStyle,','NSInteger mouseMode;\n    NSInteger pageStyle,')
fixture=fixture.replace('#define FlashFixKey', '#define PdfKitMouseModeKey @"mouse"\n#define PreviewDrawerOpenKey @"drawer"\n#define FlashFixKey')
fixture=fixture.replace('@implementation TestWindow', '@implementation TestWindow\n- (void)makeKeyAndOrderFront:(id)sender {}')
fixture=fixture.replace('-(void)setup{', '-(void)toggleDrawer:(id)sender {}\n-(void)setup{')
methods='\n'.join(method(x) for x in ['- (void) showWithPath:', '- (void)reShowWithPath:', '- (void)reShowWithDocument:', '- (void)prepareSecond', '- (void) reShowForSecond', '- (void) initializeDisplay', '- (void)removeHideView1:', '- (void)removeHideView2:'])
program=fixture.replace('METHODS',methods)+r'''
#import <mach/mach.h>
static double Footprint(void){task_vm_info_data_t i;mach_msg_type_number_t n=TASK_VM_INFO_COUNT;task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&i,&n);return i.phys_footprint/1048576.0;}
static void Check(BOOL b){if(!b)exit(2);}
static BOOL PasswordField(NSView *view){
 if([view isKindOfClass:NSSecureTextField.class] && !view.hidden)return YES;
 for(NSView *child in view.subviews)if(PasswordField(child))return YES;
 return NO;
}
int main(int argc,char**argv){@autoreleasepool{
 [NSApplication sharedApplication];NSString *path=@(argv[1]),*mode=@(argv[2]);
 [SUD setVolatileDomain:@{@"flash":@NO,@"drawer":@NO} forName:NSArgumentDomain];
 NSWindow *w=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,900,600) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];w.releasedWhenClosed=NO;
 RecoveryView *v=[[RecoveryView alloc]initWithFrame:NSMakeRect(0,0,450,600)],*second=[[RecoveryView alloc]initWithFrame:NSMakeRect(450,0,450,600)];
 for(RecoveryView *view in @[v,second]){view.myPDFWindow=[TestWindow new];view.myDocument=[TestDocument new];view.myDocument.pdfKitWindow=view.myPDFWindow;view.releaseDocument=YES;[w.contentView addSubview:view];view.displayMode=kPDFDisplaySinglePageContinuous;if(![mode isEqual:@"url"])view.myDocument.pdfRefreshTimer=[NSTimer timerWithTimeInterval:100 repeats:NO block:^(NSTimer*t){}];}
 if([mode hasPrefix:@"locked-"]){
  NSImage *image=[[NSImage alloc]initWithSize:NSMakeSize(400,600)];[image lockFocus];[NSColor.whiteColor setFill];NSRectFill(NSMakeRect(0,0,400,600));[image unlockFocus];
  PDFDocument *pdf=[PDFDocument new];[pdf insertPage:[[PDFPage alloc]initWithImage:image] atIndex:0];
  Check([pdf writeToURL:[NSURL fileURLWithPath:path] withOptions:@{PDFDocumentUserPasswordOption:@"secret",PDFDocumentOwnerPasswordOption:@"owner"}]);
  Check(TSExternalPDFSnapshot(path,TSExternalPDFSignature(path))==nil);
  if([mode isEqual:@"locked-show"]) [v showWithPath:path];else [v reShowWithPath:path];
  Check(v.document!=nil && v.document.isLocked);
  Check(![v.document.documentURL.path isEqual:path]);
  [v layoutSubtreeIfNeeded];Check(PasswordField(v));
  Check([v.document unlockWithPassword:@"secret"] && v.document.pageCount==1);
  Check([[v.document pageAtIndex:0] thumbnailOfSize:NSMakeSize(100,150) forBox:kPDFDisplayBoxMediaBox]!=nil);
  printf("PASS: %s private snapshot, password entry, unlock, render; automatic reload rejects locked candidate\n",mode.UTF8String);
  return 0;
 }
 double peak=0;
 for(int round=0;round<3;round++){@autoreleasepool{
  [second prepareSecond];if([mode isEqual:@"show"]) [v showWithPath:path];else [v reShowWithPath:path];second.document=v.document;[second reShowForSecond];
  Check(v.document.pageCount==25 && second.document.pageCount==25);
  if(![mode isEqual:@"url"]) Check(![v.document.documentURL.path isEqual:path]);
  [[v.document pageAtIndex:24] thumbnailOfSize:NSMakeSize(150,200) forBox:kPDFDisplayBoxMediaBox];
 } @autoreleasepool{[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.2]];peak=MAX(peak,Footprint());}}
 printf("%s peakMB=%.1f\n",mode.UTF8String,peak);
 @autoreleasepool{v.document=nil;second.document=nil;[v removeFromSuperview];[second removeFromSuperview];v=nil;second=nil;[w close];w=nil;}
}return 0;}
'''
with tempfile.TemporaryDirectory(prefix='texshop-pdf-load-') as td:
    t=Path(td);(t/'test.m').write_text(program)
    base=['xcrun','clang','-w','-fobjc-arc','-framework','Cocoa','-framework','PDFKit','-I'+str(root/'Sources')]
    subprocess.run(base+[str(t/'test.m'),str(root/'Sources/HideView.m'),str(root/'Sources/TSExternalPDFSnapshot.m'),'-o',str(t/'test')],check=True)
    for mode in ['locked-show','locked-reload']:
        subprocess.run([str(t/'test'),str(t/'locked.pdf'),mode],check=True)
    if '--locked-only' in sys.argv: sys.exit(0)
    subprocess.run(base+[str(root/'Tests/PDFSnapshot.m'),str(root/'Sources/TSExternalPDFSnapshot.m'),'-o',str(t/'generator')],check=True)
    subprocess.run([str(t/'generator'),str(t/'large.pdf'),'generate'],check=True)
    peaks={}
    for mode in ['url','show','reload']:
        result=subprocess.run([str(t/'test'),str(t/'large.pdf'),mode],text=True,capture_output=True,check=True)
        print(result.stdout.strip(),flush=True)
        peaks[mode]=float(re.search(r'peakMB=([0-9.]+)',result.stdout)[1])
    for mode in ['show','reload']:
        if peaks[mode]>peaks['url']+100: raise SystemExit(f'FAIL: {mode} has whole-file memory duplication')
    print('PASS: production initial/typesetting loads, two panes, memory within URL baseline +100 MB')
