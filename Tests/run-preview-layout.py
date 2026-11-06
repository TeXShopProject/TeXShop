#!/usr/bin/env python3
"""Exercise production layout actions with real PDFKit and isolated preferences."""
from pathlib import Path
import subprocess, tempfile, plistlib, sys
root=Path(__file__).resolve().parents[1]
def method(source, signature):
 a=source.index(signature); return source[a:source.index('\n}',a)+2]
toolbar=(root/'Sources/TSToolbarController.m').read_text()
view=(root/'Sources/MyPDFKitView.m').read_text(encoding='latin1')
doc=(root/'Sources/TSDocument.m').read_text()
prefs=(root/'Sources/TSPreferences.m').read_text()
controller='\n'.join(method(toolbar,s) for s in ['- (BOOL)previewDisplaysAsBook','- (BOOL)previewDisplaysRTL','- (void)changePreviewLayout:', '- (void)changePreviewArrangement:', '- (BOOL)validatePreviewLayoutItem:', '- (void)updatePreviewLayoutControls'])
viewmethods='\n'.join(method(view,s) for s in ['- (void) setupPageStyle','- (void) setupMagnificationStyle','- (void)performPreviewLayoutChange:','- (void)applyPreviewArrangement','- (void)changePageStyleTo:', '- (void)setDisplayMode:', '- (void)setScaleFactor:', '- (NSInteger)pageStyle', '- (void)setDocument:(PDFDocument *)document'])
parse=doc[doc.index('        parserRange = [testString rangeOfString:@"% !TEX bookDisplay"]'):doc.index('       // parserRange = [testString rangeOfString:@"% !TEX numberingCorrection Automatic"]')]
initialize=doc[doc.index('    self.bookDisplay = [SUD boolForKey:DisplayAsBookKey];'):doc.index('    self.previewInitialRTLDisplay = self.RTLDisplay;')+len('    self.previewInitialRTLDisplay = self.RTLDisplay;')]
program=r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import "TSPreviewLayout.h"
static NSUserDefaults *defaults;
#define SUD defaults
#define DisplayAsBookKey @"DisplayAsBook"
#define PdfFirstPageStyleKey @"PdfFirstPageStyle"
#define PdfMagnificationKey @"PdfMagnification"
#define PDF_MAX_SCALE 10000
#define atLeastHighSierra YES
#define PDF_SINGLE_PAGE_STYLE 1
#define PDF_TWO_PAGE_STYLE 2
#define PDF_MULTI_PAGE_STYLE 3
#define PDF_DOUBLE_MULTI_PAGE_STYLE 4
#define PDF_FIRST_LEFT 1
#define PDF_FIRST_RIGHT 2
#define NEW_PDF_ACTUAL_SIZE 1
#define NEW_PDF_FIT_TO_NONE 2
#define NEW_PDF_FIT_TO_WINDOW 3
#define NEW_PDF_FIT_TO_WIDTH 4
#define NEW_PDF_FIT_TO_HEIGHT 5
@class TSDocument,MyPDFKitView;
@interface TestWindow : NSWindow
@property MyPDFKitView *activeView;
@end
@implementation TestWindow
@end
@interface TSDocument : NSObject <NSToolbarDelegate>
@property BOOL bookDisplay, RTLDisplay,previewInitialBookDisplay,previewInitialRTLDisplay,previewHasDirectionComment;
@property NSNumber *previewBookOverride,*previewDirectionOverride;
@property MyPDFKitView *myPDFKitView,*myPDFKitView2;
@property TestWindow *pdfKitWindow;
@property NSWindow *fullSplitWindow;
- (BOOL)previewDisplaysAsBook;
- (BOOL)previewDisplaysRTL;
- (MyPDFKitView *)pdfKitView;
- (void)updatePreviewLayoutControls;
- (BOOL)validatePreviewLayoutItem:(NSMenuItem *)item;
@end
@interface MyPDFKitView : PDFView {
 @public NSInteger pageStyle,firstPageStyle,resizeOption; id myStepper,myStepper1; BOOL _pdfViewReady;
}
@property (weak) TSDocument *myDocument;
@property BOOL doScroll;
- (NSInteger)pageStyle;
- (void)changePageStyleTo:(NSInteger)style;
- (void)applyPreviewArrangement;
@end
@implementation MyPDFKitView
- (void)cleanupMarquee:(BOOL)b {}
- (void)updateDarkModeInversion {}
- (void)scaleChanged:(id)sender {}
VIEWMETHODS
@end
@implementation TSDocument
- (instancetype)init { if((self=[super init])) { INITIALIZE } return self; }
- (MyPDFKitView *)pdfKitView {return self.pdfKitWindow.activeView ?: self.myPDFKitView;}
CONTROLLER
- (void)comments:(NSString *)source {
 self.bookDisplay=self.previewInitialBookDisplay; self.RTLDisplay=self.previewInitialRTLDisplay; self.previewHasDirectionComment=NO;
 NSArray *lines=[source componentsSeparatedByString:@"\n"];
 for(NSString *testString in [lines subarrayWithRange:NSMakeRange(0,MIN(20,lines.count))]) {
 NSRange parserRange;
 PARSE
 }
}
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)ident willBeInsertedIntoToolbar:(BOOL)b {return TSPreviewLayoutItem(self,ident);}
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {return @[TSPreviewLayoutToolbarID,TSPreviewArrangementToolbarID];}
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {return [self toolbarDefaultItemIdentifiers:toolbar];}
- (BOOL)validateMenuItem:(NSMenuItem *)item {return [self validatePreviewLayoutItem:item];}
@end
@interface TSPreferenceWindow:NSWindow @end
@implementation TSPreferenceWindow @end
@interface TSPreferences : NSObject { @public NSUndoManager *_undoManager; NSButton *_displayAsBookButton; }
@property NSMutableDictionary *outlets;
@end
@implementation TSPreferences
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {self.outlets[key]=value;}
PREFMETHODS
@end
static void Check(BOOL ok,NSString *message){if(!ok){NSLog(@"FAIL: %@",message);exit(1);}}
static void Pump(void){[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.03]];}
static NSMenuItem *Choice(SEL action,NSInteger tag){NSMenuItem *i=[[NSMenuItem alloc]initWithTitle:@"Test" action:action keyEquivalent:@""];i.tag=tag;return i;}
static PDFDocument *PDF(void){
 NSMutableData *data=[NSMutableData data];CGDataConsumerRef consumer=CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
 CGRect box=CGRectMake(0,0,400,600);CGContextRef c=CGPDFContextCreate(consumer,&box,NULL);
 for(int i=0;i<8;i++) {CGPDFContextBeginPage(c,NULL);CGContextSetRGBFillColor(c,.1+i*.06,.4,.6,1);CGContextFillRect(c,CGRectMake(40,150,320,280));CGPDFContextEndPage(c);}
 CGPDFContextClose(c);CGContextRelease(c);CGDataConsumerRelease(consumer);return [[PDFDocument alloc]initWithData:data];
}
// Small deterministic PDFs with catalog preferences, not Info dictionary metadata.
static PDFDocument *DirectedPDF(NSString *entry) {
 NSArray *objects=@[[NSString stringWithFormat:@"<< /Type /Catalog /Pages 2 0 R %@ >>",entry],
  @"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
  @"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 420 595] /Contents 4 0 R >>",
  @"<< /Length 0 >>\nstream\nendstream"];
 NSMutableString *pdf=[NSMutableString stringWithString:@"%PDF-1.4\n"];
 NSMutableArray *offsets=[NSMutableArray array];
 for(NSUInteger i=0;i<objects.count;i++){[offsets addObject:@(pdf.length)];[pdf appendFormat:@"%lu 0 obj\n%@\nendobj\n",i+1,objects[i]];}
 NSUInteger xref=pdf.length;[pdf appendString:@"xref\n0 5\n0000000000 65535 f \n"];
 for(NSNumber *offset in offsets)[pdf appendFormat:@"%010lu 00000 n \n",offset.unsignedIntegerValue];
 [pdf appendFormat:@"trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n%lu\n%%%%EOF\n",xref];
 return [[PDFDocument alloc]initWithData:[pdf dataUsingEncoding:NSASCIIStringEncoding]];
}
static TSDocument *MakeDocument(void){
 TSDocument *d=[TSDocument new];
 d.pdfKitWindow=[[TestWindow alloc]initWithContentRect:NSMakeRect(0,0,850,650) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
 d.pdfKitWindow.releasedWhenClosed=NO;
 d.myPDFKitView=[[MyPDFKitView alloc]initWithFrame:NSMakeRect(0,0,850,650)]; d.myPDFKitView.myDocument=d;
 d.myPDFKitView2=[[MyPDFKitView alloc]initWithFrame:NSMakeRect(0,0,400,400)];d.myPDFKitView2.myDocument=d;
 d.pdfKitWindow.contentView=d.myPDFKitView;d.pdfKitWindow.activeView=d.myPDFKitView;
 d.myPDFKitView.document=PDF();d.myPDFKitView2.document=d.myPDFKitView.document;
 d.myPDFKitView->resizeOption=2;d.myPDFKitView2->resizeOption=2;
 d.myPDFKitView.scaleFactor=.8;d.myPDFKitView2.scaleFactor=.7;
 NSToolbar *bar=[[NSToolbar alloc]initWithIdentifier:NSUUID.UUID.UUIDString];bar.delegate=d;bar.displayMode=NSToolbarDisplayModeIconAndLabel;d.pdfKitWindow.toolbar=bar;
 [d.pdfKitWindow orderFront:nil];Pump();return d;
}
static NSTabView *Tabs(NSView *v){if([v isKindOfClass:NSTabView.class])return (id)v;for(NSView *c in v.subviews){NSTabView *t=Tabs(c);if(t)return t;}return nil;}
static void Snapshot(NSView *v,NSString *path){[v layoutSubtreeIfNeeded];[v display];NSBitmapImageRep *rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];NSImage *image=[[NSImage alloc]initWithSize:v.bounds.size];[image lockFocus];[v.effectiveAppearance performAsCurrentDrawingAppearance:^{[NSColor.windowBackgroundColor setFill];NSRectFill(NSMakeRect(0,0,v.bounds.size.width,v.bounds.size.height));}];NSImage *capture=[[NSImage alloc]initWithSize:v.bounds.size];[capture addRepresentation:rep];[capture drawInRect:NSMakeRect(0,0,v.bounds.size.width,v.bounds.size.height) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];[image unlockFocus];NSBitmapImageRep *opaque=[[NSBitmapImageRep alloc]initWithData:image.TIFFRepresentation];[[opaque representationUsingType:NSBitmapImageFileTypePNG properties:@{}]writeToFile:path atomically:YES];}
int main(int argc,char **argv){@autoreleasepool{
 [NSApplication sharedApplication];
 NSString *domain=NSBundle.mainBundle.bundleIdentifier;
 Check([domain hasPrefix:@"org.texshop.LayoutTest."],@"Isolated test preferences");
 defaults=NSUserDefaults.standardUserDefaults;[defaults registerDefaults:@{DisplayAsBookKey:@NO,PdfFirstPageStyleKey:@1,PdfMagnificationKey:@1}];
 TSDocument *d=MakeDocument(),*other=MakeDocument();
 PDFDocument *rtlPDF=DirectedPDF(@"/ViewerPreferences << /Direction /R2L >>"), *ltrPDF=DirectedPDF(@"/ViewerPreferences << /Direction /L2R >>");
 Check(rtlPDF && ltrPDF,@"Valid direction fixtures");
 Check([TSPreviewPDFDirection(rtlPDF) isEqual:@YES] && [TSPreviewPDFDirection(ltrPDF) isEqual:@NO],@"Catalog direction names");
 for(NSString *entry in @[@"",@"/ViewerPreferences 8",@"/ViewerPreferences << /Direction (R2L) >>",@"/ViewerPreferences << /Direction /Unknown >>"])
  Check(TSPreviewPDFDirection(DirectedPDF(entry))==nil,@"Invalid or absent direction falls back");
 d.myPDFKitView.document=rtlPDF;
 Check(d.previewDisplaysRTL && d.myPDFKitView.displaysRTL,@"First load honors PDF R2L");
 [d comments:@"% !TEX PageDirectionL2R"]; d.myPDFKitView.document=rtlPDF;
 Check(!d.previewDisplaysRTL && !d.myPDFKitView.displaysRTL,@"Explicit L2R comment beats PDF R2L on load");
 [d changePreviewArrangement:Choice(@selector(changePreviewArrangement:),2)];
 Check(d.previewDisplaysRTL,@"Toolbar choice overrides comment");
 d.myPDFKitView.document=ltrPDF;
 Check(d.previewDisplaysRTL && d.myPDFKitView.displaysRTL,@"Reload metadata does not erase user choice");
 [d changePreviewArrangement:Choice(@selector(changePreviewArrangement:),4)];
 Check(!d.previewDisplaysRTL,@"Restore respects source comment");
 [d comments:@"% !TEX PageDirectionR2L"];d.myPDFKitView.document=ltrPDF;
 Check(d.previewDisplaysRTL && d.myPDFKitView.displaysRTL,@"R2L comment beats PDF L2R");
 [d comments:@""]; d.myPDFKitView.document=ltrPDF;Check(!d.previewDisplaysRTL,@"Removing comment exposes PDF L2R");
 d.myPDFKitView.document=rtlPDF;Check(d.previewDisplaysRTL,@"Replacing PDF updates direction without a user override");
 d.myPDFKitView.document=PDF();Check(!d.previewDisplaysRTL,@"Missing PDF direction returns to app default");
 for(NSString *arg in NSProcessInfo.processInfo.arguments)if([arg hasPrefix:@"--sample="]){
  PDFDocument *sample=[[PDFDocument alloc]initWithURL:[NSURL fileURLWithPath:[arg substringFromIndex:9]]];
  Check(sample.pageCount>0 && [TSPreviewPDFDirection(sample) isEqual:@YES],@"Supplied real PDF has R2L catalog direction");
  d.myPDFKitView.document=sample;Check(d.previewDisplaysRTL && d.myPDFKitView.displaysRTL,@"Real PDF opens right to left");d.myPDFKitView.document=PDF();
 }
 for(NSToolbarItem *item in d.pdfKitWindow.toolbar.items)
  Check(item.visibilityPriority==NSToolbarItemVisibilityPriorityUser,@"Both controls have highest visibility priority");

 [d comments:@"% !TEX bookDisplay\n% !TEX PageDirectionR2L"];
 Check(d.previewDisplaysAsBook && d.previewDisplaysRTL,@"Magic comments override defaults");
 [d changePreviewArrangement:Choice(@selector(changePreviewArrangement:),1)];
 Check(!d.previewDisplaysRTL && d.previewDisplaysAsBook,@"A direction override preserves the cover comment");
 [d comments:@"% !TEX standardDisplay\n% !TEX PageDirectionR2L"];
 Check(!d.previewDisplaysRTL && !d.previewDisplaysAsBook,@"Reparse preserves override, updates independent field");
 [d changePreviewArrangement:Choice(@selector(changePreviewArrangement:),4)];
 Check(d.previewDisplaysRTL && !d.previewDisplaysAsBook,@"Restore latest document comments");
 [d comments:@""];Check(!d.previewDisplaysRTL && !d.previewDisplaysAsBook,@"Removed comments restore opening defaults");
 for(int style=1;style<=4;style++)for(int rtl=0;rtl<2;rtl++)for(int book=0;book<2;book++){
  [d changePreviewLayout:Choice(@selector(changePreviewLayout:),style)];
  [d changePreviewArrangement:Choice(@selector(changePreviewArrangement:),rtl?2:1)];
  if(d.previewDisplaysAsBook!=book)[d changePreviewArrangement:Choice(@selector(changePreviewArrangement:),3)];
  Check(d.myPDFKitView.pageStyle==style,@"Arrangement does not change layout");
  if(style==2||style==4){Check(d.myPDFKitView.displaysRTL==rtl && d.myPDFKitView.displaysAsBook==book,@"PDFKit arrangement");}
  NSMenuToolbarItem *layoutItem=(id)d.pdfKitWindow.toolbar.items.firstObject;
  [layoutItem.menu update];
  Check(layoutItem.menu.itemArray.count==4,@"Four actual toolbar choices");
  for(NSMenuItem *choice in layoutItem.menu.itemArray)
   Check(choice.target==d && choice.action==@selector(changePreviewLayout:) && (choice.state==NSControlStateValueOn)==(choice.tag==style),@"Actual toolbar menu target and check state");
  for(int n=1;n<=4;n++){
   NSMenuItem *menu=Choice(@selector(changePageStyle:),n),*tool=Choice(@selector(changePreviewLayout:),n);
   Check([d validatePreviewLayoutItem:menu] && [d validatePreviewLayoutItem:tool] && menu.state==tool.state && (menu.state==NSControlStateValueOn)==(style==n),@"Main menu and toolbar agree");
  }
 }
 Check(!other.previewDisplaysAsBook && !other.previewDisplaysRTL,@"Other documents unaffected");
 // Select the second pane; layout is pane-local but arrangement is document-wide.
 NSInteger first=d.myPDFKitView.pageStyle;d.pdfKitWindow.activeView=d.myPDFKitView2;
 [d changePreviewLayout:Choice(@selector(changePreviewLayout:),2)];
 Check(d.myPDFKitView2.pageStyle==2 && d.myPDFKitView.pageStyle==first,@"Active split pane");
 [d changePreviewArrangement:Choice(@selector(changePreviewArrangement:),2)];
 Check(d.myPDFKitView2.displaysRTL && d.myPDFKitView.displaysRTL,@"Arrangement shared across panes");
 d.myPDFKitView2.document=PDF();[d.myPDFKitView2 setupPageStyle];
 Check(d.myPDFKitView2.displaysRTL && d.previewDirectionOverride!=nil,@"Reload preserves arrangement");
 // Defaults changed now do not retroactively change this document's baseline.
 [defaults setBool:YES forKey:DisplayAsBookKey];[defaults setInteger:2 forKey:PdfFirstPageStyleKey];
 [d comments:@""];[d changePreviewArrangement:Choice(@selector(changePreviewArrangement:),4)];
 Check(!d.previewDisplaysAsBook && !d.previewDisplaysRTL,@"Existing document keeps initial defaults");
 TSDocument *fresh=[TSDocument new];Check(fresh.previewDisplaysAsBook && fresh.previewDisplaysRTL,@"New document reads updated defaults");
 Check(![d validatePreviewLayoutItem:Choice(@selector(changePreviewArrangement:),4)],@"Restore disabled without overrides");
 // Position and manually chosen scale survive layout and cover changes.
 d.pdfKitWindow.activeView=d.myPDFKitView;[d changePreviewLayout:Choice(@selector(changePreviewLayout:),3)];
 PDFPage *page=[d.myPDFKitView.document pageAtIndex:4];[d.myPDFKitView goToDestination:[[PDFDestination alloc]initWithPage:page atPoint:NSMakePoint(0,420)]];Pump();
 CGFloat scale=d.myPDFKitView.scaleFactor;[d changePreviewLayout:Choice(@selector(changePreviewLayout:),4)];Pump();
 Check([d.myPDFKitView.visiblePages containsObject:page],@"Viewed page stays visible");Check(fabs(d.myPDFKitView.scaleFactor-scale)<.01,@"Manual zoom retained");
 d.myPDFKitView->resizeOption=3;[d.myPDFKitView setupMagnificationStyle];[d changePreviewLayout:Choice(@selector(changePreviewLayout:),2)];
 Check(d.myPDFKitView.autoScales && d.myPDFKitView->resizeOption==3,@"Auto fit retained");
 d.pdfKitWindow.title=@"TeXShop — PDF Layout Controls";
 if(argc>2 && strcmp(argv[2],"-")!=0)Snapshot(d.pdfKitWindow.contentView.superview,[@(argv[2]) stringByAppendingPathComponent:@"pdf-layout.png"]);
 // Nib + actual preferences action, without loading TeXShop or its user settings.
 TSPreferences *owner=[TSPreferences new];owner.outlets=[NSMutableDictionary new];owner->_undoManager=[NSUndoManager new];owner->_undoManager.groupsByEvent=NO;
 NSString *nibFile=[@(argv[1]) stringByAppendingPathComponent:@"keyedobjects-101300.nib"];if(![NSFileManager.defaultManager fileExistsAtPath:nibFile])nibFile=[@(argv[1]) stringByAppendingPathComponent:@"keyedobjects.nib"];
 NSNib *nib=[[NSNib alloc]initWithNibData:[NSData dataWithContentsOfFile:nibFile] bundle:nil];NSArray *objects;
 Check([nib instantiateWithOwner:owner topLevelObjects:&objects],@"Load Preferences nib");
 NSButton *cover=owner->_displayAsBookButton;Check(cover && cover.action==@selector(displayAsBookChanged:),@"Cover outlet and action");
 [defaults setBool:NO forKey:DisplayAsBookKey];[owner->_undoManager beginUndoGrouping];cover.state=NSControlStateValueOn;[owner displayAsBookChanged:cover];[owner->_undoManager endUndoGrouping];
 Check([defaults boolForKey:DisplayAsBookKey],@"Cover preference saved");[owner->_undoManager undo];Check(![defaults boolForKey:DisplayAsBookKey],@"Cancel restores cover preference");
 for(id o in objects)if([o isKindOfClass:NSWindow.class]){NSWindow *w=o;NSTabView *tabs=Tabs(w.contentView);if(tabs.numberOfTabViewItems!=9)continue;[tabs selectTabViewItemAtIndex:2];w.appearance=[NSAppearance appearanceNamed:NSAppearanceNameAqua];[w orderOut:nil];[w.contentView layoutSubtreeIfNeeded];[w displayIfNeeded];if(argc>2 && strcmp(argv[2],"-")!=0){Snapshot(w.contentView,[@(argv[2]) stringByAppendingPathComponent:@"preferences.png"]);Snapshot(w.contentView,[@(argv[2]) stringByAppendingPathComponent:@"preferences.png"]);Snapshot(cover.superview.superview,[@(argv[2]) stringByAppendingPathComponent:@"arrangement-settings.png"]);}[w orderOut:nil];}
 d.myPDFKitView.document=nil;Check(![d validatePreviewLayoutItem:Choice(@selector(changePreviewLayout:),1)],@"No PDF disables actions");
 [defaults removePersistentDomainForName:domain];
 NSLog(@"PASS: PDF catalog direction and precedence, toolbar priority, 16 layout combinations, precedence, split panes, menu synchronization, reload, position/zoom, preferences undo");
}}
'''
for key,value in [('VIEWMETHODS',viewmethods),('INITIALIZE',initialize),('CONTROLLER',controller),('PARSE',parse),('PREFMETHODS',method(prefs,'- (IBAction)displayAsBookChanged:'))]:program=program.replace(key,value)
lang=next((a for a in sys.argv[1:] if a in ('en','ja')),'en')
with tempfile.TemporaryDirectory(prefix='TeXShop-layout-test-') as tmp:
 app=Path(tmp)/'LayoutTest.app';mac=app/'Contents/MacOS';mac.mkdir(parents=True)
 (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'org.texshop.LayoutTest.'+Path(tmp).name,'CFBundleExecutable':'LayoutTest','CFBundlePackageType':'APPL','LSUIElement':True}))
 import shutil
 for l in ('en','ja'):
  res=app/f'Contents/Resources/{l}.lproj';res.mkdir(parents=True);shutil.copy(root/f'Resources/Interfaces/{l}.lproj/ToolbarItems.strings',res)
 source=Path(tmp)/'Test.m';source.write_text(program)
 subprocess.run(['xcrun','clang','-fobjc-arc','-fmodules','-I'+str(root/'Sources'),'-framework','Cocoa','-framework','PDFKit',str(source),'-o',str(mac/'LayoutTest')],check=True)
 nib=root/f'Resources/Interfaces/{"Base" if lang=="en" else lang}.lproj/Preferences.nib'
 snapshot=next((a.split('=',1)[1] for a in sys.argv if a.startswith('--snapshots=')),None)
 args=[str(mac/'LayoutTest'),str(nib)]
 if snapshot:Path(snapshot).mkdir(parents=True,exist_ok=True)
 args.append(snapshot or "-")
 args += [a for a in sys.argv[1:] if a.startswith("--sample=")]
 args+=['-AppleLanguages',f'({lang})']
 try:
  subprocess.run(args,check=True)
 finally:
  domain=plistlib.loads((app/'Contents/Info.plist').read_bytes())['CFBundleIdentifier']
  subprocess.run(['defaults','delete',domain],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister','-u',str(app)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
