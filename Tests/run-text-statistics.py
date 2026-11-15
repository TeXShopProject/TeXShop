#!/usr/bin/env python3
"""Text Statistics: the popover opened from the status bar or Edit > Statistics….

Offscreen, with in-memory defaults, never ordering a window or a popover on screen (the
popover's show is recorded instead):

1. TSTextStatistics with the TeX Live detex: the Text column is what detex leaves of the
   text, with the files read by \\input, counted as the status bar counts (compared with the
   same detex run here); the Source column is the status bar's count. The text in memory is
   counted, not the file on disk (nothing is saved); the selection is counted when there is
   one; the temporary file is gone afterwards. Japanese words and characters: wc counts a
   Japanese sentence as one word and, in the C locale, counts bytes for -m; the popover does
   neither.
2. Stand-in detex programs: a second count stops a detex still running (the process ends,
   its temporary file is removed, its result never shows); a missing or failing detex shows
   a warning in place of the Text column while the Source column stays.
3. The popover: detex runs when it opens and when its refresh button is pressed, never while
   typing; the heading says Whole Document or Selection; the time of the count; a spinner
   while counting; the ⓘ mark's tool tip and VoiceOver label.
4. Edit > Statistics… and the status bar's button (the production TSDocument methods): the
   popover points at the button; with the status bar hidden, at the bottom edge of the part
   of the source being typed in; also in the window that shows both. The document nibs
   no longer hold the former Statistics panel.
5. The menus keep Edit > Statistics… with its shortcut identifier in 12 languages; the old
   statistics code and detexwrap are gone.

--images DIR draws the source window of the Base and Japanese nibs in Light and Dark Mode
with the popover's content (production views) in a drawn popover frame above the button:
whole document, selection, counting, detex missing, and the ⓘ tool tip (drawn as a box,
because tool tips cannot be drawn offscreen).
"""
import argparse, json, os, shutil, subprocess, sys, tempfile
from pathlib import Path
from source_tree import include_args, source_file
from production_fragments import method, verify_embedded

