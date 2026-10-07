#!/usr/bin/env python3
# added by Terada: Test the application reload methods in an independent PDFKit view.
from pathlib import Path
import subprocess, tempfile, sys
root=Path(__file__).resolve().parents[1]
s=(root/'Sources/MyPDFKitView.m').read_bytes().decode('utf-8', errors='replace')
def method(signature):
    start=s.index(signature);return s[start:s.index('\n}',start)+2]
methods='\n'.join(method(x) for x in ['- (void) reShowWithPath:', '- (void)prepareSecond', '- (void) reShowForSecond', '- (void) initializeDisplay', '- (void)removeHideView1:', '- (void)removeHideView2:'])
program=r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
static BOOL atLeastHighSierra=YES,atLeastMojave=YES,BuggyHighSierra=NO;
#define SUD NSUserDefaults.standardUserDefaults
#define FlashFixKey @"flash"
#define FlashDelayKey @"delay"
#define LinkPopupsKey @"links"
#define ShowSyncMarksKey @"sync"
#define PdfPageStyleKey @"pageStyle"
#define PdfFirstPageStyleKey @"firstPage"
#define PdfKitFitSizeKey @"fit"
#define continuousHighSierraFixKey @"hsfix"
#define NEW_PDF_FIT_TO_WIDTH 2
#define NEW_PDF_FIT_TO_HEIGHT 3
#define PDF_FIT_TO_WINDOW 4
static NSInteger screenUpdates=0;
#define NSDisableScreenUpdates() (screenUpdates++)
#define NSEnableScreenUpdates() (screenUpdates--)
#import "HideView.h"
@interface TestWindow:NSObject
@property (weak) id delegate;
@property BOOL noPdfFile,previewClosed,windowIsSplit;
@end
@implementation TestWindow
@end
@interface TestDocument:NSObject
@property BOOL externalEditor,pdfSinglePage;
@property NSInteger stringWindowAlignment;
@property NSInteger numberingCorrection;
@property TestWindow *pdfKitWindow;
@end
@implementation TestDocument
@end
@interface RecoveryView:PDFView {
    BOOL _editMode,protectFind,downOverLink,showSync,fromTypesetOrQuit,firstTimeSave;
    NSInteger pageStyle,firstPageStyle,resizeOption;
    NSMutableArray *_searchResults;
    NSTableView *_searchTable;
    NSInteger totalPages,totalRotation,secondTheIndex;
    NSTextField *totalPage,*stotalPage,*totalPage1,*currentPage0,*scurrentPage,*currentPage1;
    BOOL drawMark,secondNeedsInitialization;
    NSRect secondVisibleRect,secondFullRect;
}
@property BOOL firstTime,oldUsed,doScroll,skipLinks,globalLongTerm;
@property NSInteger handlingLink,timerNumber,stringAlignment;
@property NSString *oneOffSearchString;
@property NSTimer *updatePageNumberTimer;
@property TestWindow *myPDFWindow;
@property TestDocument *myDocument;
@property id sourceFiles;
@property BOOL PDFFlashFix,releaseDocument;
@property NSTimeInterval PDFFlashDelay;
@property HideView *myHideView1,*myHideView2;
-(BOOL)doReleaseDocument;
-(void)setup;
-(void)setupPageStyle;
-(void)setupMagnificationStyle;
-(void)setupOutline;
-(void)initializeDisplay;
-(void)cleanupMarquee:(BOOL)b;
-(void)fixWhiteDisplay;
-(NSImage*)screenCacheImageForView:(NSView*)v;
-(void)reShowWithPath:(NSString*)path;
-(void)prepareSecond;
-(void)reShowForSecond;
@end
@implementation RecoveryView
-(BOOL)doReleaseDocument{return self.releaseDocument;}
-(void)setup{[self initializeDisplay];}
-(void)setupPageStyle{}
-(void)setupMagnificationStyle{}
-(void)setupOutline{}

-(void)cleanupMarquee:(BOOL)b{}
-(void)fixWhiteDisplay{}
-(NSImage*)screenCacheImageForView:(NSView*)v{
 NSImage *image=[[NSImage alloc]initWithSize:v.bounds.size];[image lockFocus];[NSColor.grayColor setFill];NSRectFill(v.bounds);[image unlockFocus];return image;
}

