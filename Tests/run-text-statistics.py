#!/usr/bin/env python3
"""Text Statistics: the popover opened from the status bar or Edit > Statistics….

Offscreen, with in-memory defaults, never ordering a window or a popover on screen. AppKit
places the popover for real: the document windows say they are visible on a screen that
is faked far off the real screens (NSScreen's frame), and nothing is ordered in:

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
   popover points at the button and AppKit places it above the button, over the source;
   with the status bar hidden, above the bottom edge of the part of the source being typed
   in; also in the window that shows both. The window is in the middle of the screen
   (room above and below), near its top and near its bottom. Both anchors are flipped
   views, where NSPopover's NSRectEdgeMaxY is the bottom; an unflipped anchor opens above
   as well. The document nibs no longer hold the former Statistics panel.
5. The menus keep Edit > Statistics… with its shortcut identifier in 12 languages; the old
   statistics code and detexwrap are gone.
6. The character count options (as CotEditor's Advanced Character Count): line endings and
   whitespace left out, runs of whitespace as one (CR LF one line ending), the Unicode
   normalizations, and the units (grapheme clusters, Unicode scalars, UTF-16, bytes of an
   encoding as TeXShop writes the text, a character it cannot write); the options kept for the
   application but not the encoding; a count again with other options without detex.
7. The popover's options: the button shows them under the table and is remembered; a change
   counts again at once without running detex and is kept; the first row is named after the
   unit; the encoding row only for bytes, with TeXShop's encodings and the document's encoding
   each time the popover opens; "Treat consecutive whitespace as one" off when both kinds are
   left out; a byte count that fails shows a dash with a tool tip; the button is tinted while
   the options are hidden and not those of the status bar.

--images DIR draws the source window of the Base and Japanese nibs in Light and Dark Mode
with the popover's content (production views) in a drawn popover frame where AppKit placed
the popover (the picture grows when the popover is outside the window): whole document,
selection, counting, detex missing, the status bar hidden, the ⓘ tool tip (drawn as a
box, because tool tips cannot be drawn offscreen), the options shown, and the options
hidden with the tinted button. For each picture the popover is shown again
in its appearance (its secondary labels are drawn for the appearance it was shown in), and the
pictures are checked to hold every secondary label (time, Source column, warning, Counting…).
"""
import argparse, json, os, shutil, subprocess, sys, tempfile
from pathlib import Path
from source_tree import include_args, source_file
from production_fragments import method, verify_embedded

DETEX = next((p for p in ('/Applications/TeXLive/2026/bin/universal-darwin/detex', '/Library/TeX/texbin/detex') if Path(p).exists()), None)
MUTATIONS = {
    # A second count leaves the first detex running.
    'previous-not-stopped': ('TSTextStatistics.m', '    [self stop];\n    options = [options copy];\n    BOOL selection = NO;\n', '    options = [options copy];\n    BOOL selection = NO;\n'),
    # Stopping waits for the end of detex's output, which a process detex left may hold open.
    'waits-for-pipe-end': ('TSTextStatistics.m', '                    if (!dispatch_source_testcancel(reader)) {\n', '                    while (!dispatch_source_testcancel(reader)) usleep(10000);\n                    if (!dispatch_source_testcancel(reader)) {\n'),
    # The temporary file stays.
    'file-kept': ('TSTextStatistics.m', '        TSRemoveFile(file);\n        if (atomic_load(&run->cancelled))\n', '        if (atomic_load(&run->cancelled))\n'),
    # Typing counts again while the popover is open.
    'counts-while-typing': ('TSTextStatisticsPopover.m', '        _popover.delegate = self;\n',
                            '        _popover.delegate = self;\n        [NSNotificationCenter.defaultCenter addObserverForName:NSTextDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *n) { [weakSelf refresh]; }];\n'),
    # With the status bar hidden, nothing opens.
    'no-anchor-when-hidden': ('TSDocument.m', '    [self showStatisticsRelativeToRect:bottom ofView:scroll];\n', ''),
    # The edge as before: NSRectEdgeMaxY is the bottom of the flipped button and scroll view.
    'edge-always-maxy': ('TSDocument.m', 'preferredEdge:view.isFlipped ? NSRectEdgeMinY : NSRectEdgeMaxY];', 'preferredEdge:NSRectEdgeMaxY];'),
    # The other constant: right for the flipped anchors only.
    'edge-always-miny': ('TSDocument.m', 'preferredEdge:view.isFlipped ? NSRectEdgeMinY : NSRectEdgeMaxY];', 'preferredEdge:NSRectEdgeMinY];'),
    # An option counts all again, running detex.
    'option-runs-detex': ('TSTextStatisticsPopover.m', '_contentController.optionsChanged = ^{ [weakSelf recount]; };', '_contentController.optionsChanged = ^{ [weakSelf refresh]; };'),
    # The encoding is kept from the last time instead of the document's.
    'encoding-not-documents': ('TSTextStatisticsPopover.m', '        options.encoding = encoding;\n        self.contentController.options = options;\n',
                               '        options.encoding = self.contentController.options.encoding;\n        self.contentController.options = options;\n'),
    # A run of white space keeps its first character instead of becoming one space, as CotEditor counts it.
    'run-keeps-first': ('TSTextStatistics.m', '[result appendString:inRun == 1 ? [string substringWithRange:first] : @" "];\n            inRun = 0;',
                        '[result appendString:[string substringWithRange:first]];\n            inRun = 0;'),
    # Normalizing goes on to the end after the count was stopped.
    'normalize-ignores-stop': ('TSTextStatistics.m', '        if (cancel && cancel())\n            return string;\n        NSUInteger end = MIN(start + size, length);', '        NSUInteger end = MIN(start + size, length);'),
    # Each popover keeps the shown or hidden options of its own last use.
    'shows-per-document': ('TSTextStatisticsPopover.m', '    BOOL shows = [NSUserDefaults.standardUserDefaults boolForKey:TSShowsOptionsKey];\n    self.optionsButton.state',
                           '    BOOL shows = self.isViewLoaded && self.optionsButton ? self.optionsButton.state == NSControlStateValueOn : [NSUserDefaults.standardUserDefaults boolForKey:TSShowsOptionsKey];\n    self.optionsButton.state'),
    # The pictures (--images) take the content as shown once: the dark pictures lose their secondary labels.
    'picture-shown-once': ('PROGRAM', '        real.delegate = nil;\n        [real close];\n        real.contentViewController = nil; real.contentViewController = content;\n        real.appearance = appearance;\n        ((void (*)(id, SEL, NSRect, NSView *, NSRectEdge))originalShow)(real, @selector(showRelativeToRect:ofView:preferredEdge:), shownRect, shownView, shownEdge);\n        real.delegate = (id<NSPopoverDelegate>)doc.textStatistics;\n', ''),
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
names = ('TSStatusBarCounting.m', 'TSSourceStatusBar.m', 'TSTextStatistics.m', 'TSTextStatisticsPopover.m', 'TSDocument.m', 'TSDocumentWindowGlass.m', 'NSString-Extras.m')
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
    if name == 'PROGRAM':
        pass
    elif name == 'TSDocument.m':
        key, = [k for k, v in fragments.items() if old in v]
        assert fragments[key].count(old) == 1; fragments[key] = fragments[key].replace(old, new)
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

// What the popover points at is recorded, then AppKit shows it (never ordered in, see below) and where it placed the
// content on the screen is recorded.
static IMP originalShow;
static NSView *shownView; static NSRect shownRect, shownContent; static NSRectEdge shownEdge; static NSUInteger shows;
static void RecordShow(NSPopover *p, SEL s, NSRect rect, NSView *view, NSRectEdge edge) {
    shownView = view; shownRect = rect; shownEdge = edge; shows++;
    ((void (*)(id, SEL, NSRect, NSView *, NSRectEdge))originalShow)(p, s, rect, view, edge);
    NSView *content = p.contentViewController.view;
    shownContent = content.window ? [content.window convertRectToScreen:[content convertRect:content.bounds toView:nil]] : NSZeroRect;
}

// AppKit places a popover on the screen of the window: every screen says it is this one, far off the real screens.
// The document windows say they are visible on it and keep the frame they are given; nothing is ordered in.
static const NSRect Screen = {{-40000, -40000}, {1800, 2000}};
static NSScreen *theScreen;
static NSRect ScreenFrame(id screen, SEL s) { return Screen; }
static NSArray *Screens(id c, SEL s) { return theScreen ? @[theScreen] : @[]; }
static BOOL WindowVisible(id window, SEL s) { return YES; }
static NSScreen *WindowScreen(id window, SEL s) { return theScreen; }
static NSRect WindowConstrain(id window, SEL s, NSRect rect, NSScreen *screen) { return rect; }
static NSRect OnScreen(NSView *view, NSRect rect) { return [view.window convertRectToScreen:[view convertRect:rect toView:nil]]; }
// The content is above the anchor: the arrow points down at it.
static BOOL Above(NSRect content, NSRect anchor) { return NSHeight(content) > 0 && NSMinY(content) >= NSMaxY(anchor) - 0.5; }
static NSString *Where(NSRect content, NSRect anchor) {
    return [NSString stringWithFormat:@"content %@, anchor %@", NSStringFromRect(content), NSStringFromRect(anchor)];
}

// TeXShop's encodings, as TSDocument gives them to the popover: three of them, and the text as it is written.
#import "NSString-Extras.h"
#define SUD [NSUserDefaults standardUserDefaults]
static NSString *AutomaticUTF8MACtoUTF8ConversionKey = @"AutomaticUTF8MACtoUTF8Conversion";
static NSUInteger savingCalls;
@interface TSEncodingSupport : NSObject
+ (instancetype)sharedInstance;
- (NSString *)textForSaving:(NSString *)text encoding:(NSStringEncoding)encoding;
- (void)addEncodingsToMenu:(NSMenu *)menu withTarget:(id)target action:(SEL)action;
@end
@implementation TSEncodingSupport
+ (instancetype)sharedInstance { static id shared; if (!shared) shared = [self new]; return shared; }
- (NSString *)textForSaving:(NSString *)text encoding:(NSStringEncoding)encoding { savingCalls++; return text; }
- (void)addEncodingsToMenu:(NSMenu *)menu withTarget:(id)target action:(SEL)action {
    for (NSNumber *e in @[@(NSUTF8StringEncoding), @(NSShiftJISStringEncoding), @(NSJapaneseEUCStringEncoding)]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[NSString localizedNameOfStringEncoding:e.unsignedIntegerValue] action:action keyEquivalent:@""];
        item.tag = e.integerValue;
        [menu addItem:item];
    }
}
@end
static TSCharacterCountOptions *Plain(void) { return [TSCharacterCountOptions new]; }
static NSUInteger Count(NSString *string, void (^set)(TSCharacterCountOptions *o)) {
    TSCharacterCountOptions *o = Plain();
    if (set) set(o);
    return TSCharacterCountWithOptions(string, o, nil);
}
// The number in a cell of the table, without the grouping.
static NSUInteger Cell(NSString *row, NSUInteger column) {
    NSString *cell = [row componentsSeparatedByString:@"|"][column];
    NSString *digits = [[cell componentsSeparatedByCharactersInSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet] componentsJoinedByString:@""];
    return digits.length ? (NSUInteger)digits.longLongValue : NSNotFound;
}

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
    // In the middle of the screen: room above and below.
    [doc->textWindow setFrame:NSMakeRect(NSMinX(Screen) + 400, NSMinY(Screen) + 680, 760, 640) display:NO];
    WaitFor(^BOOL{ return !doc.sourceStatusBar.counting; }, 10);
    return doc;
}