DETEX = next((p for p in ('/Applications/TeXLive/2026/bin/universal-darwin/detex', '/Library/TeX/texbin/detex') if Path(p).exists()), None)
MUTATIONS = {
    # A second count leaves the first detex running.
    'previous-not-stopped': ('TSTextStatistics.m', '    [self stop];\n    BOOL selection = NO;\n', '    BOOL selection = NO;\n'),
    # Stopping waits for the end of detex's output, which a process detex left may hold open.
    'waits-for-pipe-end': ('TSTextStatistics.m', '                    if (!dispatch_source_testcancel(reader)) {\n', '                    while (!dispatch_source_testcancel(reader)) usleep(10000);\n                    if (!dispatch_source_testcancel(reader)) {\n'),
    # The temporary file stays.
    'file-kept': ('TSTextStatistics.m', '        TSRemoveFile(file);\n        if (atomic_load(&run->cancelled))\n', '        if (atomic_load(&run->cancelled))\n'),
    # Typing counts again while the popover is open.
    'counts-while-typing': ('TSTextStatisticsPopover.m', '        _popover.delegate = self;\n',
                            '        _popover.delegate = self;\n        [NSNotificationCenter.defaultCenter addObserverForName:NSTextDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *n) { [weakSelf refresh]; }];\n'),
    # With the status bar hidden, nothing opens.
    'no-anchor-when-hidden': ('TSDocument.m', '    [self showStatisticsRelativeToRect:bottom ofView:scroll];\n', ''),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
parser.add_argument('--images', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
failures = []
def fail(message):
    failures.append(message); print('FAIL:', message)
if not DETEX:
    sys.exit('FAIL: TeX Live detex is needed')

# 5. Static: the menus, the removed code.
import xml.etree.ElementTree as ET
for lang in ['Base', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN']:
    tree = ET.parse(root / f'Resources/Interfaces/{lang}.lproj/MainMenu.nib/designable.nib').getroot()
    items = [i for i in tree.iter('menuItem') if i.find("connections/action[@selector='showStatistics:']") is not None]
    if len(items) != 1 or items[0].get('identifier') != 'TSShortcut.showStatistics:.0':
        fail(f'{lang}: Edit > Statistics… stays with its shortcut identifier')
names = ('TSStatusBarCounting.m', 'TSSourceStatusBar.m', 'TSTextStatistics.m', 'TSTextStatisticsPopover.m', 'TSDocument.m', 'TSDocumentWindowGlass.m')
text = {n: source_file(root, n).read_text(encoding='utf-8', errors='surrogateescape') for n in names}
document = text['TSDocument.m']
header = source_file(root, 'TSDocument.h').read_text(encoding='utf-8', errors='surrogateescape')
for gone in ('updateStatistics', 'saveForStatistics', 'detexTask', 'detexHandle', 'detexPipe', 'statTempFile', 'statisticsForm cellAtIndex',
             'detexwrap', '*statisticsPanel', '*statisticsForm'):
    if gone in document or gone in header:
        fail(f'the former statistics code is gone: {gone}')
if (root / 'Resources/Shellscripts/detexwrap').exists() or 'detexwrap' in (root / 'TeXShop.xcodeproj/project.pbxproj').read_text():
    fail('detexwrap is gone')
if 'saveDocument' in method(document, '- (void)showStatistics: sender') + method(document, '- (void)showStatisticsRelativeToRect:(NSRect)rect ofView:(NSView *)view'):
    fail('Statistics does not save')
fragments = {
    'show': method(document, '- (void)showStatistics: sender'),
    'from': method(document, '- (void)showStatisticsFromView:(NSView *)anchor'),
    'rect': method(document, '- (void)showStatisticsRelativeToRect:(NSRect)rect ofView:(NSView *)view'),
}
originals = dict(fragments)
if args.mutation:
    name, old, new = MUTATIONS[args.mutation]
    if name == 'TSDocument.m':
        assert fragments['show'].count(old) == 1; fragments['show'] = fragments['show'].replace(old, new)
    else:
        assert text[name].count(old) == 1, args.mutation; text[name] = text[name].replace(old, new)

PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <signal.h>
#import "TestAppKitIsolation.h"
#import "TSDocumentWindowGlass.h"
#import "TSSourceStatusBar.h"
#import "TSTextStatisticsPopover.h"
static int failures, checks;
static void Check(BOOL ok, NSString *name) { checks++; if (!ok) { printf("FAIL: %s\n", name.UTF8String); failures++; } }

// The popover is never shown: where it would point is recorded.
static NSView *shownView; static NSRect shownRect; static NSRectEdge shownEdge; static NSUInteger shows;
static void RecordShow(NSPopover *p, SEL s, NSRect rect, NSView *view, NSRectEdge edge) { shownView = view; shownRect = rect; shownEdge = edge; shows++; }

@interface TSDocumentBase : NSObject @end
@implementation TSDocumentBase @end
@interface TSDocument : TSDocumentBase
{
@public
    NSSplitView *splitView;
    NSScrollView *scrollView, *scrollView2;
    NSTextView *textView, *textView1, *textView2;
    NSView *leftView, *rightView;
    NSWindow *textWindow, *fullSplitWindow;
    NSStringEncoding _encoding;
}
@property (strong) NSWindow *pdfKitWindow;
@property (strong) TSSourceStatusBar *sourceStatusBar;
@property (strong) TSTextStatisticsPopover *textStatistics;
@property (strong) NSURL *fileURL;
- (void)showStatistics:sender;
- (void)showStatisticsFromView:(NSView *)anchor;
- (void)showStatisticsRelativeToRect:(NSRect)rect ofView:(NSView *)view;
@end
@implementation TSDocument
- (NSTextView *)textView { return textView; }
@@SHOW@@
@@FROM@@
@@RECT@@
@end

static void Register(NSString *name, Class base) {
    if (NSClassFromString(name)) return;
    objc_registerClassPair(objc_allocateClassPair(base, name.UTF8String, 0));
}
static void Spin(double seconds) { [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]]; }
static BOOL WaitFor(BOOL (^done)(void), double seconds) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!done() && limit.timeIntervalSinceNow > 0) Spin(0.01);
    return done();
}
static NSString *L(NSString *key) { return NSLocalizedString(key, @""); }
static NSUInteger TemporaryFiles(void) {
    NSUInteger n = 0;
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:NSTemporaryDirectory() error:NULL])
        if ([name hasPrefix:@"TeXShop-statistics-"]) n++;
    return n;
}
static BOOL Alive(pid_t pid) { return pid > 0 && kill(pid, 0) == 0; }
static pid_t PidIn(NSString *file) { return (pid_t)[[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:NULL] intValue]; }

static NSData *nibData;
static TSDocument *Open(NSString *string) {
    TSDocument *doc = [TSDocument new];
    NSArray *objects;
    if (![[[NSNib alloc] initWithNibData:nibData bundle:nil] instantiateWithOwner:doc topLevelObjects:&objects]) return nil;
    for (NSWindow *w in objects) if ([w isKindOfClass:NSWindow.class]) w.releasedWhenClosed = NO;
    doc->textView = doc->textView1;
    doc->_encoding = NSUTF8StringEncoding;
    [doc->scrollView2 removeFromSuperview];
    [doc->textView2.layoutManager replaceTextStorage:doc->textView1.textStorage];
    [doc->textView1.textStorage setAttributedString:[[NSAttributedString alloc] initWithString:string
        attributes:@{NSFontAttributeName: [NSFont userFixedPitchFontOfSize:13], NSForegroundColorAttributeName: NSColor.textColor}]];
    doc->textView2.font = doc->textView1.font;
    __weak TSDocument *weakDocument = doc;
    doc.sourceStatusBar = [[TSSourceStatusBar alloc] initWithTextStorage:doc->textView1.textStorage textViews:@[doc->textView1, doc->textView2]
                                                         activeTextView:^NSTextView *{ return [weakDocument textView]; }];
    [doc.sourceStatusBar placeBelowView:doc->splitView];
    doc.sourceStatusBar.showStatistics = ^(NSView *anchor) { [weakDocument showStatisticsFromView:anchor]; };
    [doc->textWindow setFrame:NSMakeRect(40, 40, 760, 640) display:NO];
    WaitFor(^BOOL{ return !doc.sourceStatusBar.counting; }, 10);
    return doc;
}

