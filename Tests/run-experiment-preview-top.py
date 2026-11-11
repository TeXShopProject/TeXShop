#!/usr/bin/env python3
"""Check that the first Experiment output shows the top of its first page.

The Experiment preview view is compiled from its complete production source and
runs on real PDFKit in windows that are never shown. On macOS 26, PDFKit may
place a document loaded into a hidden window, or lay it out again after the
window appears, away from the top; the test moves the view to the middle of the
page at those moments and checks that the top is shown again. Later typesetting
keeps the position the user was viewing. Defaults stay in memory.
"""
from pathlib import Path
import argparse, os, plistlib, subprocess, sys, tempfile
from source_tree import include_args
from experiment_preview_source import prelude as experiment_preview_prelude, sources as experiment_preview_sources

MUTATIONS = {
    'no-first-flag': ('        self.showsTopOfFirstPage = YES;\n', ''),
    'no-initial-top': ('        self.showsTopOfFirstPage = YES;\n        [self showTopOfFirstPage];\n',
                       '        self.showsTopOfFirstPage = YES;\n'),
    'no-late-pass': ('        view.showsTopOfFirstPage = NO;\n        [view showTopOfFirstPage];\n',
                     '        view.showsTopOfFirstPage = NO;\n'),
    'always-top': ('    if (!self.showsTopOfFirstPage) return;\n    [self showTopOfFirstPage];\n',
                   '    [self showTopOfFirstPage];\n'),
    'ignore-insets': ('    top = [clip constrainBoundsRect:top];\n',
                      '    top.origin.y = clip.isFlipped ? NSMinY(documentRect) : NSMaxY(documentRect) - NSHeight(top);\n'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
pdf = (root/'Sources/Preview/ScrapPDFKitView.m').read_text()
assert '- (void)didShowOutputWindow' in pdf and '- (void)showTopOfFirstPage' in pdf
if args.mutation:
    old, new = MUTATIONS[args.mutation]
    assert pdf.count(old) == 1, args.mutation
    pdf = pdf.replace(old, new)
for header in ['globals.h', 'TSDocument.h', 'TSEncodingSupport.h']:
    pdf = pdf.replace(f'#import "{header}"', '')
pdf = pdf.replace('#import "TSPreviewAppearance.h"', (root/'Sources/Preview/TSPreviewAppearance.h').read_text())
pdf = experiment_preview_prelude(root) + pdf

program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import <Quartz/Quartz.h>
#import "TSColorSupport.h"
#import "TSExperimentTheme.h"
static NSDictionary *liteColors, *darkColors;
static NSUserDefaults *testDefaults;
#define SUD testDefaults
#define SourceColorChangedNotification @"SourceColorChanged"
@implementation TSColorSupport
+ (id)sharedInstance { static id instance; if (!instance) instance = [self new]; return instance; }
- (NSColor *)colorForKey:(NSString *)key fromDictionary:(NSDictionary *)theme isWindowDark:(BOOL)dark { return NSColor.grayColor; }
@end
PDFSOURCE
static NSString *context = @"";
static NSUInteger checks;
static void Check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL: %s [%s]\n", message.UTF8String, context.UTF8String); exit(1); }
}
static void Pump(void) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:.15];
    while (end.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
}
// A4 pages; the first has a short formula near its top, as an Experiment produces.
static NSString *WritePDF(NSString *directory, NSUInteger pages) {
    NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"experiment-%lu.pdf", (unsigned long)pages]];
    NSMutableData *data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect box = CGRectMake(0, 0, 595, 842);
    CGContextRef c = CGPDFContextCreate(consumer, &box, NULL);
    for (NSUInteger n = 0; n < pages; n++) {
        CGPDFContextBeginPage(c, NULL);
        CGContextSetRGBFillColor(c, 0, 0, 0, 1);
        if (n == 0) CGContextFillRect(c, CGRectMake(220, 740, 160, 30));
        CGPDFContextEndPage(c);
    }
    CGPDFContextClose(c); CGContextRelease(c); CGDataConsumerRelease(consumer);
    [data writeToFile:path atomically:YES];
    return path;
}
typedef struct { NSInteger page; CGFloat top, bottom; } Visible;
// The part of the PDF not covered by the content insets, in page coordinates.
static Visible Seen(ScrapPDFKitView *view) {
    NSScrollView *scroll = view.documentView.enclosingScrollView;
    NSClipView *clip = scroll.contentView;
    NSRect b = clip.bounds; NSEdgeInsets i = scroll.contentInsets;
    CGFloat unit = NSHeight(b) / NSHeight(clip.frame);   // insets are in points, the clip in document units
    CGFloat topY = clip.isFlipped ? NSMinY(b) + i.top * unit : NSMaxY(b) - i.top * unit;
    CGFloat bottomY = clip.isFlipped ? NSMaxY(b) - i.bottom * unit : NSMinY(b) + i.bottom * unit;
    NSPoint top = [view convertPoint:NSMakePoint(NSMidX(b), topY) fromView:clip];
    NSPoint bottom = [view convertPoint:NSMakePoint(NSMidX(b), bottomY) fromView:clip];
    PDFPage *page = [view pageForPoint:top nearest:YES];
    PDFPage *first = [view.document pageAtIndex:0];
    Visible v = { (NSInteger)[view.document indexForPage:page], [view convertPoint:top toPage:first].y, [view convertPoint:bottom toPage:first].y };
    return v;
}
static void ExpectTop(ScrapPDFKitView *view, NSString *message) {
    Visible v = Seen(view);
    CGFloat margin = 30 / MAX(view.scaleFactor, .01);   // the gray gap PDFKit leaves above a page
    Check(v.top >= 842 - 1 && v.top <= 842 + margin, [message stringByAppendingFormat:@" (page top %.0f visible top %.0f)", 842.0, v.top]);
    Check(v.bottom < 740, [message stringByAppendingString:@" — formula visible"]);
}
static BOOL MoveToMiddle(ScrapPDFKitView *view) {
    // What PDFKit on macOS 26 may do: centre the first page in the view.
    PDFPage *page = [view.document pageAtIndex:0];
    NSScrollView *scroll = view.documentView.enclosingScrollView; NSClipView *clip = scroll.contentView;
    NSPoint middle = [view.documentView convertPoint:[view convertPoint:NSMakePoint(297, 150) fromPage:page] fromView:view];
    NSRect b = clip.bounds; b.origin.y = middle.y - NSHeight(b) / 2;
    [clip scrollToPoint:[clip constrainBoundsRect:b].origin]; [scroll reflectScrolledClipView:clip];
    // A window showing the whole page has nowhere else to go.
    return Seen(view).top < 700;
}
static NSPanel *Panel(NSSize size, ScrapPDFKitView **view) {
    // Same structure as the Experiment preview in TSDocument.nib.
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(272, 172, size.width, size.height)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable|NSWindowStyleMaskUtilityWindow
        backing:NSBackingStoreBuffered defer:YES];
    panel.releasedWhenClosed = NO;
    ScrapPDFKitView *pdf = [[ScrapPDFKitView alloc] initWithFrame:NSMakeRect(0, -10, size.width, size.height + 10)];
    pdf.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;
    [panel.contentView addSubview:pdf];
    *view = pdf; Pump();
    return panel;
}
int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    testDefaults = [TSMemoryDefaults new];
    NSString *dir = @(argv[1]);
    NSString *one = WritePDF(dir, 1), *two = WritePDF(dir, 2);
    NSUInteger windows = 0, seconds = 0;
    for (NSValue *value in @[[NSValue valueWithSize:NSMakeSize(276, 378)], [NSValue valueWithSize:NSMakeSize(640, 300)], [NSValue valueWithSize:NSMakeSize(900, 420)]]) {
        for (NSNumber *inset in @[@0, @52]) {
            for (NSString *path in @[one, two]) {
                ScrapPDFKitView *view; NSPanel *panel = Panel(value.sizeValue, &view);
                // Showing the window; on macOS 26 its toolbar lets the content scroll under it.
                void (^appear)(void) = ^{
                    NSScrollView *scroll = view.documentView.enclosingScrollView;
                    if (inset.doubleValue) {
                        scroll.automaticallyAdjustsContentInsets = NO;
                        scroll.contentInsets = NSEdgeInsetsMake(inset.doubleValue, 0, 0, 0);
                    }
                    Check(scroll.contentInsets.top == inset.doubleValue, @"Fixture inset applied");
                    [panel makeKeyAndOrderFront:nil];
                };
                context = [NSString stringWithFormat:@"%.0fx%.0f inset %@ %@", value.sizeValue.width, value.sizeValue.height, inset, path.lastPathComponent];
                windows++;
                BOOL fits = value.sizeValue.height == 378 && path == one;

                // First output: misplaced while the window is hidden, and again after it appears.
                [view reShowWithPath:path];
                Check(view.document.pageCount == (path == one ? 1 : 2), @"PDF loaded");
                ExpectTop(view, @"Top shown right after loading");
                Check(MoveToMiddle(view) || fits, @"Fixture moves away from the formula unless the page fits");
                appear();
                Check(MoveToMiddle(view) || fits, @"Fixture moves when the window appears");
                [view didShowOutputWindow];
                ExpectTop(view, @"Top shown when the window appears");
                Check(MoveToMiddle(view) || fits, @"Fixture moves again");
                Pump();
                ExpectTop(view, @"Top shown after a late layout");
                Check(Seen(view).page == 0, @"First page, not a later one");

                // Later output keeps the position the user is viewing.
                if (!fits) {
                    MoveToMiddle(view);
                    Visible before = Seen(view);
                    [view reShowWithPath:path];
                    appear();
                    [view didShowOutputWindow]; Pump();
                    Visible after = Seen(view);
                    // Re-applying the fixture inset may shift the view by that much.
                    Check(after.top < 700 && fabs(after.top - before.top) < (40 + inset.doubleValue) / view.scaleFactor, @"Second typesetting keeps the viewed position");
                    seconds++;
                }

                // Closing the Experiment empties the preview; the next output is a first output.
                [panel close]; [view setDocument:nil];
                [view reShowWithPath:path];
                Check(MoveToMiddle(view) || fits, @"Fixture moves after reopening");
                appear();
                [view didShowOutputWindow]; MoveToMiddle(view); Pump();
                ExpectTop(view, @"Top shown again after the Experiment was closed");
                [panel close];
            }
        }
    }
    Check(windows == 12 && seconds == 10, @"All window sizes, insets and page counts");
    printf("PASS: first Experiment output shows the top of page 1 (%lu checks)\n", (unsigned long)checks);
}}
'''.replace('PDFSOURCE', pdf)
with tempfile.TemporaryDirectory(prefix='TeXShop-experiment-top-') as tmp:
    tmp = Path(tmp)
    app = tmp/'ExperimentTopTest.app'; mac = app/'Contents/MacOS'; mac.mkdir(parents=True)
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'org.texshop.ExperimentTopTest.'+tmp.name,
        'CFBundleExecutable': 'ExperimentTopTest', 'CFBundlePackageType': 'APPL', 'LSUIElement': True}))
    (tmp/'Test.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-w', *include_args(root), '-I'+str(root/'Tests'),
                    '-framework', 'Cocoa', '-framework', 'Quartz', str(tmp/'Test.m'), *experiment_preview_sources(root), '-o', str(mac/'ExperimentTopTest')], check=True)
    home = tmp/'Home'; (home/'Library/Preferences').mkdir(parents=True)
    try:
        result = subprocess.run([str(mac/'ExperimentTopTest'), str(tmp)], env={**os.environ, 'CFFIXED_USER_HOME': str(home)},
                                capture_output=True, text=True)
        sys.stdout.write(result.stdout); sys.stderr.write(result.stderr)
        sys.exit(result.returncode)
    finally:
        subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister', '-u', str(app)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
