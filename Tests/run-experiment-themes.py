#!/usr/bin/env python3
"""Exercise Experiment theme hooks and the actual PDFKit toolbar without showing windows.

The PDF view is compiled from its complete production implementation. The source view's
new lifecycle/theme methods run on NSTextView; legacy completion dependencies are omitted.
Defaults stay in memory, and no window uses frame autosaving, including failing mutations.
"""
from pathlib import Path
import argparse, os, subprocess, tempfile
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['source-hook', 'pdf-hook', 'defaults-hook', 'reload-hook', 'menu-validation', 'filter-gamma', 'source-alpha', 'preview-alpha'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = (root/'Sources/ScrapTextView.m').read_text(encoding='latin1')
source = source[source.index('- (void)updateExperimentColors:'):source.index('- (void)awakeFromNib')]
pdf = (root/'Sources/ScrapPDFKitView.m').read_text()
for header in ['globals.h', 'TSDocument.h', 'TSEncodingSupport.h']:
    pdf = pdf.replace(f'#import "{header}"', '')
if args.mutation == 'source-hook':
    source = source.replace('[self updateExperimentColors:nil];', '')
if args.mutation == 'pdf-hook':
    pdf = pdf.replace('[self updateExperimentColors:nil];', '')
if args.mutation == 'defaults-hook':
    pdf = pdf.replace('[center addObserver:self selector:@selector(updateExperimentAppearance:)\n        name:NSUserDefaultsDidChangeNotification object:SUD];', '')
if args.mutation == 'reload-hook':
    start, end = pdf.index('- (void)setDocument:'), pdf.index('- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowed')
    pdf = pdf[:start] + '- (void)setDocument:(PDFDocument *)document { [super setDocument:document]; }\n' + pdf[end:]
if args.mutation == 'menu-validation':
    pdf = pdf.replace('return [super validateMenuItem:item];', 'return YES;')
if args.mutation == 'source-alpha':
    source = source.replace('self.window.alphaValue = TSExperimentWindowAlpha(theme, @"SourceAlpha");', '')
if args.mutation == 'preview-alpha':
    pdf = pdf.replace('self.window.alphaValue = TSExperimentWindowAlpha(theme, @"PreviewAlpha");', '')
appearance = (root/'Sources/TSPreviewAppearance.h').read_text()
if args.mutation == 'filter-gamma':
    appearance = appearance.replace('numberWithDouble:1.6', 'numberWithDouble:1.0')
pdf = pdf.replace('#import "TSPreviewAppearance.h"', appearance)
prefix = r'''
#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
#import "TSColorSupport.h"
#import "TSExperimentTheme.h"
static NSDictionary *liteColors, *darkColors;
@interface ExperimentMemoryDefaults : NSUserDefaults
@property (nonatomic, strong) NSMutableDictionary *values;
@end
@implementation ExperimentMemoryDefaults
- (instancetype)init { self = [super init]; if (self) _values = [NSMutableDictionary dictionary]; return self; }
- (NSInteger)integerForKey:(NSString *)key { return [self.values[key] integerValue]; }
- (void)setInteger:(NSInteger)value forKey:(NSString *)key {
    self.values[key] = @(value);
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:self];
}
@end
static ExperimentMemoryDefaults *testDefaults;
#define SUD testDefaults
#define SourceColorChangedNotification @"SourceColorChanged"
@implementation TSColorSupport
+ (id)sharedInstance { static id instance; if (!instance) instance = [self new]; return instance; }
- (NSColor *)colorForKey:(NSString *)key fromDictionary:(NSDictionary *)theme isWindowDark:(BOOL)dark
{ return theme[key] ?: (dark ? NSColor.blackColor : NSColor.whiteColor); }
@end
@interface ExperimentSourceFixture : NSTextView
@end
@implementation ExperimentSourceFixture
SOURCE
@end
'''.replace('SOURCE', source)
tests = r'''
static int checks;
static void check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static void pump(void) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:.1];
    while (end.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
}
static NSWindow *window(NSView *view) {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,600,480)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    w.contentView = view;
    return w;
}
static PDFDocument *document(void) {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(400,600)];
    [image lockFocus]; [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(0,0,400,600));
    [@"Experiment" drawAtPoint:NSMakePoint(20,500) withAttributes:@{NSForegroundColorAttributeName:NSColor.blackColor}];
    [image unlockFocus];
    PDFDocument *doc = [PDFDocument new];
    [doc insertPage:[[PDFPage alloc] initWithImage:image] atIndex:0];
    return doc;
}
static BOOL inverted(ScrapPDFKitView *view) { return view.documentView.enclosingScrollView.contentFilters.count == 3; }
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    testDefaults = [ExperimentMemoryDefaults new];
    liteColors = @{@"EditorBackground":NSColor.whiteColor, @"EditorText":NSColor.blackColor,
        @"EditorInsertionPoint":NSColor.blueColor, @"PreviewBackground":NSColor.grayColor,
        @"SourceAlpha":@[@0,@0,@0,@.92], @"PreviewAlpha":@[@0,@0,@0,@.93]};
    darkColors = @{@"EditorBackground":NSColor.blackColor, @"EditorText":NSColor.whiteColor,
        @"EditorInsertionPoint":NSColor.cyanColor, @"PreviewBackground":NSColor.darkGrayColor,
        @"SourceAlpha":@[@0,@0,@0,@.82], @"PreviewAlpha":@[@0,@0,@0,@.83]};
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    ExperimentSourceFixture *editor = [[ExperimentSourceFixture alloc] initWithFrame:NSMakeRect(0,0,600,480)];
    editor.string = @"source text";
    NSWindow *sourceWindow = window(editor);
    ScrapPDFKitView *pdf = [[ScrapPDFKitView alloc] initWithFrame:NSMakeRect(0,0,600,480)];
    NSWindow *pdfWindow = window(pdf);
    pdf.document = document(); pump();
    check([editor.backgroundColor isEqual:NSColor.whiteColor], @"initial source theme");
    check([editor.insertionPointColor isEqual:NSColor.blueColor], @"initial insertion color");
    check([pdf.backgroundColor isEqual:NSColor.grayColor], @"initial preview theme");
    check(fabs(sourceWindow.alphaValue-.92)<.001 && fabs(pdfWindow.alphaValue-.93)<.001, @"initial source/PDF transparency");
    check(!inverted(pdf), @"system light pages");
    NSMenuItem *next = [[NSMenuItem alloc] initWithTitle:@"Next" action:@selector(goToNextPage:) keyEquivalent:@""];
    NSMenuItem *previous = [[NSMenuItem alloc] initWithTitle:@"Previous" action:@selector(goToPreviousPage:) keyEquivalent:@""];
    check(![pdf validateMenuItem:next] && ![pdf validateMenuItem:previous], @"single page navigation stays disabled");
    PDFDocument *twoPages = document();
    [twoPages insertPage:[document() pageAtIndex:0] atIndex:1];
    pdf.document = twoPages; pump();
    check([pdf validateMenuItem:next] && ![pdf validateMenuItem:previous], @"first page navigation uses PDFKit validation");
    [pdf goToLastPage:nil]; pump();
    check(![pdf validateMenuItem:next] && [pdf validateMenuItem:previous], @"last page navigation uses PDFKit validation");
    pdf.document = document(); pump();
    NSMenuToolbarItem *appearance = nil;
    for (NSToolbarItem *item in pdfWindow.toolbar.items)
        if ([item.itemIdentifier isEqual:TSPreviewAppearanceToolbarID]) appearance=(id)item;
    check(appearance.menu.numberOfItems == 3, @"actual toolbar contains three choices");
    for (NSMenuItem *choice in appearance.menu.itemArray) {
        check(choice.target == pdf && choice.action == @selector(changePreviewAppearance:), @"menu wiring");
    }
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]; pump();
    check([editor.backgroundColor isEqual:NSColor.blackColor] && [editor.textColor isEqual:NSColor.whiteColor], @"source follows system dark");
    check([[editor.textStorage attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] isEqual:NSColor.whiteColor], @"existing source text recolored");
    check([editor.insertionPointColor isEqual:NSColor.cyanColor], @"dark insertion color");
    check([pdf.backgroundColor isEqual:NSColor.darkGrayColor], @"preview follows system dark");
    check(fabs(sourceWindow.alphaValue-.82)<.001 && fabs(pdfWindow.alphaValue-.83)<.001, @"dark transparency");
    check(inverted(pdf), @"system dark pages even though PDF scroll view is forced light");
    NSArray *filters = pdf.documentView.enclosingScrollView.contentFilters;
    check([[(CIFilter *)filters[0] name] isEqualToString:@"CIGammaAdjust"] &&
          [[(CIFilter *)filters[1] name] isEqualToString:@"CIColorMatrix"] &&
          [[(CIFilter *)filters[2] name] isEqualToString:@"CIGammaAdjust"], @"inversion filter order");
    check(fabs([[filters[0] valueForKey:@"inputPower"] doubleValue]-.625)<1e-6 &&
          fabs([[filters[2] valueForKey:@"inputPower"] doubleValue]-1.6)<1e-6, @"inversion gamma contract");
    CGFloat factor = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldIncreaseContrast ? 1.9337 : 1.8972;
    NSArray *vectors = @[@"inputRVector", @"inputGVector", @"inputBVector"];
    CGFloat weights[] = {.2126, .7152, .0722};
    for (NSUInteger row=0; row<3; row++) {
        CIVector *v = [filters[1] valueForKey:vectors[row]];
        for (NSUInteger column=0; column<4; column++) {
            CGFloat expected = column==3 ? 0 : (row==column ? 1 : 0)-weights[column]*factor;
            check(fabs([v valueAtIndex:column]-expected)<1e-6, @"inversion matrix contract");
        }
    }
    CIVector *bias = [filters[1] valueForKey:@"inputBiasVector"];
    CIVector *alpha = [filters[1] valueForKey:@"inputAVector"];
    check(bias.X==1 && bias.Y==1 && bias.Z==1 && bias.W==0 &&
          alpha.X==0 && alpha.Y==0 && alpha.Z==0 && alpha.W==1, @"inversion preserves page alpha");
    [appearance.menu performActionForItemAtIndex:1]; pump();
    check([testDefaults integerForKey:TSPreviewAppearanceModeKey] == 1 && !inverted(pdf), @"Light choice persists and overrides dark system");
    for (NSMenuItem *choice in appearance.menu.itemArray) {
        [pdf validateMenuItem:choice];
        check(choice.state == (choice.tag==1 ? NSControlStateValueOn : NSControlStateValueOff), @"selected choice checkmark");
    }
    [appearance.menu performActionForItemAtIndex:2]; pump();
    check(inverted(pdf), @"Dark choice");
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua]; pump();
    check(inverted(pdf) && [pdf.backgroundColor isEqual:NSColor.grayColor], @"dark PDF independent of light window theme");
    // A normal preview writes this same key; Experiment must respond without a local action.
    [testDefaults setInteger:1 forKey:TSPreviewAppearanceModeKey]; pump();
    check(!inverted(pdf), @"external shared setting change");
    [testDefaults setInteger:2 forKey:TSPreviewAppearanceModeKey]; pump();
    check(inverted(pdf), @"external dark shared setting change");
    pdf.documentView.enclosingScrollView.contentFilters = @[];
    pdf.document = document(); pump();
    check(inverted(pdf), @"page appearance reapplied after document replacement");
    NSDictionary *custom = @{@"EditorBackground":NSColor.yellowColor, @"EditorText":NSColor.purpleColor,
        @"EditorInsertionPoint":NSColor.redColor, @"PreviewBackground":NSColor.orangeColor,
        @"SourceAlpha":@[@0,@0,@0,@.7], @"PreviewAlpha":@[@0,@0,@0,@.8]};
    [NSNotificationCenter.defaultCenter postNotificationName:SourceColorChangedNotification object:nil userInfo:custom];
    check([editor.backgroundColor isEqual:NSColor.yellowColor] && [editor.textColor isEqual:NSColor.purpleColor], @"live source theme edit");
    check([pdf.backgroundColor isEqual:NSColor.orangeColor], @"live preview theme edit");
    check(fabs(sourceWindow.alphaValue-.7)<.001 && fabs(pdfWindow.alphaValue-.8)<.001, @"live transparency edit");
    [NSNotificationCenter.defaultCenter postNotificationName:SourceColorChangedNotification object:nil];
    check([editor.backgroundColor isEqual:NSColor.whiteColor] && [pdf.backgroundColor isEqual:NSColor.grayColor], @"theme cancel restores saved colors");
    // A later Experiment must adopt the persisted preference and theme immediately.
    ScrapPDFKitView *secondPDF = [[ScrapPDFKitView alloc] initWithFrame:NSMakeRect(0,0,600,480)];
    NSWindow *secondWindow = window(secondPDF); secondPDF.document=document(); pump();
    check(inverted(secondPDF), @"new preview inherits shared appearance");
    [appearance.menu performActionForItemAtIndex:0]; pump();
    check(!inverted(pdf) && !inverted(secondPDF), @"System choice propagates to all Experiment previews");
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]; pump();
    check(inverted(pdf) && inverted(secondPDF), @"System choice follows later system change");
    check(TSExperimentWindowAlpha(@{}, @"SourceAlpha")==1, @"missing alpha stays opaque");
    check(TSExperimentWindowAlpha(@{@"SourceAlpha":@[@0]}, @"SourceAlpha")==1, @"malformed alpha stays opaque");
    check(!sourceWindow.isVisible && !pdfWindow.isVisible && !secondWindow.isVisible, @"no windows displayed");
    [sourceWindow close]; [pdfWindow close]; [secondWindow close];
    printf("PASS: %d Experiment theme and PDF appearance checks\n", checks);
} return 0; }
'''
with tempfile.TemporaryDirectory(prefix='texshop-experiment-themes-') as tmp:
    src, exe = Path(tmp)/'test.m', Path(tmp)/'test'
    src.write_text(prefix + pdf + tests)
    subprocess.run(['xcrun','clang','-w','-fobjc-arc','-framework','Cocoa','-framework','Quartz',
        '-I',str(root/'Sources'),str(src),'-o',str(exe)], check=True)
    result = subprocess.run([str(exe)],env=dict(os.environ,CFFIXED_USER_HOME=tmp),capture_output=True,text=True,timeout=30)
    if args.mutation:
        assert result.returncode == 1 and 'FAIL:' in result.stderr, result.stdout + result.stderr
        print('PASS: detected', args.mutation)
    else:
        if result.returncode: raise SystemExit(result.stdout + result.stderr)
        print(result.stdout.strip())