// Pictures: the window, with the popover's content in a drawn popover frame above the anchor.
static NSString *images;
static NSBitmapImageRep *Snapshot(NSView *view) {
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    return rep;
}
static void DrawWithPopover(TSDocument *doc, NSString *name, NSString *tip) {
    if (!images) return;
    NSViewController *content = doc.textStatistics.contentController;
    for (NSString *look in @[@"light", @"dark"]) {
        NSAppearance *appearance = [NSAppearance appearanceNamed:[look isEqual:@"dark"] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
        doc->textWindow.appearance = appearance;
        NSWindow *holder = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 200) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:YES];
        holder.appearance = appearance;
        [NSAppearance setCurrentAppearance:appearance];
        // The popover's background, which the drawing cannot take from the glass.
        holder.backgroundColor = [NSColor.windowBackgroundColor blendedColorWithFraction:0.15 ofColor:NSColor.controlBackgroundColor];
        holder.contentView = content.view;
        [content.view layoutSubtreeIfNeeded];
        [holder setContentSize:content.view.fittingSize];
        [content.view layoutSubtreeIfNeeded];
        NSBitmapImageRep *pop = Snapshot(holder.contentView.superview);
        NSView *frame = doc->textWindow.contentView.superview;
        [doc->textWindow layoutIfNeeded]; [frame layoutSubtreeIfNeeded];
        NSBitmapImageRep *win = Snapshot(frame);
        NSImage *out = [[NSImage alloc] initWithSize:frame.bounds.size];
        [out lockFocus];
        [win drawInRect:frame.bounds];
        NSRect anchor = [shownView convertRect:shownRect toView:nil];
        NSSize size = content.view.bounds.size;
        CGFloat arrow = 10, x = MIN(MAX(NSMidX(anchor) - size.width / 2, 8), NSWidth(frame.bounds) - size.width - 8);
        NSRect box = NSMakeRect(x, NSMaxY(anchor) + arrow, size.width, size.height);
        [NSAppearance setCurrentAppearance:appearance];
        [NSGraphicsContext saveGraphicsState];
        NSShadow *shadow = [NSShadow new]; shadow.shadowBlurRadius = 14; shadow.shadowOffset = NSMakeSize(0, -3);
        shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.3]; [shadow set];
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:box xRadius:14 yRadius:14];
        [path moveToPoint:NSMakePoint(NSMidX(anchor) - arrow, NSMinY(box))];
        [path lineToPoint:NSMakePoint(NSMidX(anchor), NSMaxY(anchor) + 1)];
        [path lineToPoint:NSMakePoint(NSMidX(anchor) + arrow, NSMinY(box))];
        [[NSColor.windowBackgroundColor blendedColorWithFraction:0.15 ofColor:NSColor.controlBackgroundColor] setFill];
        [path fill];
        [NSGraphicsContext restoreGraphicsState];
        [NSColor.separatorColor setStroke]; [path stroke];
        [NSGraphicsContext saveGraphicsState];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(box, 0.5, 0.5) xRadius:14 yRadius:14] addClip];
        [pop drawInRect:box];
        [NSGraphicsContext restoreGraphicsState];
        if (tip) {
            NSView *mark = [content isKindOfClass:TSTextStatisticsViewController.class] ? [(TSTextStatisticsViewController *)content infoMark] : nil;
            NSRect m = [mark convertRect:mark.bounds toView:nil];
            NSPoint at = NSMakePoint(NSMinX(box) + NSMinX(m) + 4, NSMinY(box) + NSMinY(m) - 26);
            NSDictionary *attrs = @{NSFontAttributeName: [NSFont toolTipsFontOfSize:0], NSForegroundColorAttributeName: NSColor.labelColor};
            NSSize ts = [tip sizeWithAttributes:attrs];
            NSRect tr = NSMakeRect(MIN(at.x, NSWidth(frame.bounds) - ts.width - 20), at.y - ts.height, ts.width + 12, ts.height + 6);
            [NSColor.windowBackgroundColor setFill]; NSRectFill(tr);
            [NSColor.separatorColor setStroke]; [NSBezierPath strokeRect:tr];
            [tip drawAtPoint:NSMakePoint(NSMinX(tr) + 6, NSMinY(tr) + 3) withAttributes:attrs];
        }
        [out unlockFocus];
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:out.TIFFRepresentation];
        [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[images stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@-%@.png", name, look]] atomically:YES];
        holder.contentView = nil;
    }
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    method_setImplementation(class_getInstanceMethod(NSPopover.class, @selector(showRelativeToRect:ofView:preferredEdge:)), (IMP)RecordShow);
    for (NSString *name in @[@"TSConsoleWindow", @"TSFullSplitWindow", @"TSFullscreenWindow", @"TSHTMLWindow", @"TSLogWindow", @"TSPreviewWindow", @"TSTextEditorWindow"]) Register(name, NSWindow.class);
    Register(@"MyPDFView", NSView.class); Register(@"MyPDFKitView", NSClassFromString(@"PDFView") ?: NSView.class); Register(@"ScrapPDFKitView", NSClassFromString(@"PDFView") ?: NSView.class);
    Register(@"TSTextView", NSTextView.class); Register(@"ScrapTextView", NSTextView.class); Register(@"TSAdvancedFindTextView", NSTextView.class);
    NSDictionary *spec = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:NULL];
    nibData = [NSData dataWithContentsOfFile:spec[@"nib"]];
    NSString *lang = spec[@"lang"], *tag = [NSString stringWithFormat:@" (%@)", lang];
    images = [spec[@"images"] length] ? spec[@"images"] : nil;
    NSURL *detex = [NSURL fileURLWithPath:spec[@"detex"]], *slow = [NSURL fileURLWithPath:spec[@"slow"]], *failing = [NSURL fileURLWithPath:spec[@"failing"]];
    NSURL *folder = [NSURL fileURLWithPath:spec[@"folder"] isDirectory:YES];
    NSString *memory = spec[@"memory"];
    NSUInteger before = TemporaryFiles();

    // 1. The TeX Live detex, on the text in memory; the file on disk stays as it was.
    TSTextStatistics *statistics = [TSTextStatistics new];
    __block TSTextStatisticsResult *result = nil;
    [statistics countString:memory ranges:@[[NSValue valueWithRange:NSMakeRange(0, 0)]] folder:folder detex:detex encoding:NSUTF8StringEncoding
                 completion:^(TSTextStatisticsResult *r) { result = r; }];
    Check(statistics.running && statistics.temporaryFile != nil, [@"a count runs with its temporary file" stringByAppendingString:tag]);
    Check(WaitFor(^BOOL{ return result != nil; }, 20) && result.state == TSTextStatisticsDone && !result.selection, [@"detex counts the whole text" stringByAppendingString:tag]);
    TSStatusBarCounts want = TSStatusBarCountsUnknown(), source = TSStatusBarCountsUnknown();
    TSStatusBarCount(spec[@"oracle"], @[], YES, NO, &want, nil);
    TSStatusBarCount(memory, @[], YES, NO, &source, nil);
    Check(result.text.characters == want.characters && result.text.words == want.words && result.text.lines == want.lines,
          [NSString stringWithFormat:@"the Text column is detex's output (with \\input), counted as the status bar counts: %lu/%lu/%lu, expected %lu/%lu/%lu%@",
           result.text.characters, result.text.words, result.text.lines, want.characters, want.words, want.lines, tag]);
    Check(result.source.characters == source.characters && result.source.words == source.words && result.source.lines == source.lines,
          [@"the Source column is the status bar's count of the text in memory" stringByAppendingString:tag]);
    Check([[NSString stringWithContentsOfURL:[folder URLByAppendingPathComponent:@"main.tex"] encoding:NSUTF8StringEncoding error:NULL] isEqual:spec[@"disk"]],
          [@"nothing is saved: the file on disk is unchanged" stringByAppendingString:tag]);
    Check(!statistics.running && TemporaryFiles() == before, [@"the temporary file is removed" stringByAppendingString:tag]);
    // Japanese: the sentence alone through detex.
    result = nil;
    NSString *japanese = [spec[@"sentence"] stringByAppendingString:@"\n"];
    [statistics countString:japanese ranges:@[] folder:folder detex:detex encoding:NSUTF8StringEncoding completion:^(TSTextStatisticsResult *r) { result = r; }];
    WaitFor(^BOOL{ return result != nil; }, 20);
    printf("JAPANESE: the Text column: %lu characters, %lu words (wc: %s bytes for -m in the C locale, %s word for -w)\n",
           result.text.characters, result.text.words, [spec[@"wcBytes"] description].UTF8String, [spec[@"wcWords"] description].UTF8String);
    Check(result.text.characters == [spec[@"sentence"] length] + 1 && result.text.characters != [spec[@"wcBytes"] unsignedIntegerValue]
          && result.text.words >= 4 && result.text.words != [spec[@"wcWords"] unsignedIntegerValue],
          [NSString stringWithFormat:@"Japanese: characters as seen (%lu) and words by the word boundaries (%lu), not wc's bytes and blank-separated chunks%@",
           result.text.characters, result.text.words, tag]);
    // The selection.
    NSRange sentence = [memory rangeOfString:spec[@"sentence"]];
    result = nil;
    [statistics countString:memory ranges:@[[NSValue valueWithRange:sentence]] folder:folder detex:detex encoding:NSUTF8StringEncoding
                 completion:^(TSTextStatisticsResult *r) { result = r; }];
    Check(WaitFor(^BOOL{ return result != nil; }, 20) && result.selection && result.source.characters == TSStatusBarCharacterCount(memory, sentence, nil)
          && result.text.characters != NSNotFound, [NSString stringWithFormat:@"the selection is counted (%lu)%@", result.source.characters, tag]);

    // 2. A second count stops the first detex; stop ends it; missing or failing detex.
    NSString *pidFile = spec[@"pid"];
    __block NSUInteger firstDone = 0;
    [statistics countString:memory ranges:@[] folder:folder detex:slow encoding:NSUTF8StringEncoding completion:^(TSTextStatisticsResult *r) { firstDone++; }];
    NSURL *firstFile = statistics.temporaryFile;
    Check(WaitFor(^BOOL{ return Alive(PidIn(pidFile)); }, 10), [@"the slow detex runs" stringByAppendingString:tag]);
    pid_t first = PidIn(pidFile);
    result = nil;
    [statistics countString:memory ranges:@[] folder:folder detex:detex encoding:NSUTF8StringEncoding completion:^(TSTextStatisticsResult *r) { result = r; }];
    Check(WaitFor(^BOOL{ return !Alive(first); }, 5), [@"a second count stops the detex still running" stringByAppendingString:tag]);
    Check(WaitFor(^BOOL{ return result != nil; }, 20) && result.state == TSTextStatisticsDone && firstDone == 0,
          [@"only the second count shows" stringByAppendingString:tag]);
    Check(![NSFileManager.defaultManager fileExistsAtPath:firstFile.path] && TemporaryFiles() == before, [@"the first count's temporary file is removed" stringByAppendingString:tag]);
    [NSFileManager.defaultManager removeItemAtPath:pidFile error:NULL];
    [statistics countString:memory ranges:@[] folder:folder detex:slow encoding:NSUTF8StringEncoding completion:^(TSTextStatisticsResult *r) { firstDone++; }];
    WaitFor(^BOOL{ return Alive(PidIn(pidFile)); }, 10);
    pid_t stopped = PidIn(pidFile);
    [statistics stop];
    Check(WaitFor(^BOOL{ return !Alive(stopped) && TemporaryFiles() == before; }, 5) && firstDone == 0, [@"stop ends detex and removes the file" stringByAppendingString:tag]);
    Spin(0.2);
    // A process that detex left holds the output open: stopping detex does not wait for it, nor does detex's own end.
    NSURL *holding = [NSURL fileURLWithPath:spec[@"holding"]], *leaving = [NSURL fileURLWithPath:spec[@"leaving"]];
    [NSFileManager.defaultManager removeItemAtPath:pidFile error:NULL];
    [statistics countString:memory ranges:@[] folder:folder detex:holding encoding:NSUTF8StringEncoding completion:^(TSTextStatisticsResult *r) { firstDone++; }];
    NSURL *heldFile = statistics.temporaryFile;
    Check(WaitFor(^BOOL{ return Alive(PidIn(pidFile)); }, 10), [@"the detex that leaves a process runs" stringByAppendingString:tag]);
    Spin(0.3);
    result = nil;
    CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
    [statistics countString:memory ranges:@[] folder:folder detex:nil encoding:NSUTF8StringEncoding completion:^(TSTextStatisticsResult *r) { result = r; }];
    Check(WaitFor(^BOOL{ return result != nil; }, 1.5) && firstDone == 0 && ![NSFileManager.defaultManager fileExistsAtPath:heldFile.path],
          [NSString stringWithFormat:@"a stopped detex whose output another process holds does not hold up the next count or the removal of its file (%.2f s)%@",
           CFAbsoluteTimeGetCurrent() - started, tag]);
    result = nil;
    started = CFAbsoluteTimeGetCurrent();
    [statistics countString:memory ranges:@[] folder:folder detex:leaving encoding:NSUTF8StringEncoding completion:^(TSTextStatisticsResult *r) { result = r; }];
    Check(WaitFor(^BOOL{ return result != nil; }, 3) && result.state == TSTextStatisticsDone && result.text.characters == source.characters,
          [NSString stringWithFormat:@"a detex that ends leaving a process with its output is counted without waiting for that process (%.2f s, %lu)%@",
           CFAbsoluteTimeGetCurrent() - started, result.text.characters, tag]);
    Check(WaitFor(^BOOL{ return TemporaryFiles() == before; }, 2), [@"and its file is removed" stringByAppendingString:tag]);
    for (NSArray *c in @[@[[NSNull null], @(TSTextStatisticsDetexMissing)], @[failing, @(TSTextStatisticsDetexFailed)]]) {
        result = nil;
        [statistics countString:memory ranges:@[] folder:folder detex:c[0] == NSNull.null ? nil : c[0] encoding:NSUTF8StringEncoding
                     completion:^(TSTextStatisticsResult *r) { result = r; }];
        Check(WaitFor(^BOOL{ return result != nil; }, 20) && result.state == [c[1] integerValue] && result.source.characters == source.characters
              && result.text.characters == NSNotFound && TemporaryFiles() == before, [NSString stringWithFormat:@"detex %@: the Source column stays%@",
              c[0] == NSNull.null ? @"missing" : @"failing", tag]);
    }

    // 3 and 4. The document: Edit > Statistics… and the status bar's button.
    TSDocument *doc = Open(memory);
    BOOL panel = NO;
    for (NSString *name in @[@"statisticsPanel", @"statisticsWords", @"updateStatistics:"])
        if ([nibData rangeOfData:[name dataUsingEncoding:NSUTF8StringEncoding] options:0 range:NSMakeRange(0, nibData.length)].location != NSNotFound) panel = YES;
    Check(doc && !panel, [@"the compiled nib no longer holds the former Statistics panel" stringByAppendingString:tag]);
    doc.fileURL = [folder URLByAppendingPathComponent:@"main.tex"];
    [doc.sourceStatusBar fileDidChangeAtURL:doc.fileURL];
    TSSourceStatusBar *bar = doc.sourceStatusBar;
    Check(bar.statisticsButton && [bar.statisticsButton.title isEqual:L(@"Text Statistics…")] && !bar.statisticsButton.hidden
          && NSMaxX(bar.statisticsButton.frame) < NSWidth(bar.bounds) - 20, [@"the status bar has Text Statistics… before the file size" stringByAppendingString:tag]);
    [bar.statisticsButton performClick:nil];
    TSTextStatisticsPopover *popover = doc.textStatistics;
    TSTextStatisticsViewController *content = popover.contentController;
    popover.detex = ^NSURL *{ return detex; };
    Check(shows == 1 && shownView == bar.statisticsButton && shownEdge == NSRectEdgeMaxY && popover.popover.behavior == NSPopoverBehaviorTransient,
          [@"the button opens the popover above itself, closing when clicking outside" stringByAppendingString:tag]);
    // The first count used the default detex (the settings' TeX folder); count again with the one of this test.
    [popover refresh];
    Check(content.counting, [@"a spinner while counting" stringByAppendingString:tag]);
    Check(WaitFor(^BOOL{ return !content.counting; }, 20) && [content.heading isEqual:L(@"Whole Document")] && content.time.length > 0 && content.warning == nil,
          [NSString stringWithFormat:@"the whole document: %@ %@%@", content.heading, content.time, tag]);
    Check([content.rows[0] hasPrefix:[L(@"Characters") stringByAppendingString:@"|"]] && [content.rows[1] hasPrefix:[L(@"Words") stringByAppendingString:@"|"]]
          && [content.rows[2] hasPrefix:[L(@"Lines") stringByAppendingString:@"|"]], [NSString stringWithFormat:@"rows: %@%@", [content.rows componentsJoinedByString:@" / "], tag]);
    NSArray *parts = [content.rows[0] componentsSeparatedByString:@"|"];
    Check([parts[2] length] > 0 && [parts[1] length] > 0, [@"both columns hold numbers" stringByAppendingString:tag]);
    NSString *about = L(@"Counted by detex without the TeX commands, with the files read by \\input and \\include.");
    Check([content.infoMark.toolTip isEqual:about] && [content.infoMark.accessibilityLabel isEqual:about] && content.infoMark.isAccessibilityElement,
          [@"the ⓘ mark's tool tip, also for VoiceOver" stringByAppendingString:tag]);
    DrawWithPopover(doc, [lang stringByAppendingString:@"-01-whole"], nil);
    DrawWithPopover(doc, [lang stringByAppendingString:@"-05-tooltip"], about);
    NSUInteger counts = popover.countsStarted;
    for (int i = 0; i < 5; i++) { [doc->textView1 insertText:@"あ" replacementRange:NSMakeRange(0, 0)]; Spin(0.05); }
    Check(popover.countsStarted == counts && !popover.statistics.running, [@"typing does not count again" stringByAppendingString:tag]);
    [content.refreshButton performClick:nil];
    Check(popover.countsStarted == counts + 1, [@"the refresh button counts again" stringByAppendingString:tag]);
    WaitFor(^BOOL{ return !content.counting; }, 20);
    // The selection.
    doc->textView1.selectedRange = [doc->textView1.string rangeOfString:spec[@"sentence"]];
    [doc showStatistics:nil];
    Check(WaitFor(^BOOL{ return !content.counting; }, 20) && [content.heading isEqual:L(@"Selection")], [@"Edit > Statistics… counts the selection" stringByAppendingString:tag]);
    DrawWithPopover(doc, [lang stringByAppendingString:@"-02-selection"], nil);
    // Counting, for the picture.
    popover.detex = ^NSURL *{ return slow; };
    [popover refresh];
    Check(content.counting, [@"counting" stringByAppendingString:tag]);
    DrawWithPopover(doc, [lang stringByAppendingString:@"-03-counting"], nil);
    [popover close];
    Check(WaitFor(^BOOL{ return TemporaryFiles() == before; }, 5), [@"closing the popover stops detex" stringByAppendingString:tag]);
    // detex missing.
    popover.detex = ^NSURL *{ return nil; };
    doc->textView1.selectedRange = NSMakeRange(0, 0);
    [doc showStatistics:nil];
    Check(WaitFor(^BOOL{ return !content.counting; }, 20) && [content.warning isEqual:L(@"detex was not found.")] && [[content.rows[0] componentsSeparatedByString:@"|"][1] length] > 0
          && [[content.rows[0] componentsSeparatedByString:@"|"][2] length] == 0, [@"detex missing: a warning in place of the Text column" stringByAppendingString:tag]);
    DrawWithPopover(doc, [lang stringByAppendingString:@"-04-detex-missing"], nil);
    popover.detex = ^NSURL *{ return detex; };

    // The status bar hidden: from the bottom edge of the part being typed in.
    TSSourceStatusBar.shown = NO;
    Check(bar.statisticsButton == nil, [@"no button while the bar is hidden" stringByAppendingString:tag]);
    [doc showStatistics:nil];
    Check(shownView == doc->scrollView && shownRect.size.height == 1 && fabs(shownRect.origin.y - (doc->scrollView.isFlipped ? NSMaxY(doc->scrollView.bounds) - 1 : 0)) < 0.5
          && shownEdge == NSRectEdgeMaxY, [NSString stringWithFormat:@"with the bar hidden, the popover points at the bottom of the source (%@)%@", NSStringFromRect(shownRect), tag]);
    NSSize size = NSMakeSize(NSWidth(doc->scrollView.frame), 100);
    [doc->scrollView setFrameSize:size]; [doc->scrollView2 setFrameSize:size];
    [doc->splitView addSubview:doc->scrollView2]; [doc->splitView adjustSubviews];
    doc->textView = doc->textView2;
    [doc showStatistics:nil];
    Check(shownView == doc->scrollView2, [@"in a split source, at the bottom of the part being typed in" stringByAppendingString:tag]);
    // The window that shows both.
    [doc->splitView removeFromSuperview]; [doc->leftView addSubview:doc->splitView]; doc->splitView.frame = doc->leftView.bounds;
    [doc.sourceStatusBar placeBelowView:doc->splitView];
    [doc showStatistics:nil];
    Check(shownView.window == doc->fullSplitWindow, [@"in the window that shows both, with the bar hidden" stringByAppendingString:tag]);
    TSSourceStatusBar.shown = YES;
    [doc showStatistics:nil];
    Check(shownView == bar.statisticsButton && shownView.window == doc->fullSplitWindow, [@"in the window that shows both, from the button" stringByAppendingString:tag]);
    [popover close];
    Check(WaitFor(^BOOL{ return TemporaryFiles() == before; }, 10), [@"no temporary file is left" stringByAppendingString:tag]);

    if (failures) return 1;
    printf("PASS: %d checks%s\n", checks, tag.UTF8String);
} return 0; }
'''

with tempfile.TemporaryDirectory(prefix='texshop-text-statistics-') as tmp:
    tmp = Path(tmp)
    folder = tmp / 'doc'; folder.mkdir()
    disk = '\\documentclass{article}\n\\begin{document}\nOld text on disk.\n\\end{document}\n'
    (folder / 'main.tex').write_text(disk, encoding='utf-8')
    (folder / 'chap.tex').write_text('Zebra crossings は横断歩道です。\n', encoding='utf-8')
    sentence = '日本語の文章です。今日はいい天気ですね。'
    memory = ('\\documentclass{article}\n\\begin{document}\n\\section{はじめに}\n' + sentence + '\n'
              'Some $x^2$ English words, and \\textbf{bold}.\n\\input{chap}\n\\end{document}\n')
    probe_input = tmp / 'memory.tex'; probe_input.write_text(memory, encoding='utf-8')
    oracle = subprocess.run([DETEX, str(probe_input)], cwd=folder, capture_output=True, check=True).stdout.decode('utf-8')
    if 'Zebra' not in oracle:
        fail('detex follows \\input in the document folder')
    # wc, as the former Statistics window used it.
    ja = sentence + '\n'
    wc_words = int(subprocess.run(['wc', '-w'], input=ja.encode(), capture_output=True, env=dict(os.environ, LANG='ja_JP.UTF-8', LC_ALL='ja_JP.UTF-8')).stdout.split()[0])
    wc_bytes = int(subprocess.run(['wc', '-m'], input=ja.encode(), capture_output=True, env=dict(os.environ, LANG='C', LC_ALL='C')).stdout.split()[0])
    print(f'WC: the Japanese sentence: wc -w {wc_words} (ja_JP), wc -m {wc_bytes} (C locale) for {len(sentence)} characters')
    if not (wc_words <= 2 and wc_bytes == len(ja.encode())):
        fail('wc counts the Japanese sentences as one chunk of words between blanks, and bytes in the C locale')
    bin_ = tmp / 'bin'; bin_.mkdir()
    pid = tmp / 'pid'
    (bin_ / 'slow').write_text(f'#!/bin/sh\necho $$ > {pid}\nsleep 30\ncat "$1"\n'); (bin_ / 'slow').chmod(0o755)
    (bin_ / 'failing').write_text('#!/bin/sh\nexit 3\n'); (bin_ / 'failing').chmod(0o755)
    # A detex that leaves a process holding its output open: stopped while it runs, and ending by itself.
    (bin_ / 'holding').write_text(f'#!/bin/sh\necho $$ > {pid}\n( exec sleep 8 ) &\nsleep 30\ncat "$1"\n'); (bin_ / 'holding').chmod(0o755)
    (bin_ / 'leaving').write_text('#!/bin/sh\n( exec sleep 8 ) &\ncat "$1"\n'); (bin_ / 'leaving').chmod(0o755)
    for name in ('TSStatusBarCounting.m', 'TSSourceStatusBar.m', 'TSTextStatistics.m', 'TSTextStatisticsPopover.m', 'TSDocumentWindowGlass.m'):
        (tmp / name).write_text(text[name], encoding='utf-8', errors='surrogateescape')
    program = (PROGRAM.replace('@@SHOW@@', fragments['show']).replace('@@FROM@@', fragments['from'])
               .replace('@@RECT@@', fragments['rect']))
    if not args.mutation:
        verify_embedded(program, [(k, document, v) for k, v in originals.items()])
    (tmp / 'probe.m').write_text(program, encoding='utf-8')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-framework', 'Quartz', '-I', str(tmp), *include_args(root), '-I', str(root / 'Tests'),
                    str(tmp / 'probe.m'), *(str(tmp / n) for n in ('TSStatusBarCounting.m', 'TSSourceStatusBar.m', 'TSTextStatistics.m',
                    'TSTextStatisticsPopover.m', 'TSDocumentWindowGlass.m')), '-o', str(tmp / 'probe')], check=True)
    if args.images:
        args.images.mkdir(parents=True, exist_ok=True)
    for lang in ('Base', 'ja'):
        folder_name = 'en' if lang == 'Base' else lang
        (tmp / f'{folder_name}.lproj').mkdir(exist_ok=True)
        shutil.copy2(root / f'Resources/Interfaces/{folder_name}.lproj/Localizable.strings', tmp / f'{folder_name}.lproj/Localizable.strings')
        spec = {'nib': str(root / f'Resources/Interfaces/{lang}.lproj/TSDocument.nib/keyedobjects.nib'), 'lang': lang,
                'images': str(args.images.resolve()) if args.images else '', 'detex': DETEX, 'slow': str(bin_ / 'slow'),
                'failing': str(bin_ / 'failing'), 'holding': str(bin_ / 'holding'), 'leaving': str(bin_ / 'leaving'), 'folder': str(folder), 'memory': memory, 'oracle': oracle, 'disk': disk,
                'sentence': sentence, 'pid': str(pid), 'wcWords': wc_words, 'wcBytes': wc_bytes}
        (tmp / 'spec.json').write_text(json.dumps(spec, ensure_ascii=False))
        result = subprocess.run([str(tmp / 'probe'), str(tmp / 'spec.json'), '-AppleLanguages', f'({folder_name})'], capture_output=True, text=True, timeout=600)
        print(result.stdout.strip())
        if result.returncode:
            fail(f'Text Statistics ({lang})'); print(result.stderr[-2000:])

if args.mutation:
    if not failures:
        sys.exit(f'FAIL: mutation {args.mutation} was not detected')
    print(f'PASS: detected mutation {args.mutation}')
elif failures:
    sys.exit(f'FAIL: {len(failures)}')
else:
    print('PASS: Text Statistics')