// Pictures: the window, with the popover's content in a drawn popover frame above the anchor.
static NSString *images;
// The visible labels in the secondary label color, and whether a label's place in a snapshot holds any text: the
// lightest and darkest pixels there differ.
static NSArray<NSTextField *> *SecondaryLabels(NSView *root) {
    NSMutableArray *found = [NSMutableArray array], *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        NSView *view = queue.firstObject; [queue removeObjectAtIndex:0];
        [queue addObjectsFromArray:view.subviews];
        if ([view isKindOfClass:NSTextField.class] && !view.hiddenOrHasHiddenAncestor && NSWidth(view.frame) > 0
            && [(NSTextField *)view stringValue].length > 0 && [[(NSTextField *)view textColor] isEqual:NSColor.secondaryLabelColor])
            [found addObject:view];
    }
    return found;
}
static BOOL Inked(NSBitmapImageRep *rep, NSView *root, NSView *view) {
    NSRect r = [view convertRect:view.bounds toView:root];
    CGFloat scale = rep.pixelsWide / NSWidth(root.bounds);
    NSInteger x0 = MAX(0, (NSInteger)floor(NSMinX(r) * scale)), x1 = MIN(rep.pixelsWide, (NSInteger)ceil(NSMaxX(r) * scale));
    NSInteger y0 = MAX(0, (NSInteger)floor((NSHeight(root.bounds) - NSMaxY(r)) * scale)), y1 = MIN(rep.pixelsHigh, (NSInteger)ceil((NSHeight(root.bounds) - NSMinY(r)) * scale));
    CGFloat lightest = 0, darkest = 1;
    for (NSInteger y = y0; y < y1; y++)
        for (NSInteger x = x0; x < x1; x++) {
            NSColor *c = [[rep colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.genericGrayColorSpace];
            lightest = MAX(lightest, c.whiteComponent); darkest = MIN(darkest, c.whiteComponent);
        }
    return lightest - darkest > 0.15;
}
static NSBitmapImageRep *Snapshot(NSView *view) {
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    return rep;
}
// The picture takes the content out of the popover. The popover is then closed and given its content again, also
// without pictures, so that the checks see the same states either way (left out, the next show placed no content).
// The window goes back to the system's appearance.
static void DrawPictures(TSDocument *doc, NSString *name, NSString *tip);
static void DrawWithPopover(TSDocument *doc, NSString *name, NSString *tip) {
    if (images) DrawPictures(doc, name, tip);
    TSTextStatisticsPopover *popover = doc.textStatistics;
    [popover close];
    NSViewController *content = popover.popover.contentViewController;
    popover.popover.appearance = nil;
    popover.popover.contentViewController = nil;
    popover.popover.contentViewController = content;
}
static void DrawPictures(TSDocument *doc, NSString *name, NSString *tip) {
    NSViewController *content = doc.textStatistics.contentController;
    NSWindow *window = shownView.window;
    for (NSString *look in @[@"light", @"dark"]) {
        NSAppearance *appearance = [NSAppearance appearanceNamed:[look isEqual:@"dark"] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
        window.appearance = appearance;
        // The popover draws its secondary labels for the appearance it was shown in (vibrancy): show it again from the
        // same anchor in this one (not recorded), then take its content out.
        NSPopover *real = doc.textStatistics.popover;
        real.delegate = nil;
        [real close];
        real.contentViewController = nil; real.contentViewController = content;
        real.appearance = appearance;
        ((void (*)(id, SEL, NSRect, NSView *, NSRectEdge))originalShow)(real, @selector(showRelativeToRect:ofView:preferredEdge:), shownRect, shownView, shownEdge);
        real.delegate = (id<NSPopoverDelegate>)doc.textStatistics;
        Spin(0.1);
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
        // Every secondary label of the content (time, Source column, warning, Counting…) is drawn in the picture.
        NSMutableArray<NSString *> *blank = [NSMutableArray array];
        NSUInteger labels = 0;
        for (NSTextField *label in SecondaryLabels(content.view)) {
            labels++;
            if (!Inked(pop, holder.contentView.superview, label)) [blank addObject:label.stringValue];
        }
        Check(labels > 0 && blank.count == 0, [NSString stringWithFormat:@"picture %@-%@: the %lu secondary labels are drawn (blank: %@)", name, look,
              (unsigned long)labels, [blank componentsJoinedByString:@", "]]);
        NSView *frame = window.contentView.superview;
        [window layoutIfNeeded]; [frame layoutSubtreeIfNeeded];
        NSBitmapImageRep *win = Snapshot(frame);
        // The popover's content where AppKit placed it, in the window's coordinates; the picture takes it in.
        NSRect anchor = [shownView convertRect:shownRect toView:nil];
        NSRect placed = [window convertRectFromScreen:shownContent];
        NSSize size = content.view.bounds.size;
        BOOL above = NSMinY(placed) >= NSMaxY(anchor) - 0.5;
        NSRect box = NSMakeRect(NSMinX(placed), above ? NSMinY(placed) : NSMaxY(placed) - size.height, size.width, size.height);
        CGFloat arrow = 10, tipX = MIN(MAX(NSMidX(anchor), NSMinX(box) + 2 * arrow), NSMaxX(box) - 2 * arrow);
        NSRect canvas = NSUnionRect(frame.bounds, NSInsetRect(NSUnionRect(box, anchor), -24, -24));
        NSImage *out = [[NSImage alloc] initWithSize:canvas.size];
        [out lockFocus];
        NSAffineTransform *shift = [NSAffineTransform transform]; [shift translateXBy:-NSMinX(canvas) yBy:-NSMinY(canvas)]; [shift concat];
        [win drawInRect:frame.bounds];
        [NSAppearance setCurrentAppearance:appearance];
        [NSGraphicsContext saveGraphicsState];
        NSShadow *shadow = [NSShadow new]; shadow.shadowBlurRadius = 14; shadow.shadowOffset = NSMakeSize(0, -3);
        shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.3]; [shadow set];
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:box xRadius:14 yRadius:14];
        CGFloat base = above ? NSMinY(box) : NSMaxY(box), tipY = above ? NSMaxY(anchor) + 1 : NSMinY(anchor) - 1;
        [path moveToPoint:NSMakePoint(tipX - arrow, base)];
        [path lineToPoint:NSMakePoint(tipX, tipY)];
        [path lineToPoint:NSMakePoint(tipX + arrow, base)];
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
            NSRect tr = NSMakeRect(MIN(at.x, NSMaxX(canvas) - ts.width - 20), at.y - ts.height, ts.width + 12, ts.height + 6);
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
    window.appearance = nil;
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    originalShow = method_setImplementation(class_getInstanceMethod(NSPopover.class, @selector(showRelativeToRect:ofView:preferredEdge:)), (IMP)RecordShow);
    for (NSString *name in @[@"TSConsoleWindow", @"TSFullSplitWindow", @"TSHTMLWindow", @"TSLogWindow", @"TSPreviewWindow", @"TSTextEditorWindow"]) Register(name, NSWindow.class);
    theScreen = NSScreen.mainScreen ?: NSScreen.screens.firstObject;
    method_setImplementation(class_getInstanceMethod(NSScreen.class, @selector(frame)), (IMP)ScreenFrame);
    method_setImplementation(class_getInstanceMethod(NSScreen.class, @selector(visibleFrame)), (IMP)ScreenFrame);
    method_setImplementation(class_getClassMethod(NSScreen.class, @selector(screens)), (IMP)Screens);
    for (NSString *name in @[@"TSTextEditorWindow", @"TSFullSplitWindow"]) {
        Class c = NSClassFromString(name);
        class_addMethod(c, @selector(isVisible), (IMP)WindowVisible, "c@:");
        class_addMethod(c, @selector(screen), (IMP)WindowScreen, "@@:");
        class_addMethod(c, @selector(constrainFrameRect:toScreen:), (IMP)WindowConstrain, method_getTypeEncoding(class_getInstanceMethod(NSWindow.class, @selector(constrainFrameRect:toScreen:))));
    }
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
    [statistics countString:memory ranges:@[[NSValue valueWithRange:NSMakeRange(0, 0)]] folder:folder detex:detex encoding:NSUTF8StringEncoding options:Plain()
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
    [statistics countString:japanese ranges:@[] folder:folder detex:detex encoding:NSUTF8StringEncoding options:Plain() completion:^(TSTextStatisticsResult *r) { result = r; }];
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
    [statistics countString:memory ranges:@[[NSValue valueWithRange:sentence]] folder:folder detex:detex encoding:NSUTF8StringEncoding options:Plain()
                 completion:^(TSTextStatisticsResult *r) { result = r; }];
    Check(WaitFor(^BOOL{ return result != nil; }, 20) && result.selection && result.source.characters == TSStatusBarCharacterCount(memory, sentence, nil)
          && result.text.characters != NSNotFound, [NSString stringWithFormat:@"the selection is counted (%lu)%@", result.source.characters, tag]);

    // 2. A second count stops the first detex; stop ends it; missing or failing detex.
    NSString *pidFile = spec[@"pid"];
    __block NSUInteger firstDone = 0;
    [statistics countString:memory ranges:@[] folder:folder detex:slow encoding:NSUTF8StringEncoding options:Plain() completion:^(TSTextStatisticsResult *r) { firstDone++; }];
    NSURL *firstFile = statistics.temporaryFile;
    Check(WaitFor(^BOOL{ return Alive(PidIn(pidFile)); }, 10), [@"the slow detex runs" stringByAppendingString:tag]);
    pid_t first = PidIn(pidFile);
    result = nil;
    [statistics countString:memory ranges:@[] folder:folder detex:detex encoding:NSUTF8StringEncoding options:Plain() completion:^(TSTextStatisticsResult *r) { result = r; }];
    Check(WaitFor(^BOOL{ return !Alive(first); }, 5), [@"a second count stops the detex still running" stringByAppendingString:tag]);
    Check(WaitFor(^BOOL{ return result != nil; }, 20) && result.state == TSTextStatisticsDone && firstDone == 0,
          [@"only the second count shows" stringByAppendingString:tag]);
    Check(![NSFileManager.defaultManager fileExistsAtPath:firstFile.path] && TemporaryFiles() == before, [@"the first count's temporary file is removed" stringByAppendingString:tag]);
    [NSFileManager.defaultManager removeItemAtPath:pidFile error:NULL];
    [statistics countString:memory ranges:@[] folder:folder detex:slow encoding:NSUTF8StringEncoding options:Plain() completion:^(TSTextStatisticsResult *r) { firstDone++; }];
    WaitFor(^BOOL{ return Alive(PidIn(pidFile)); }, 10);
    pid_t stopped = PidIn(pidFile);
    [statistics stop];
    Check(WaitFor(^BOOL{ return !Alive(stopped) && TemporaryFiles() == before; }, 5) && firstDone == 0, [@"stop ends detex and removes the file" stringByAppendingString:tag]);
    Spin(0.2);
    // A process that detex left holds the output open: stopping detex does not wait for it, nor does detex's own end.
    NSURL *holding = [NSURL fileURLWithPath:spec[@"holding"]], *leaving = [NSURL fileURLWithPath:spec[@"leaving"]];
    [NSFileManager.defaultManager removeItemAtPath:pidFile error:NULL];
    [statistics countString:memory ranges:@[] folder:folder detex:holding encoding:NSUTF8StringEncoding options:Plain() completion:^(TSTextStatisticsResult *r) { firstDone++; }];
    NSURL *heldFile = statistics.temporaryFile;
    Check(WaitFor(^BOOL{ return Alive(PidIn(pidFile)); }, 10), [@"the detex that leaves a process runs" stringByAppendingString:tag]);
    Spin(0.3);
    result = nil;
    CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
    [statistics countString:memory ranges:@[] folder:folder detex:nil encoding:NSUTF8StringEncoding options:Plain() completion:^(TSTextStatisticsResult *r) { result = r; }];
    Check(WaitFor(^BOOL{ return result != nil; }, 1.5) && firstDone == 0 && ![NSFileManager.defaultManager fileExistsAtPath:heldFile.path],
          [NSString stringWithFormat:@"a stopped detex whose output another process holds does not hold up the next count or the removal of its file (%.2f s)%@",
           CFAbsoluteTimeGetCurrent() - started, tag]);
    result = nil;
    started = CFAbsoluteTimeGetCurrent();
    [statistics countString:memory ranges:@[] folder:folder detex:leaving encoding:NSUTF8StringEncoding options:Plain() completion:^(TSTextStatisticsResult *r) { result = r; }];
    Check(WaitFor(^BOOL{ return result != nil; }, 3) && result.state == TSTextStatisticsDone && result.text.characters == source.characters,
          [NSString stringWithFormat:@"a detex that ends leaving a process with its output is counted without waiting for that process (%.2f s, %lu)%@",
           CFAbsoluteTimeGetCurrent() - started, result.text.characters, tag]);
    Check(WaitFor(^BOOL{ return TemporaryFiles() == before; }, 2), [@"and its file is removed" stringByAppendingString:tag]);
    for (NSArray *c in @[@[[NSNull null], @(TSTextStatisticsDetexMissing)], @[failing, @(TSTextStatisticsDetexFailed)]]) {
        result = nil;
        [statistics countString:memory ranges:@[] folder:folder detex:c[0] == NSNull.null ? nil : c[0] encoding:NSUTF8StringEncoding options:Plain()
                     completion:^(TSTextStatisticsResult *r) { result = r; }];
        Check(WaitFor(^BOOL{ return result != nil; }, 20) && result.state == [c[1] integerValue] && result.source.characters == source.characters
              && result.text.characters == NSNotFound && TemporaryFiles() == before, [NSString stringWithFormat:@"detex %@: the Source column stays%@",
              c[0] == NSNull.null ? @"missing" : @"failing", tag]);
    }

    // 6. Counting with options.
    NSString *spaced = @"a b\r\nc\u3000\u3000d\n\n\te";
    struct { const char *name; BOOL le, ws, runs; TSCharacterUnit unit; NSUInteger want; } spacing[] = {
        {"as the status bar", NO, NO, NO, TSCharacterUnitGraphemeCluster, 12},
        {"line endings left out", YES, NO, NO, TSCharacterUnitGraphemeCluster, 9},
        {"whitespace left out (U+3000 and tab too)", NO, YES, NO, TSCharacterUnitGraphemeCluster, 8},
        {"both left out", YES, YES, NO, TSCharacterUnitGraphemeCluster, 5},
        {"runs as one, line endings among them", NO, NO, YES, TSCharacterUnitGraphemeCluster, 9},
        {"runs as one without whitespace: the blank lines are one", NO, YES, YES, TSCharacterUnitGraphemeCluster, 7},
        {"runs as one without line endings", YES, NO, YES, TSCharacterUnitGraphemeCluster, 8},
        {"UTF-16: CR LF two units", NO, NO, NO, TSCharacterUnitUTF16, 13},
        {"bytes of UTF-8: U+3000 three bytes", NO, NO, NO, TSCharacterUnitByte, 17},
    };
    for (size_t i = 0; i < sizeof spacing / sizeof spacing[0]; i++) {
        __typeof__(spacing[0]) c = spacing[i];
        NSUInteger got = Count(spaced, ^(TSCharacterCountOptions *o) {
            o.ignoresLineEndings = c.le; o.ignoresWhitespace = c.ws; o.treatsConsecutiveWhitespaceAsOne = c.runs; o.unit = c.unit;
        });
        Check(got == spacing[i].want, [NSString stringWithFormat:@"options: %s: %lu, expected %lu%@", spacing[i].name, got, spacing[i].want, tag]);
    }
    Check(Count(spaced, nil) == TSStatusBarCharacterCount(spaced, NSMakeRange(0, spaced.length), nil), [@"options: the default counts as the status bar" stringByAppendingString:tag]);
    Check(Count(@"a\r\nb", ^(TSCharacterCountOptions *o) { o.treatsConsecutiveWhitespaceAsOne = YES; o.unit = TSCharacterUnitUTF16; }) == 4,
          [@"options: a run of one CR LF keeps both units" stringByAppendingString:tag]);
    Check(Count(@"x\u3000 y", ^(TSCharacterCountOptions *o) { o.treatsConsecutiveWhitespaceAsOne = YES; o.unit = TSCharacterUnitByte; }) == 3
          && Count(@"x\u3000y", ^(TSCharacterCountOptions *o) { o.treatsConsecutiveWhitespaceAsOne = YES; o.unit = TSCharacterUnitByte; }) == 5
          && Count(@"\r\n ", ^(TSCharacterCountOptions *o) { o.treatsConsecutiveWhitespaceAsOne = YES; o.unit = TSCharacterUnitUnicodeScalar; }) == 1,
          [@"options: a run of two or more becomes one space, as CotEditor counts it; one U+3000 stays" stringByAppendingString:tag]);
    // CotEditor 7.1.3 (String+AdvancedCounting.swift): \R, then [\t\p{Zs}], a whole character at a time by its first code point.
    Check(Count(@"A\vB", ^(TSCharacterCountOptions *o) { o.ignoresLineEndings = YES; }) == 2 && Count(@"A\fB", ^(TSCharacterCountOptions *o) { o.ignoresLineEndings = YES; }) == 2
          && Count(@"A\vB", ^(TSCharacterCountOptions *o) { o.ignoresWhitespace = YES; }) == 3
          && Count(@" \u0301", ^(TSCharacterCountOptions *o) { o.ignoresWhitespace = YES; o.unit = TSCharacterUnitByte; }) == 0
          && Count([NSString stringWithFormat:@"a%Cb%Cc", (unichar)0x2028, (unichar)0x85], ^(TSCharacterCountOptions *o) { o.ignoresLineEndings = YES; }) == 3,
          [@"options: VT and FF are line endings, and a space with a combining mark goes as one character, as in CotEditor" stringByAppendingString:tag]);
    NSString *joined = @"e\u0301\U0001F468\u200D\U0001F469\u200D\U0001F467";
    struct { const char *name; TSUnicodeNormalization n; TSCharacterUnit unit; NSUInteger want; } forms[] = {
        {"grapheme clusters", TSUnicodeNormalizationNone, TSCharacterUnitGraphemeCluster, 2},
        {"Unicode scalars", TSUnicodeNormalizationNone, TSCharacterUnitUnicodeScalar, 7},
        {"UTF-16", TSUnicodeNormalizationNone, TSCharacterUnitUTF16, 10},
        {"NFC scalars", TSUnicodeNormalizationNFC, TSCharacterUnitUnicodeScalar, 6},
    };
    for (size_t i = 0; i < sizeof forms / sizeof forms[0]; i++) {
        __typeof__(forms[0]) f = forms[i];
        NSUInteger got = Count(joined, ^(TSCharacterCountOptions *o) { o.normalization = f.n; o.unit = f.unit; });
        Check(got == forms[i].want, [NSString stringWithFormat:@"options: e + U+0301 and a family emoji in %s: %lu, expected %lu%@", forms[i].name, got, forms[i].want, tag]);
    }
    Check(Count(@"\uFF71\u2460\uFB01", nil) == 3 && Count(@"\uFF71\u2460\uFB01", ^(TSCharacterCountOptions *o) { o.normalization = TSUnicodeNormalizationNFKC; }) == 4
          && Count(@"\uFF71\u2460\uFB01", ^(TSCharacterCountOptions *o) { o.normalization = TSUnicodeNormalizationNFKD; }) == 4,
          [@"options: NFKC and NFKD map half-width kana, circled digits and ligatures" stringByAppendingString:tag]);
    Check(Count(@"\u0345\u0301", ^(TSCharacterCountOptions *o) { o.normalization = TSUnicodeNormalizationNFKCCaseFold; o.unit = TSCharacterUnitUnicodeScalar; }) == 1
          && Count(@"\U00016D68", ^(TSCharacterCountOptions *o) { o.normalization = TSUnicodeNormalizationNFKCCaseFold; o.unit = TSCharacterUnitUnicodeScalar; }) == 1,
          [@"options: NFKC Case-Fold is ICU's (U+0345 U+0301 is U+03AF)" stringByAppendingString:tag]);
    Check(Count(@"\u0958\u0344", ^(TSCharacterCountOptions *o) { o.normalization = TSUnicodeNormalizationModifiedNFC; o.unit = TSCharacterUnitUnicodeScalar; })
          == [[@"\u0958\u0344" normalizedStringWithModifiedNFC] length]
          && Count(@"\u0958\u0344", ^(TSCharacterCountOptions *o) { o.normalization = TSUnicodeNormalizationModifiedNFC; o.unit = TSCharacterUnitUnicodeScalar; }) == 2
          && Count(@"\u0958", ^(TSCharacterCountOptions *o) { o.normalization = TSUnicodeNormalizationNFC; o.unit = TSCharacterUnitUnicodeScalar; }) == 2,
          [@"options: Modified NFC as Edit > Unicode Normalization makes it (U+0958 and U+0344 stay)" stringByAppendingString:tag]);
    // Long texts are normalized a piece at a time: the same as all at once, and a stop is seen between pieces.
    NSMutableString *longText = [NSMutableString string];
    for (int i = 0; i < 30000; i++) [longText appendString:@"e\u0301 \uFF71\u304B\u3099\u212B\u0958 Stra\u00DFe "];
    for (NSNumber *form in @[@(TSUnicodeNormalizationNFC), @(TSUnicodeNormalizationNFKCCaseFold), @(TSUnicodeNormalizationModifiedNFC), @(TSUnicodeNormalizationModifiedNFD)]) {
        NSString *piece = @"e\u0301 \uFF71\u304B\u3099\u212B\u0958 Stra\u00DFe ";
        NSUInteger one = Count(piece, ^(TSCharacterCountOptions *o) { o.normalization = form.integerValue; o.unit = TSCharacterUnitUTF16; });
        NSUInteger all = Count(longText, ^(TSCharacterCountOptions *o) { o.normalization = form.integerValue; o.unit = TSCharacterUnitUTF16; });
        Check(all == one * 30000, [NSString stringWithFormat:@"options: a long text normalized in pieces (form %@): %lu, expected %lu%@", form, all, one * 30000, tag]);
    }
    NSMutableString *huge = [NSMutableString string];
    for (int i = 0; i < 2600000; i++) [huge appendString:@"\u1E9E\u0130\uFB03"];
    TSCharacterCountOptions *folding = Plain(); folding.normalization = TSUnicodeNormalizationModifiedNFD;  // about half a second to normalize
    __block BOOL stopNow = NO;
    __block CFAbsoluteTime stoppedAt = 0, endedAt = 0;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        TSCharacterCountWithOptions(huge, folding, ^BOOL{ return stopNow; });
        endedAt = CFAbsoluteTimeGetCurrent();
    });
    Spin(0.02);
    stoppedAt = CFAbsoluteTimeGetCurrent(); stopNow = YES;
    Check(WaitFor(^BOOL{ return endedAt > 0; }, 5) && endedAt - stoppedAt < 0.1,
          [NSString stringWithFormat:@"options: a stopped Modified NFD of 7,800,000 characters ends at once (%.3f s)%@", endedAt - stoppedAt, tag]);
    Check(Count(@"\u00DF\u00DF\u00AD", nil) == 3 && Count(@"\u00DF\u00DF\u00AD", ^(TSCharacterCountOptions *o) { o.normalization = TSUnicodeNormalizationNFKC; }) == 3
          && Count(@"\u00DF\u00DF\u00AD", ^(TSCharacterCountOptions *o) { o.normalization = TSUnicodeNormalizationNFKCCaseFold; }) == 4,
          [@"options: NFKC Case-Fold folds ß to ss and drops the soft hyphen" stringByAppendingString:tag]);
    Check(Count(@"\u304C\u212B", ^(TSCharacterCountOptions *o) { o.normalization = TSUnicodeNormalizationNFD; o.unit = TSCharacterUnitUTF16; }) == 4
          && Count(@"\u304C\u212B", ^(TSCharacterCountOptions *o) { o.normalization = TSUnicodeNormalizationModifiedNFD; o.unit = TSCharacterUnitUTF16; }) == 3
          && Count(@"\u304B\u3099\u212B", ^(TSCharacterCountOptions *o) { o.normalization = TSUnicodeNormalizationModifiedNFC; o.unit = TSCharacterUnitUTF16; }) == 2,
          [@"options: modified NFD and NFC leave U+2000–U+2FFF as they are" stringByAppendingString:tag]);
    Check(Count(@"\u65E5\u672C\\", ^(TSCharacterCountOptions *o) { o.unit = TSCharacterUnitByte; o.encoding = NSShiftJISStringEncoding; }) == 5
          && Count(@"ab", ^(TSCharacterCountOptions *o) { o.unit = TSCharacterUnitByte; o.encoding = NSUnicodeStringEncoding; }) == 4,
          [@"options: bytes of Shift JIS, and of UTF-16 without a byte order mark" stringByAppendingString:tag]);
    Check(Count(@"\U0001F600", ^(TSCharacterCountOptions *o) { o.unit = TSCharacterUnitByte; o.encoding = NSShiftJISStringEncoding; }) == TSCharacterCountUnencodable
          && Count(@"\U0001F600", ^(TSCharacterCountOptions *o) { o.unit = TSCharacterUnitUnicodeScalar; o.encoding = NSShiftJISStringEncoding; }) == 1,
          [@"options: a character Shift JIS cannot write fails the byte count only" stringByAppendingString:tag]);
    Check(Count(@"ab", ^(TSCharacterCountOptions *o) {
              o.unit = TSCharacterUnitByte; o.textForEncoding = ^NSString *(NSString *t, NSStringEncoding e) { return [t stringByAppendingString:@"xyz"]; }; }) == 5,
          [@"options: bytes are those of the text as TeXShop writes it" stringByAppendingString:tag]);
    TSCharacterCountOptions *saved = Plain();
    Check(saved.isDefault && [TSCharacterCountOptions savedOptions].isDefault, [@"options: the default ones" stringByAppendingString:tag]);
    saved.ignoresLineEndings = YES; saved.ignoresWhitespace = YES; saved.treatsConsecutiveWhitespaceAsOne = YES;
    saved.normalization = TSUnicodeNormalizationNFKCCaseFold; saved.unit = TSCharacterUnitByte; saved.encoding = NSShiftJISStringEncoding;
    [saved save];
    TSCharacterCountOptions *loaded = [TSCharacterCountOptions savedOptions];
    Check(loaded.ignoresLineEndings && loaded.ignoresWhitespace && loaded.treatsConsecutiveWhitespaceAsOne && loaded.normalization == TSUnicodeNormalizationNFKCCaseFold
          && loaded.unit == TSCharacterUnitByte && loaded.encoding == NSUTF8StringEncoding && !loaded.isDefault,
          [@"options: kept in the settings, all but the encoding" stringByAppendingString:tag]);
    [Plain() save];
    // Counting again with other options: detex does not run, the rest of the result stays.
    result = nil;
    [statistics countString:memory ranges:@[] folder:folder detex:detex encoding:NSUTF8StringEncoding options:Plain() completion:^(TSTextStatisticsResult *r) { result = r; }];
    WaitFor(^BOOL{ return result != nil; }, 20);
    TSTextStatisticsResult *counted = result;
    Check(counted.sourceCharacters == counted.source.characters && counted.textCharacters == counted.text.characters && [counted.textString isEqual:spec[@"oracle"]],
          [@"options: the default count is the status bar's, and the result keeps detex's output" stringByAppendingString:tag]);
    TSCharacterCountOptions *noSpace = Plain(); noSpace.ignoresWhitespace = YES; noSpace.ignoresLineEndings = YES;
    result = nil;
    [statistics recountCharactersOfResult:counted options:noSpace completion:^(TSTextStatisticsResult *r) { result = r; }];
    Check(!statistics.temporaryFile, [@"options: counting again writes no file for detex" stringByAppendingString:tag]);
    Check(WaitFor(^BOOL{ return result != nil; }, 10) && result.sourceCharacters == TSCharacterCountWithOptions(memory, noSpace, nil)
          && result.textCharacters == TSCharacterCountWithOptions(spec[@"oracle"], noSpace, nil) && result.textCharacters < counted.textCharacters
          && result.text.words == counted.text.words && [result.date isEqual:counted.date] && result.state == TSTextStatisticsDone,
          [NSString stringWithFormat:@"options: counted again without whitespace: %lu/%lu, before %lu/%lu%@", result.sourceCharacters, result.textCharacters,
           counted.sourceCharacters, counted.textCharacters, tag]);
    result = nil;
    [statistics countString:memory ranges:@[] folder:folder detex:detex encoding:NSUTF8StringEncoding options:noSpace completion:^(TSTextStatisticsResult *r) { result = r; }];
    Check(WaitFor(^BOOL{ return result != nil; }, 20) && result.textCharacters == TSCharacterCountWithOptions(spec[@"oracle"], noSpace, nil),
          [@"options: a count with options counts detex's output with them" stringByAppendingString:tag]);

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
    popover.popover.animates = NO;
    NSRect buttonOnScreen = OnScreen(bar.statisticsButton, bar.statisticsButton.bounds);
    Check(shows == 1 && shownView == bar.statisticsButton && popover.popover.shown && popover.popover.behavior == NSPopoverBehaviorTransient,
          [@"the button opens the popover, closing when clicking outside" stringByAppendingString:tag]);
    Check(bar.statisticsButton.isFlipped && doc->scrollView.isFlipped,
          [@"the button and the source's scroll view are flipped: NSRectEdgeMaxY is their bottom" stringByAppendingString:tag]);
    Check(NSMinY(buttonOnScreen) - NSMinY(Screen) > 400 && NSMaxY(Screen) - NSMaxY(doc->textWindow.frame) > 400,
          [NSString stringWithFormat:@"the window has room above and below on the screen (%@)%@", NSStringFromRect(doc->textWindow.frame), tag]);
    Check(Above(shownContent, buttonOnScreen) && NSMaxY(shownContent) < NSMaxY(doc->textWindow.frame),
          [NSString stringWithFormat:@"AppKit places the popover above the button, over the source (%@)%@", Where(shownContent, buttonOnScreen), tag]);
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
    NSTextField *warningLabel = [content valueForKey:@"warningLabel"];
    [content.view layoutSubtreeIfNeeded];
    NSRect warningFrame = [warningLabel convertRect:warningLabel.bounds toView:content.view];
    Check(NSMaxX(warningFrame) <= NSWidth(content.view.bounds) - 12 && warningLabel.cell.wraps,
          [NSString stringWithFormat:@"the warning wraps and keeps the margin of the popover (%@ in %@)%@", NSStringFromRect(warningFrame), NSStringFromRect(content.view.bounds), tag]);
    DrawWithPopover(doc, [lang stringByAppendingString:@"-04-detex-missing"], nil);
    popover.detex = ^NSURL *{ return detex; };

    // 7. The options in the popover.
    [popover close];
    [doc showStatistics:nil];
    WaitFor(^BOOL{ return !content.counting; }, 20);
    Check(content.optionsButton.state == NSControlStateValueOff && content.optionsView.hiddenOrHasHiddenAncestor && content.optionsButton.contentTintColor == nil
          && [content.optionsButton.toolTip isEqual:L(@"Character Count Options")] && [content.optionsButton.accessibilityLabel isEqual:L(@"Character Count Options")],
          [@"popover options: hidden at first, behind a plain button with its name" stringByAppendingString:tag]);
    // Bytes as TeXShop saves the text: composed when UTF-8-MAC is converted to UTF-8 (TSDocument's block).
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"AutomaticUTF8MACtoUTF8Conversion"];
    NSString *savedText = popover.textForEncoding ? popover.textForEncoding(@"e\u0301", NSUTF8StringEncoding) : nil;
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"AutomaticUTF8MACtoUTF8Conversion"];
    NSString *plainText = popover.textForEncoding ? popover.textForEncoding(@"e\u0301", NSUTF8StringEncoding) : nil;
    Check([savedText isEqual:@"\u00E9"] && [plainText isEqual:@"e\u0301"],
          [NSString stringWithFormat:@"popover options: bytes of the text as it is saved, composed when UTF-8-MAC is converted (%lu, %lu)%@", savedText.length, plainText.length, tag]);
    [content.optionsButton performClick:nil];
    Check(!content.optionsView.hiddenOrHasHiddenAncestor && [NSUserDefaults.standardUserDefaults boolForKey:@"StatisticsShowsCharacterCountOptions"]
          && content.encodingPopUp.hiddenOrHasHiddenAncestor && content.consecutiveWhitespaceBox.enabled,
          [@"popover options: the button shows them, remembered; no encoding for characters" stringByAppendingString:tag]);
    counts = popover.countsStarted;
    NSString *beforeRow = content.rows[0];
    NSString *sourceText = [doc->textView1.string copy];
    [content.ignoreWhitespaceBox performClick:nil];
    [content.ignoreLineEndingsBox performClick:nil];
    TSCharacterCountOptions *shown = Plain(); shown.ignoresWhitespace = YES; shown.ignoresLineEndings = YES;
    __block TSTextStatisticsResult *expected = nil;
    TSTextStatistics *other = [TSTextStatistics new];
    [other countString:sourceText ranges:@[] folder:folder detex:detex encoding:NSUTF8StringEncoding options:shown completion:^(TSTextStatisticsResult *r) { expected = r; }];
    WaitFor(^BOOL{ return expected != nil; }, 20);
    Check(WaitFor(^BOOL{ return Cell(content.rows[0], 1) == TSCharacterCountWithOptions(sourceText, shown, nil); }, 10)
          && Cell(content.rows[0], 2) == expected.textCharacters && popover.countsStarted == counts && !content.counting,
          [NSString stringWithFormat:@"popover options: a change counts again at once, without detex: %@ → %@ (text %lu)%@", beforeRow, content.rows[0], expected.textCharacters, tag]);
    Check([NSUserDefaults.standardUserDefaults boolForKey:@"StatisticsIgnoresWhitespace"] && [NSUserDefaults.standardUserDefaults boolForKey:@"StatisticsIgnoresLineEndings"]
          && !content.consecutiveWhitespaceBox.enabled, [@"popover options: kept; no runs to take as one with both left out" stringByAppendingString:tag]);
    [content.unitPopUp selectItemWithTag:TSCharacterUnitByte];
    [content.unitPopUp sendAction:content.unitPopUp.action to:content.unitPopUp.target];
    TSCharacterCountOptions *bytes = [shown copy]; bytes.unit = TSCharacterUnitByte;
    Check(WaitFor(^BOOL{ return [content.rows[0] hasPrefix:[L(@"Bytes") stringByAppendingString:@"|"]] && Cell(content.rows[0], 1) == TSCharacterCountWithOptions(sourceText, bytes, nil); }, 10)
          && !content.encodingPopUp.hiddenOrHasHiddenAncestor && content.encodingPopUp.numberOfItems == 3 && content.encodingPopUp.selectedTag == (NSInteger)NSUTF8StringEncoding,
          [NSString stringWithFormat:@"popover options: bytes, named so, in the document's encoding among TeXShop's: %@%@", content.rows[0], tag]);
    NSUInteger calls = savingCalls;
    [content.encodingPopUp selectItemWithTag:(NSInteger)NSShiftJISStringEncoding];
    [content.encodingPopUp sendAction:content.encodingPopUp.action to:content.encodingPopUp.target];
    bytes.encoding = NSShiftJISStringEncoding;
    Check(WaitFor(^BOOL{ return Cell(content.rows[0], 1) == TSCharacterCountWithOptions(sourceText, bytes, nil); }, 10) && savingCalls > calls,
          [NSString stringWithFormat:@"popover options: bytes of Shift JIS, as TeXShop writes the text: %@%@", content.rows[0], tag]);
    DrawWithPopover(doc, [lang stringByAppendingString:@"-07-options"], nil);
    [doc->textView1 insertText:@"\U0001F600" replacementRange:NSMakeRange(0, 0)];
    [content.refreshButton performClick:nil];
    NSString *cannot = [NSString stringWithFormat:L(@"Some characters cannot be written in %@."), [NSString localizedNameOfStringEncoding:NSShiftJISStringEncoding]];
    Check(WaitFor(^BOOL{ return !content.counting; }, 20) && [[content.rows[0] componentsSeparatedByString:@"|"][1] isEqual:@"—"]
          && content.encodingPopUp.selectedTag == (NSInteger)NSShiftJISStringEncoding,
          [NSString stringWithFormat:@"popover options: a character Shift JIS cannot write: a dash (%@); refresh keeps the encoding chosen%@", content.rows[0], tag]);
    NSTextField *dash = nil;
    NSMutableArray *queue = [NSMutableArray arrayWithObject:content.view];
    while (queue.count) { NSView *v = queue.firstObject; [queue removeObjectAtIndex:0]; [queue addObjectsFromArray:v.subviews];
        if ([v isKindOfClass:NSTextField.class] && [[(NSTextField *)v stringValue] isEqual:@"—"]) dash = (NSTextField *)v; }
    Check([dash.toolTip isEqual:cannot], [NSString stringWithFormat:@"popover options: the dash says why: %@%@", dash.toolTip, tag]);
    [doc->textView1 replaceCharactersInRange:NSMakeRange(0, 2) withString:@""];
    // Opened again: the options kept, the encoding the document's.
    [popover close];
    doc->_encoding = NSJapaneseEUCStringEncoding;
    [doc showStatistics:nil];
    WaitFor(^BOOL{ return !content.counting; }, 20);
    Check(!content.optionsView.hiddenOrHasHiddenAncestor && content.unitPopUp.selectedTag == TSCharacterUnitByte && content.ignoreWhitespaceBox.state == NSControlStateValueOn
          && content.encodingPopUp.selectedTag == (NSInteger)NSJapaneseEUCStringEncoding,
          [NSString stringWithFormat:@"popover options: opened again, the options stay and the encoding is the document's (%ld)%@", (long)content.encodingPopUp.selectedTag, tag]);
    doc->_encoding = NSUTF8StringEncoding;
    // Hidden or shown in another document: this one follows when it opens again.
    for (NSNumber *other in @[@NO, @YES]) {
        [popover close];
        [NSUserDefaults.standardUserDefaults setBool:other.boolValue forKey:@"StatisticsShowsCharacterCountOptions"];
        [doc showStatistics:nil];
        WaitFor(^BOOL{ return !content.counting; }, 20);
        Check(content.optionsView.hiddenOrHasHiddenAncestor == !other.boolValue && (content.optionsButton.state == NSControlStateValueOn) == other.boolValue,
              [NSString stringWithFormat:@"popover options: %@ in another document, %@ here when opened again%@", other.boolValue ? @"shown" : @"hidden",
               content.optionsView.hiddenOrHasHiddenAncestor ? @"hidden" : @"shown", tag]);
    }
    [content.optionsButton performClick:nil];
    Check(content.optionsView.hiddenOrHasHiddenAncestor && [content.optionsButton.contentTintColor isEqual:NSColor.controlAccentColor]
          && ![NSUserDefaults.standardUserDefaults boolForKey:@"StatisticsShowsCharacterCountOptions"],
          [@"popover options: hidden again, the button tinted while the count is not the status bar's" stringByAppendingString:tag]);
    [content.unitPopUp selectItemWithTag:TSCharacterUnitGraphemeCluster];
    [content.unitPopUp sendAction:content.unitPopUp.action to:content.unitPopUp.target];
    WaitFor(^BOOL{ return [content.rows[0] hasPrefix:[L(@"Characters") stringByAppendingString:@"|"]]; }, 10);
    DrawWithPopover(doc, [lang stringByAppendingString:@"-08-options-tinted"], nil);
    for (NSButton *box in @[content.ignoreWhitespaceBox, content.ignoreLineEndingsBox]) [box performClick:nil];
    Check(WaitFor(^BOOL{ return Cell(content.rows[0], 1) == TSStatusBarCharacterCount(doc->textView1.string, NSMakeRange(0, doc->textView1.string.length), nil); }, 10)
          && content.optionsButton.contentTintColor == nil && [TSCharacterCountOptions savedOptions].isDefault,
          [@"popover options: back to the status bar's count, the button plain" stringByAppendingString:tag]);

    // The window near the top and near the bottom of the screen: above the button too.
    NSRect middle = doc->textWindow.frame;
    for (NSNumber *y in @[@(NSMaxY(Screen) - NSHeight(middle)), @(NSMinY(Screen) + 10)]) {
        [popover close];
        [doc->textWindow setFrameOrigin:NSMakePoint(NSMinX(middle), y.doubleValue)];
        [bar.statisticsButton performClick:nil];
        NSRect button = OnScreen(bar.statisticsButton, bar.statisticsButton.bounds);
        Check(shownView == bar.statisticsButton && Above(shownContent, button) && NSMaxY(shownContent) < NSMaxY(doc->textWindow.frame),
              [NSString stringWithFormat:@"the window near the %@ of the screen: above the button (%@)%@", y.doubleValue > NSMidY(Screen) ? @"top" : @"bottom",
               Where(shownContent, button), tag]);
    }
    [popover close];
    [doc->textWindow setFrameOrigin:middle.origin];
    // An anchor that is not flipped: its top is its maximum y.
    NSView *plain = [[NSView alloc] initWithFrame:NSMakeRect(20, 4, 120, 20)];
    [doc->textWindow.contentView addSubview:plain];
    [doc showStatisticsFromView:plain];
    NSRect plainOnScreen = OnScreen(plain, plain.bounds);
    Check(!plain.isFlipped && shownView == plain && Above(shownContent, plainOnScreen),
          [NSString stringWithFormat:@"an anchor that is not flipped: above it as well (%@)%@", Where(shownContent, plainOnScreen), tag]);
    [popover close];
    [plain removeFromSuperview];

    // The status bar hidden: from the bottom edge of the part being typed in, above it, over the source.
    TSSourceStatusBar.shown = NO;
    Check(bar.statisticsButton == nil, [@"no button while the bar is hidden" stringByAppendingString:tag]);
    for (NSNumber *y in @[@(NSMinY(middle)), @(NSMaxY(Screen) - NSHeight(middle)), @(NSMinY(Screen) + 10)]) {
        [popover close];
        [doc->textWindow setFrameOrigin:NSMakePoint(NSMinX(middle), y.doubleValue)];
        [doc showStatistics:nil];
        NSRect bottom = OnScreen(doc->scrollView, shownRect), source = OnScreen(doc->scrollView, doc->scrollView.bounds);
        NSString *place = y.doubleValue == NSMinY(middle) ? @"middle" : y.doubleValue > NSMidY(Screen) ? @"top" : @"bottom";
        Check(shownView == doc->scrollView && shownRect.size.height == 1 && fabs(shownRect.origin.y - (doc->scrollView.isFlipped ? NSMaxY(doc->scrollView.bounds) - 1 : 0)) < 0.5
              && fabs(NSMinY(bottom) - NSMinY(source)) < 0.5, [NSString stringWithFormat:@"with the bar hidden, the popover points at the bottom of the source (%@)%@", NSStringFromRect(shownRect), tag]);
        Check(Above(shownContent, bottom) && NSMaxY(shownContent) <= NSMaxY(source),
              [NSString stringWithFormat:@"with the bar hidden, the window in the %@ of the screen: above the bottom edge of the source, over it (%@, source %@)%@",
               place, Where(shownContent, bottom), NSStringFromRect(source), tag]);
    }
    [doc->textWindow setFrameOrigin:middle.origin];
    [popover close];
    [doc showStatistics:nil];
    WaitFor(^BOOL{ return !content.counting; }, 20);
    DrawWithPopover(doc, [lang stringByAppendingString:@"-06-bar-hidden"], nil);
    NSSize size = NSMakeSize(NSWidth(doc->scrollView.frame), 100);
    [doc->scrollView setFrameSize:size]; [doc->scrollView2 setFrameSize:size];
    [doc->splitView addSubview:doc->scrollView2]; [doc->splitView adjustSubviews];
    doc->textView = doc->textView2;
    [popover close];
    [doc showStatistics:nil];
    NSRect part = OnScreen(doc->scrollView2, shownRect);
    Check(shownView == doc->scrollView2 && Above(shownContent, part),
          [NSString stringWithFormat:@"in a split source, above the bottom of the part being typed in (%@)%@", Where(shownContent, part), tag]);
    // The window that shows both.
    [doc->splitView removeFromSuperview]; [doc->leftView addSubview:doc->splitView]; doc->splitView.frame = doc->leftView.bounds;
    [doc.sourceStatusBar placeBelowView:doc->splitView];
    [doc->fullSplitWindow setFrame:NSMakeRect(NSMinX(Screen) + 200, NSMinY(Screen) + 680, 1200, 640) display:NO];
    [popover close];
    [doc showStatistics:nil];
    part = OnScreen(shownView, shownRect);
    Check(shownView.window == doc->fullSplitWindow && Above(shownContent, part),
          [NSString stringWithFormat:@"in the window that shows both, with the bar hidden: above the bottom of the source (%@)%@", Where(shownContent, part), tag]);
    TSSourceStatusBar.shown = YES;
    [popover close];
    [doc showStatistics:nil];
    part = OnScreen(bar.statisticsButton, bar.statisticsButton.bounds);
    Check(shownView == bar.statisticsButton && shownView.window == doc->fullSplitWindow && Above(shownContent, part),
          [NSString stringWithFormat:@"in the window that shows both, from the button: above it (%@)%@", Where(shownContent, part), tag]);
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
    for name in ('TSStatusBarCounting.m', 'TSSourceStatusBar.m', 'TSTextStatistics.m', 'TSTextStatisticsPopover.m', 'TSDocumentWindowGlass.m', 'NSString-Extras.m'):
        (tmp / name).write_text(text[name], encoding='utf-8', errors='surrogateescape')
    program = (PROGRAM.replace('@@SHOW@@', fragments['show']).replace('@@FROM@@', fragments['from'])
               .replace('@@RECT@@', fragments['rect']))
    if not args.mutation:
        verify_embedded(program, [(k, document, v) for k, v in originals.items()])
    elif MUTATIONS[args.mutation][0] == 'PROGRAM':
        _, old, new = MUTATIONS[args.mutation]
        assert program.count(old) == 1, args.mutation; program = program.replace(old, new)
    (tmp / 'probe.m').write_text(program, encoding='utf-8')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-framework', 'Quartz', '-licucore', '-I', str(tmp), *include_args(root), '-I', str(root / 'Tests'),
                    str(tmp / 'probe.m'), *(str(tmp / n) for n in ('TSStatusBarCounting.m', 'TSSourceStatusBar.m', 'TSTextStatistics.m',
                    'TSTextStatisticsPopover.m', 'TSDocumentWindowGlass.m', 'NSString-Extras.m')), '-o', str(tmp / 'probe')], check=True)
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
        # NSTemporaryDirectory() follows DIRHELPER_USER_DIR_SUFFIX, not TMPDIR: give the probe a
        # temporary folder of its own, so files of other processes are not counted.
        probe_env = dict(os.environ, DIRHELPER_USER_DIR_SUFFIX=f'texshop-statistics-test-{os.getpid()}-{folder_name}')
        result = subprocess.run([str(tmp / 'probe'), str(tmp / 'spec.json'), '-AppleLanguages', f'({folder_name})'], capture_output=True, text=True, timeout=600, env=probe_env)
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