METHODS
@end
static void check(BOOL ok,NSString *message){if(!ok){NSLog(@"FAIL: %@",message);exit(1);}}
int main(int argc,char**argv){@autoreleasepool{
 [NSApplication sharedApplication];
 [SUD registerDefaults:@{FlashFixKey:@YES,FlashDelayKey:@0.01}];
 NSString *good=[NSString stringWithUTF8String:argv[1]],*bad=[NSString stringWithUTF8String:argv[2]];
 NSData *goodData=[NSData dataWithContentsOfFile:good],*badData=[NSData dataWithContentsOfFile:bad];
 NSString *live=[NSString stringWithUTF8String:argv[3]];
 if(!goodData){
 NSImage *image=[[NSImage alloc]initWithSize:NSMakeSize(400,600)];[image lockFocus];[NSColor.whiteColor setFill];NSRectFill(NSMakeRect(0,0,400,600));[image unlockFocus];
 PDFDocument *pdf=[PDFDocument new];for(int i=0;i<3;i++)[pdf insertPage:[[PDFPage alloc]initWithImage:image] atIndex:i];goodData=pdf.dataRepresentation;
 badData=[@"%PDF-1.4\n1 0 obj\n<< /Type /Catalog" dataUsingEncoding:NSASCIIStringEncoding];
 }
 check(goodData.length>0 && badData.length>0,@"Input PDF");
 for(NSNumber *flash in @[@NO,@YES])for(NSNumber *release in @[@NO,@YES])for(NSNumber *mode in @[@(kPDFDisplaySinglePage),@(kPDFDisplaySinglePageContinuous),@(kPDFDisplayTwoUp),@(kPDFDisplayTwoUpContinuous)]) {
 [goodData writeToFile:live atomically:NO];
 [SUD setVolatileDomain:@{FlashFixKey:flash} forName:NSArgumentDomain];
 NSWindow *w=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,900,600) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
 RecoveryView *v=[[RecoveryView alloc]initWithFrame:NSMakeRect(0,0,450,600)],*second=[[RecoveryView alloc]initWithFrame:NSMakeRect(450,0,450,600)];
 for(RecoveryView *view in @[v,second]) {view.myPDFWindow=[TestWindow new];view.myDocument=[TestDocument new];view.myDocument.pdfKitWindow=view.myPDFWindow;view.releaseDocument=release.boolValue;view.PDFFlashFix=flash.boolValue;view.PDFFlashDelay=.01;view.displayMode=mode.integerValue;[w.contentView addSubview:view];view.document=[[PDFDocument alloc]initWithURL:[NSURL fileURLWithPath:live]];view.scaleFactor=1.25;}
 @try {
 [badData writeToFile:live atomically:NO];[v reShowWithPath:live];[second prepareSecond];second.document=v.document;[second reShowForSecond];
 [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
 check(v.document==nil,@"壊れたPDFを読み込んだ状態の再現");
 [goodData writeToFile:live atomically:NO];[v reShowWithPath:live];[second prepareSecond];second.document=v.document;[second reShowForSecond];
 }@catch(NSException *e){NSLog(@"EXCEPTION: %@ %@",e.name,e.reason);return 2;}
 [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
 
 check(v.document.pageCount>0 && v.currentPage!=nil,@"正常PDFへの復旧");
 check(second.document.pageCount>0 && second.currentPage!=nil,@"第2ペインの復旧");
 for(NSView *child in w.contentView.subviews)check(![child isKindOfClass:HideView.class],@"灰色のキャッシュ画像が残らない");
 NSBitmapImageRep *bitmap=[w.contentView bitmapImageRepForCachingDisplayInRect:w.contentView.bounds];[w.contentView cacheDisplayInRect:w.contentView.bounds toBitmapImageRep:bitmap];
 NSUInteger white=0;for(NSInteger y=0;y<bitmap.pixelsHigh;y+=8)for(NSInteger x=0;x<bitmap.pixelsWide;x+=8){NSColor *c=[[bitmap colorAtX:x y:y]colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];if(c.redComponent>.95&&c.greenComponent>.95&&c.blueComponent>.95)white++;}
 check(white>100,@"灰色の画像に遮られずPDFの白いページが描画される");
 check(screenUpdates==0,@"画面更新の抑制解除");
 }
 printf("PASS: invalid-to-valid reload, both panes, four display modes, data/URL loading\n");
}}
'''.replace('METHODS',methods)
with tempfile.TemporaryDirectory(prefix='texshop-recovery-') as directory:
    p=Path(directory);(p/'test.m').write_text(program)
    subprocess.run(['xcrun','clang','-fobjc-arc','-framework','Cocoa','-framework','PDFKit','-I',str(root/'Sources'),str(p/'test.m'),str(root/'Sources/HideView.m'),'-o',str(p/'test')],check=True)
    subprocess.run([str(p/'test'),*(sys.argv[1:] or [str(p/'good.pdf'),str(p/'bad.pdf')]),str(p/'live.pdf')],check=True)
