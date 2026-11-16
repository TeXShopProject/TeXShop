#!/usr/bin/env python3
"""Zoom to Content and Zoom to Content Width (#33) with the production code, in windows that
are never shown: the Preview window's toolbar group, its zoom of the active part, and the
shared zoom of TSContentZoom.h on real PDFKit views. The content is measured as the page is
shown: with /Rotate and a CropBox, its visual top comes to the top of the view and its visual
width fills the view; a page number at the foot does not shrink Zoom to Content Width. With one
page across, the next page (or the one before the last) sets the width too, so that pages printed
on both sides, with their text further left or right on every other page, keep their line ends.
Fit to Content Width has its own test, run-fit-content-width.py."""
from pathlib import Path
import argparse, re, subprocess, sys, tempfile
from source_tree import include_args
from production_fragments import method, verify_embedded

MUTATIONS = {
    # TSContentZoom.h
    'height-limits-width': ('zoom', 'widthOnly ? nil : ^CGFloat{ return NSHeight(TSContentRectInView(view, row)); }',
                            '^CGFloat{ return NSHeight(TSContentRectInView(view, row)); }'),
    'centred-not-top': ('zoom', '    TSContentScrollTo(view, target, widthOnly, !widthOnly);', '    TSContentScrollTo(view, target, NO, YES);'),
    'no-next-page': ('zoom', '    return next ? [row arrayByAddingObject:next] : row;', '    return row;'),
    'no-page-before-last': ('zoom', '    NSInteger other = index + 1 < count ? index + 1 : index - 1;', '    NSInteger other = index + 1;'),
    'height-of-both-pages': ('zoom', 'return NSHeight(TSContentRectInView(view, row)); }', 'return NSHeight(TSContentRectInView(view, across)); }'),
    'rotation-ignored': ('zoom', '    CGAffineTransform toDrawn = [page transformForBox:box];',
                         '    CGAffineTransform toDrawn = CGAffineTransformMakeTranslation(-NSMinX(bounds), -NSMinY(bounds));'),
    'one-page-in-two-up': ('zoom', '            if (beside) [pages addObject:beside];', '            if (NO) [pages addObject:beside];'),
    'partner-only-if-shown': ('zoom', '            if (beside) [pages addObject:beside];',
                              '            if (beside && [shown containsObject:beside]) [pages addObject:beside];'),
    'cover-ignored': ('zoom', '        NSInteger first = view.displaysAsBook ? 1 : 0;', '        NSInteger first = 0;'),
    'partner-by-height': ('zoom', '        NSInteger other = index < first ? -1 : ((index - first) % 2 == 0 ? index + 1 : index - 1);',
                          '        NSInteger other = index - 1;'),
    'one-pass': ('zoom', '    for (int pass = 0; pass < 4; pass++) {', '    for (int pass = 0; pass < 1; pass++) {'),
    # MyPDFKitView.m
    'rounded-up': ('view', 'MIN((NSInteger)floor(scale * 100.0 + 1e-6), PDF_MAX_SCALE)', 'MIN((NSInteger)ceil(scale * 100.0), PDF_MAX_SCALE)'),
    'zoom-keeps-fit': ('view', '\t// A fixed magnification, as Zoom In sets, also when it did not change.\n\tresizeOption = NEW_PDF_FIT_TO_NONE;\n', ''),
    'menu-whole-is-width': ('view', '- (void)zoomToContent:(id)sender\n{\n\t[self zoomToContentWidthOnly:NO];', '- (void)zoomToContent:(id)sender\n{\n\t[self zoomToContentWidthOnly:YES];'),
    # TSToolbarController.m
    'wrong-part': ('toolbar', '    MyPDFKitView *view = [self pdfKitView];\n    if ((index == 0 || index == 1)',
                   '    MyPDFKitView *view = [self myPDFKitView];\n    if ((index == 0 || index == 1)'),
    'second-button-whole': ('toolbar', '        [view zoomToContentWidthOnly:index == 1];', '        [view zoomToContentWidthOnly:NO];'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
zoom_path = root / 'Sources/Preview/TSContentZoom.h'
view_source = (root / 'Sources/Preview/MyPDFKitView.m').read_text(encoding='latin1')
toolbar_source = (root / 'Sources/Windows/TSToolbarController.m').read_text(encoding='latin1')
# Included without #pragma once, which warns in a main file.
zoom_text = zoom_path.read_text().replace('#pragma once\n', '', 1)

# The group is offered in both preview toolbars (the Preview window and the single window,
# with and without sharing), next to the magnification field, and in none of the defaults.
allowed = method(toolbar_source, '- (NSArray *) toolbarAllowedItemIdentifiers: (NSToolbar *) toolbar {')
default = method(toolbar_source, '- (NSArray *) toolbarDefaultItemIdentifiers: (NSToolbar *) toolbar {')
assert allowed.count('kMagnificationKKTID,\n\t\t\t\t\tkContentZoomKKTID,') == 2, 'Preview window toolbars offer the group'
assert allowed.count('skMagnificationKKTID,\n                    kContentZoomKKTID,') == 2, 'Single window toolbars offer the group'
assert allowed.count('kContentZoomKKTID') == 4 and 'kContentZoomKKTID' not in default, 'Offered, not added by default'
identifier = re.search(r'static NSString\*\s+kContentZoomKKTID\s+= (@"\w+");', toolbar_source)
assert identifier, 'Group identifier'
# Every language names the new button; only English keeps the English words.
for strings in sorted((root / 'Resources/Interfaces').glob('*.lproj/ToolbarItems.strings')):
    text = strings.read_text()
    found = re.search(r'"?ExperimentZoomToContentWidth"?\s*=\s*"([^"]+)";', text)
    assert found, 'Zoom to Content Width in ' + strings.parent.name
    assert (found.group(1) == 'Zoom to Content Width') == (strings.parent.name == 'en.lproj'), 'Translated in ' + strings.parent.name
print('PASS: toolbar lists and the names in %d languages' % len(list((root / 'Resources/Interfaces').glob('*.lproj/ToolbarItems.strings'))))

# Preview > Magnification: Fit to Content Width with the other magnifications (tag 6, after
# Fit to Window), and the two zooms after Zoom Out, named as the toolbar buttons, in every
# language. The magnification is never named like a zoom.
import plistlib, xml.etree.ElementTree as ET
def strings_table(path):
    return plistlib.loads(subprocess.run(['plutil', '-convert', 'xml1', '-o', '-', str(path)], capture_output=True, check=True).stdout)
menus = sorted((root / 'Resources/Interfaces').glob('*.lproj/MainMenu.nib/designable.nib'))
assert len(menus) == 12, 'twelve menus'
for nib in menus:
    language = nib.parent.parent.name.split('.')[0]
    tree = ET.parse(nib)
    magnification = next(menu for menu in tree.iter('menu')
                         if any(i.get('identifier') == 'TSShortcut.changePDFViewSize:.3' for i in menu.findall('items/menuItem')))
    items = [i for i in magnification.find('items') if i.tag == 'menuItem']
    ids = [i.get('identifier') for i in items]
    def at(name):
        assert name in ids, name + ' in ' + language
        return items[ids.index(name)]
    fit = at('TSShortcut.changePDFViewSize:.6')
    assert ids.index('TSShortcut.changePDFViewSize:.6') == ids.index('TSShortcut.changePDFViewSize:.3') + 1, 'after Fit to Window in ' + language
    assert fit.get('tag') == '6' and fit.find('connections/action').get('selector') == 'changePDFViewSize:', language
    out = ids.index('TSShortcut.zoomOut:.0')
    assert ids[out + 1:out + 3] == ['TSShortcut.zoomToContent:.0', 'TSShortcut.zoomToContentWidth:.0'], 'after Zoom Out in ' + language
    for name, selector in (('TSShortcut.zoomToContent:.0', 'zoomToContent:'), ('TSShortcut.zoomToContentWidth:.0', 'zoomToContentWidth:')):
        item = at(name)
        assert item.find('connections/action').get('selector') == selector and item.find('connections/action').get('target') == '-1', language
        assert not item.get('keyEquivalent'), 'no default key in ' + language
    toolbar = strings_table(root / 'Resources/Interfaces' / (('en' if language == 'Base' else language) + '.lproj') / 'ToolbarItems.strings')
    whole, width = toolbar['ExperimentZoomToContent'], toolbar['ExperimentZoomToContentWidth']
    assert at('TSShortcut.zoomToContent:.0').get('title') == whole and at('TSShortcut.zoomToContentWidth:.0').get('title') == width, 'toolbar names in ' + language
    names = [i.get('title') for i in items if i.get('title')]
    assert len(set(names)) == len(names), 'distinct names in ' + language
    assert (fit.get('title') == 'Fit to Content Width') == (language == 'Base'), 'translated in ' + language
    settings = strings_table(root / 'Resources/Interfaces' / (language + '.lproj') / 'SettingsPreview.strings')
    assert settings['Fc6-Pp-tH1.title'] == fit.get('title'), 'Settings names it as the menu in ' + language
xib = (root / 'Resources/Interfaces/Base.lproj/SettingsPreview.xib').read_text()
assert '<menuItem title="Fit to Window" state="on" tag="3" id="339" />\n                      <menuItem title="Fit to Content Width" tag="6" id="Fc6-Pp-tH1" />' in xib, 'Settings > Preview offers it'
print('PASS: Preview > Magnification and Settings in %d languages' % len(menus))

view_methods = [method(view_source, s) for s in (
    '- (void)zoomToContentWidthOnly:(BOOL)widthOnly', '- (void)zoomToContent:(id)sender', '- (void)zoomToContentWidth:(id)sender',
    '- (void) changeScale: sender', '- (void)setScaleFactor:(CGFloat)scale')]
toolbar_methods = [method(toolbar_source, s) for s in (
    '- (NSToolbarItem *)contentZoomToolbarItem', '- (void)zoomPreviewToContent:(id)sender')]
fragments = [('complete method: ' + t.split('\n')[0], src, t)
             for src, texts in ((view_source, view_methods), (toolbar_source, toolbar_methods)) for t in texts]
fragments.append(('header without #pragma once: TSContentZoom.h', zoom_path.read_text(), zoom_text))
view_text, toolbar_text = '\n'.join(view_methods), '\n'.join(toolbar_methods)
if args.mutation:
    which, old, new = MUTATIONS[args.mutation]
    text = {'zoom': zoom_text, 'view': view_text, 'toolbar': toolbar_text}[which]
    assert text.count(old) == 1, args.mutation
    text = text.replace(old, new)
    if which == 'zoom': zoom_text = text
    elif which == 'view': view_text = text
    else: toolbar_text = text

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import "TestAppKitIsolation.h"
#import "TSPreviewScrollerKeeper.h"
ZOOMHEADER
#define PDF_MAX_SCALE 2000
enum { NEW_PDF_ACTUAL_SIZE = 1, NEW_PDF_FIT_TO_NONE = 2, NEW_PDF_FIT_TO_WINDOW = 3, NEW_PDF_FIT_TO_CONTENT_WIDTH = 6 };
static NSString *kContentZoomKKTID = IDENTIFIER;
static NSUInteger checks;
static NSString *context = @"";
static void check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL: %s [%s]\n", message.UTF8String, context.UTF8String); exit(1); }
}
static void settle(NSWindow *w) {
    for (int i = 0; i < 4; i++) {
        [w layoutIfNeeded];
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
}
@interface TestDocument : NSObject <NSToolbarDelegate>
@property id pdfKitView, myPDFKitView;
- (NSPanel *)magnificationPanel;
@end
@interface MyPDFKitView : PDFView {
    BOOL _fittingContentWidth;
    NSInteger resizeOption, scaleMag;
    NSTextField *myScale, *smyScale, *myScale1;
    NSStepper *myStepper, *smyStepper, *myStepper1;
}
@property (weak) TestDocument *myDocument;
@property NSInteger marqueeCleanups;
- (void)zoomToContentWidthOnly:(BOOL)widthOnly;
- (void)zoomToContent:(id)sender;
- (void)zoomToContentWidth:(id)sender;
@end
@implementation MyPDFKitView
- (void)useScaleField:(NSTextField *)field { myScale = field; }
- (NSInteger)resizeOption { return resizeOption; }
- (void)setResizeOption:(NSInteger)option { resizeOption = option; }
- (void)cleanupMarquee:(BOOL)terminate { self.marqueeCleanups++; }
// Zoom cleans up the marquee and keeps a pinned link popup, in view (#35).
- (void)cleanupMarqueeKeepingPinnedLinkPreview { self.marqueeCleanups++; }
- (void)keepPinnedLinkPreviewInView {}
VIEWMETHODS
@end
@implementation TestDocument
- (NSPanel *)magnificationPanel { return nil; }
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar { return @[kContentZoomKKTID]; }
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar { return @[kContentZoomKKTID]; }
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)identifier willBeInsertedIntoToolbar:(BOOL)inserted {
    return [identifier isEqual:kContentZoomKKTID] ? [self contentZoomToolbarItem] : nil;
}
TOOLBARMETHODS
@end

// A4 pages. The body and a page number at the foot; page 2 has a narrower body on the
// left; page 6 is blank.
static const NSRect Body = {{100, 200}, {395, 550}}, Number = {{290, 40}, {15, 12}}, Left = {{40, 250}, {260, 450}};
static PDFDocument *makeDocument(NSInteger rotation, NSRect crop) {
    NSMutableData *data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect media = CGRectMake(0, 0, 595, 842);
    CGContextRef pdf = CGPDFContextCreate(consumer, &media, NULL);
    for (int i = 0; i < 6; i++) {
        CGPDFContextBeginPage(pdf, NULL);
        CGContextSetGrayFillColor(pdf, 0, 1);
        if (i < 5) {
            CGContextFillRect(pdf, NSRectToCGRect(i == 1 ? Left : Body));
            CGContextFillRect(pdf, NSRectToCGRect(Number));
        }
        CGPDFContextEndPage(pdf);
    }
    CGPDFContextClose(pdf); CGContextRelease(pdf); CGDataConsumerRelease(consumer);
    PDFDocument *document = [[PDFDocument alloc] initWithData:data];
    for (NSUInteger i = 0; i < document.pageCount; i++) {
        PDFPage *page = [document pageAtIndex:i];
        if (!NSIsEmptyRect(crop)) [page setBounds:crop forBox:kPDFDisplayBoxCropBox];
        page.rotation = rotation;
    }
    // Read back, so that the rotation and the crop box come from /Rotate and /CropBox.
    PDFDocument *saved = [[PDFDocument alloc] initWithData:document.dataRepresentation];
    check([saved pageAtIndex:0].rotation == rotation, @"the file keeps /Rotate");
    return saved;
}

// Pages printed on both sides: the text further right on every other page, as with the book
// class; with wide, page 7 also has a figure wider than the text.
static const NSRect OddBody = {{107, 150}, {343, 600}}, EvenBody = {{161, 150}, {343, 600}}, Wide = {{60, 400}, {480, 100}};
static NSRect sideInk(NSUInteger index, BOOL wide) {
    NSRect ink = NSUnionRect(index % 2 ? EvenBody : OddBody, Number);
    if (wide && index == 6) ink = NSUnionRect(ink, Wide);
    return NSInsetRect(ink, -8, -8);
}
static PDFDocument *makeTwoSided(BOOL wide, NSUInteger count) {
    NSMutableData *data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect media = CGRectMake(0, 0, 595, 842);
    CGContextRef pdf = CGPDFContextCreate(consumer, &media, NULL);
    for (NSUInteger i = 0; i < count; i++) {
        CGPDFContextBeginPage(pdf, NULL);
        CGContextSetGrayFillColor(pdf, 0, 1);
        CGContextFillRect(pdf, NSRectToCGRect(i % 2 ? EvenBody : OddBody));
        CGContextFillRect(pdf, NSRectToCGRect(Number));
        if (wide && i == 6) CGContextFillRect(pdf, NSRectToCGRect(Wide));
        CGPDFContextEndPage(pdf);
    }
    CGPDFContextClose(pdf); CGContextRelease(pdf); CGDataConsumerRelease(consumer);
    return [[PDFDocument alloc] initWithData:data];
}

typedef struct { NSWindow *window; MyPDFKitView *upper, *lower; NSTextField *field; TestDocument *document; } Preview;
static Preview makePreview(PDFDocument *document, PDFDisplayMode mode) {
    Preview p;
    p.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 1000)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    p.window.releasedWhenClosed = NO;
    p.document = [TestDocument new];
    p.field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 60, 20)];
    // Two parts, as a split preview; the lower one is active.
    p.upper = [[MyPDFKitView alloc] initWithFrame:NSMakeRect(0, 600, 600, 400)];
    p.lower = [[MyPDFKitView alloc] initWithFrame:NSMakeRect(0, 0, 600, 600)];
    for (MyPDFKitView *view in @[p.upper, p.lower]) {
        [p.window.contentView addSubview:view];
        [view useScaleField:p.field];
        view.myDocument = p.document;
        view.displayBox = kPDFDisplayBoxCropBox;
        view.displayMode = mode;
        view.displaysPageBreaks = YES;
        view.document = document;
        // As MyPDFKitView does when it gets a document or a window: the text at the top edge
        // stays when a scroller comes or goes, also after a zoom.
        [TSPreviewScrollerKeeper installInView:view];
        view.autoScales = YES;
    }
    p.document.pdfKitView = p.lower; p.document.myPDFKitView = p.upper;
    settle(p.window);
    for (MyPDFKitView *view in @[p.upper, p.lower]) [TSPreviewScrollerKeeper installInView:view];
    return p;
}
static NSClipView *clipOf(PDFView *view) { return view.documentView.enclosingScrollView.contentView; }
// A point of the clip view (left/right 0..1, top 0..1 from the top) on a page, in page coordinates.
static NSPoint shown(PDFView *view, PDFPage *page, CGFloat across, CGFloat down) {
    NSClipView *clip = clipOf(view);
    NSRect b = clip.bounds;
    NSPoint point = NSMakePoint(NSMinX(b) + across * NSWidth(b), clip.isFlipped ? NSMinY(b) + down * NSHeight(b) : NSMaxY(b) - down * NSHeight(b));
    return [view convertPoint:[view convertPoint:point fromView:clip] toPage:page];
}
static void show(PDFView *view, NSUInteger index) {
    [view goToPage:[view.document pageAtIndex:index]];
    settle(view.window);
}
// The coordinate of a page point that a direction on screen follows.
static CGFloat along(NSPoint point, NSInteger rotation) { return rotation % 180 ? point.x : point.y; }
static CGFloat across(NSPoint point, NSInteger rotation) { return rotation % 180 ? point.y : point.x; }

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    // Content of the pages with the body: Body and Number, with the 8pt margin.
    NSRect ink = NSInsetRect(NSUnionRect(Body, Number), -8, -8);
    for (NSInteger rotation = 0; rotation < 360; rotation += 90) for (int cropped = 0; cropped < 2; cropped++) {
        context = [NSString stringWithFormat:@"rotation %ld%@", (long)rotation, cropped ? @" with a crop box" : @""];
        PDFDocument *document = makeDocument(rotation, cropped ? NSMakeRect(30, 20, 535, 800) : NSZeroRect);
        PDFPage *third = [document pageAtIndex:2];
        NSRect measured = TSContentInkBounds(third, kPDFDisplayBoxCropBox);
        check(fabs(NSMinX(measured) - 100) < 1 && fabs(NSMaxX(measured) - 495) < 1 && fabs(NSMinY(measured) - 40) < 1 && fabs(NSMaxY(measured) - 750) < 1,
              [NSString stringWithFormat:@"ink in page coordinates %@", NSStringFromRect(measured)]);
        Preview p = makePreview(document, kPDFDisplaySinglePageContinuous);
        MyPDFKitView *view = p.lower;
        // The width and height of the content as shown.
        CGFloat wide = rotation % 180 ? NSHeight(ink) : NSWidth(ink), high = rotation % 180 ? NSWidth(ink) : NSHeight(ink);

        show(view, 2);
        [view zoomToContentWidthOnly:YES]; settle(p.window);
        CGFloat width = NSWidth(clipOf(view).frame), scale = view.scaleFactor;
        check(scale * wide <= width + 0.5 && scale * wide > width * 0.98,
              [NSString stringWithFormat:@"content width %.1f fills the view %.1f", scale * wide, width]);
        check(fabs(scale * 100 - floor(width / wide * 100 + 1e-6)) < 0.01 && p.field.integerValue == lround(scale * 100),
              [NSString stringWithFormat:@"whole percent %ld, rounded down, in the field", (long)p.field.integerValue]);
        check(view.resizeOption == NEW_PDF_FIT_TO_NONE && !view.autoScales && view.marqueeCleanups > 0, @"a fixed magnification, as Zoom In sets");
        // The top of the view shows the top of the content as seen: the side of the page that
        // the rotation turns upward.
        NSPoint top = shown(view, third, .5, 0);
        CGFloat expectedTop = rotation == 0 ? NSMaxY(ink) : rotation == 90 ? NSMinX(ink) : rotation == 180 ? NSMinY(ink) : NSMaxX(ink);
        check(fabs((rotation % 180 ? top.x : top.y) - expectedTop) < 1.5,
              [NSString stringWithFormat:@"top of the content at the top of the view (%@, expected %.0f)", NSStringFromPoint(top), expectedTop]);
        // Left and right edges of the view are those of the content as seen.
        NSPoint leftEdge = shown(view, third, 0, .5), rightEdge = shown(view, third, 1, .5);
        CGFloat expectedLeft = rotation == 0 ? NSMinX(ink) : rotation == 90 ? NSMinY(ink) : rotation == 180 ? NSMaxX(ink) : NSMaxY(ink);
        CGFloat expectedRight = rotation == 0 ? NSMaxX(ink) : rotation == 90 ? NSMaxY(ink) : rotation == 180 ? NSMinX(ink) : NSMinY(ink);
        check(fabs(across(leftEdge, rotation) - expectedLeft) < 3 && fabs(across(rightEdge, rotation) - expectedRight) < 3,
              [NSString stringWithFormat:@"content across the view (%@ to %@)", NSStringFromPoint(leftEdge), NSStringFromPoint(rightEdge)]);
        CGFloat widthScale = scale;

        // Zoom to Content: the whole content, page number included, in the view, centred.
        p.upper.scaleFactor = 0.5; CGFloat upperScale = p.upper.scaleFactor;
        [view zoomToContentWidthOnly:NO]; settle(p.window);
        scale = view.scaleFactor;
        CGFloat height = NSHeight(clipOf(view).frame);
        check(scale * wide <= NSWidth(clipOf(view).frame) + 0.5 && scale * high <= height + 0.5 &&
              (scale * wide > NSWidth(clipOf(view).frame) * 0.98 || scale * high > height * 0.98),
              [NSString stringWithFormat:@"whole content %.0fx%.0f fits %.0fx%.0f", scale * wide, scale * high, NSWidth(clipOf(view).frame), height]);
        NSPoint middle = shown(view, third, .5, .5);
        check(fabs(middle.x - NSMidX(ink)) < 3 && fabs(middle.y - NSMidY(ink)) < 3,
              [NSString stringWithFormat:@"whole content centred (%@)", NSStringFromPoint(middle)]);
        if (rotation % 180 == 0)
            check(widthScale > scale * 1.3, @"the page number does not shrink Zoom to Content Width (#33)");
        // From Fit to Content Width, a zoom that gives the same magnification still makes it fixed.
        view.resizeOption = NEW_PDF_FIT_TO_CONTENT_WIDTH;
        [view zoomToContentWidthOnly:NO]; settle(p.window);
        check(fabs(view.scaleFactor - scale) < 1e-6 && view.resizeOption == NEW_PDF_FIT_TO_NONE, @"fixed after a zoom that changes nothing");
        check(p.upper.scaleFactor == upperScale, @"the other part keeps its magnification");
        [p.window close];
    }

    // Two-page layout: the content of both pages of the row fills the width.
    context = @"two pages";
    for (NSNumber *mode in @[@(kPDFDisplayTwoUpContinuous), @(kPDFDisplayTwoUp)]) {
        PDFDocument *document = makeDocument(0, NSZeroRect);
        Preview p = makePreview(document, (PDFDisplayMode)mode.integerValue);
        MyPDFKitView *view = p.lower;
        show(view, 0);
        [view zoomToContentWidthOnly:YES]; settle(p.window);
        PDFPage *first = [document pageAtIndex:0], *second = [document pageAtIndex:1];
        NSPoint leftEdge = shown(view, first, 0, .5), rightEdge = shown(view, second, 1, .5);
        // Rounding down to a whole percent leaves up to 0.01 of the width, half on each side
        // (the row is about 830 page units wide).
        CGFloat slack = 1.5 + 0.005 / view.scaleFactor * 830;
        check(fabs(leftEdge.x - (NSMinX(Body) - 8)) < slack && fabs(rightEdge.x - (NSMaxX(NSUnionRect(Left, Number)) + 8)) < slack,
              [NSString stringWithFormat:@"from the first page's content to the second's (%.1f, %.1f) in mode %ld",
               leftEdge.x, rightEdge.x, (long)mode.integerValue]);
        // Unless the view cannot scroll that far: one row at a time ends below the content.
        NSClipView *clip = clipOf(view);
        BOOL atEnd = clip.isFlipped ? NSMaxY(clip.bounds) >= NSHeight(view.documentView.frame) - 1 : NSMinY(clip.bounds) <= 1;
        CGFloat seenTop = shown(view, first, .25, 0).y;
        check(fabs(seenTop - (NSMaxY(Body) + 8)) < 1.5 || (atEnd && seenTop > NSMaxY(Body) + 8 && mode.integerValue == kPDFDisplayTwoUp),
              [NSString stringWithFormat:@"top of the higher content at the top in mode %ld (%.1f; document %@, clip %@)", (long)mode.integerValue,
               shown(view, first, .25, 0).y, NSStringFromRect(view.documentView.frame), NSStringFromRect(clipOf(view).bounds)]);
        [p.window close];
    }

    // Rows of two pages, with and without a cover page, in either direction: the page beside
    // the one in view is the other page of its row, never a page of another row that PDFKit
    // places at the same height while one row at a time is shown. The rows of one row at a
    // time are those PDFKit shows; a second press keeps the magnification.
    for (NSNumber *mode in @[@(kPDFDisplayTwoUp), @(kPDFDisplayTwoUpContinuous)])
    for (int book = 0; book < 2; book++) for (int rtl = 0; rtl < 2; rtl++) for (NSUInteger index = 0; index < 6; index++)
    for (int enlarged = 0; enlarged < 2; enlarged++) for (int whole = 0; whole < 2; whole++) {
        context = [NSString stringWithFormat:@"row: mode %ld, cover %d, right to left %d, page %lu, from %@, %@",
                   (long)mode.integerValue, book, rtl, (unsigned long)index, enlarged ? @"250%" : @"Fit to Window",
                   whole ? @"Zoom to Content" : @"Zoom to Content Width"];
        PDFDocument *document = makeDocument(0, NSZeroRect);
        Preview p = makePreview(document, (PDFDisplayMode)mode.integerValue);
        MyPDFKitView *view = p.lower;
        view.displaysAsBook = book; view.displaysRTL = rtl; view.autoScales = YES;
        show(view, index);
        NSMutableArray<PDFPage *> *row = [NSMutableArray array];
        if (mode.integerValue == kPDFDisplayTwoUp)
            [row addObjectsFromArray:view.visiblePages];
        else {
            NSInteger other = book && index == 0 ? -1 : ((NSInteger)index - book) % 2 == 0 ? (NSInteger)index + 1 : (NSInteger)index - 1;
            [row addObject:[document pageAtIndex:index]];
            if (other >= 0 && other < 6) [row addObject:[document pageAtIndex:other]];
        }
        check(row.count >= 1 && row.count <= 2, [NSString stringWithFormat:@"a row of %lu pages", (unsigned long)row.count]);
        BOOL blank = YES;
        for (PDFPage *page in row) if ([document indexForPage:page] != 5) blank = NO;
        // Enlarged, one page of the row may be out of sight; it still counts.
        if (enlarged) { view.scaleFactor = 2.5; settle(p.window); show(view, index); }
        [view zoomToContentWidthOnly:!whole]; settle(p.window);
        CGFloat scale = view.scaleFactor;
        if (blank) { [p.window close]; continue; }
        NSRect content = NSZeroRect;
        for (PDFPage *page in row) {
            NSUInteger i = [document indexForPage:page];
            if (i == 5) continue;
            NSRect ink = NSInsetRect(NSUnionRect(i == 1 ? Left : Body, Number), -8, -8);
            NSRect inView = [view convertRect:ink fromPage:page];
            content = NSIsEmptyRect(content) ? inView : NSUnionRect(content, inView);
        }
        CGFloat width = NSWidth(clipOf(view).frame), height = NSHeight(clipOf(view).frame);
        if (whole)
            check(NSWidth(content) <= width + 0.5 && NSHeight(content) <= height + 0.5 &&
                  (NSWidth(content) > width * 0.97 || NSHeight(content) > height * 0.97),
                  [NSString stringWithFormat:@"the content of the row %@ fits the view %.1fx%.1f at %.2f", NSStringFromSize(content.size), width, height, scale]);
        else
            check(NSWidth(content) <= width + 0.5 && NSWidth(content) > width * 0.97,
                  [NSString stringWithFormat:@"the content of the row %.1f fills the view %.1f at %.2f", NSWidth(content), width, scale]);
        [view zoomToContentWidthOnly:!whole]; settle(p.window);
        check(fabs(view.scaleFactor - scale) < 0.001, [NSString stringWithFormat:@"a second press keeps %.2f (%.2f)", scale, view.scaleFactor]);
        [p.window close];
    }

    // Pages printed on both sides. With one page across, both zooms take the next page too, or
    // the page before the last one, sideways: neither loses its line ends. The top, or the
    // height, is that of the page in view.
    for (NSNumber *mode in @[@(kPDFDisplaySinglePageContinuous), @(kPDFDisplaySinglePage)]) for (int whole = 0; whole < 2; whole++) {
        PDFDocument *document = makeTwoSided(NO, 8);
        Preview p = makePreview(document, (PDFDisplayMode)mode.integerValue);
        MyPDFKitView *view = p.lower;
        for (NSNumber *number in @[@2, @3, @7]) {
            NSUInteger index = number.unsignedIntegerValue, other = index + 1 < 8 ? index + 1 : index - 1;
            context = [NSString stringWithFormat:@"both sides: mode %ld, %@, page %lu", (long)mode.integerValue,
                       whole ? @"Zoom to Content" : @"Zoom to Content Width", (unsigned long)index];
            show(view, index);
            if (whole) [view zoomToContent:nil]; else [view zoomToContentWidth:nil];
            settle(p.window);
            NSRect ink = sideInk(index, NO), beside = sideInk(other, NO);
            CGFloat left = MIN(NSMinX(ink), NSMinX(beside)), right = MAX(NSMaxX(ink), NSMaxX(beside));
            PDFPage *page = [document pageAtIndex:index];
            CGFloat slack = 1.5 + 0.005 / view.scaleFactor * (right - left);
            CGFloat seenLeft = shown(view, page, 0, .5).x, seenRight = shown(view, page, 1, .5).x;
            check(view.resizeOption == NEW_PDF_FIT_TO_NONE, @"a fixed magnification");
            if (whole) {
                // Centred, unless the whole page is narrower than the view, which PDFKit then centres.
                BOOL wholePageAcross = seenLeft < 0 && seenRight > 595;
                check(seenLeft <= left + slack && seenRight >= right - slack &&
                      (wholePageAcross || fabs((seenLeft + seenRight) / 2 - (left + right) / 2) < slack),
                      [NSString stringWithFormat:@"both pages' content across, centred (%.1f to %.1f for %.1f to %.1f)", seenLeft, seenRight, left, right]);
                CGFloat top = shown(view, page, .5, 0).y, bottom = shown(view, page, .5, 1).y;
                check(top >= NSMaxY(ink) - slack && bottom <= NSMinY(ink) + slack,
                      [NSString stringWithFormat:@"the page's content top to bottom (%.1f to %.1f)", top, bottom]);
                check(fabs(seenRight - seenLeft - (right - left)) < slack || fabs(top - bottom - NSHeight(ink)) < slack + 2,
                      @"the width or the height fills the view");
            } else {
                check(fabs(seenLeft - left) < slack && fabs(seenRight - right) < slack,
                      [NSString stringWithFormat:@"both pages' content fills the width (%.1f to %.1f for %.1f to %.1f)", seenLeft, seenRight, left, right]);
                NSClipView *clip = clipOf(view);
                BOOL atEnd = clip.isFlipped ? NSMaxY(clip.bounds) >= NSHeight(view.documentView.frame) - 1 : NSMinY(clip.bounds) <= 1;
                CGFloat top = shown(view, page, .5, 0).y;
                check(fabs(top - NSMaxY(ink)) < 1.5 || (atEnd && top > NSMaxY(ink)),
                      [NSString stringWithFormat:@"the top of the page's content at the top (%.1f)", top]);
            }
            // The page beside it shows all of its content's width as well.
            PDFPage *next = [document pageAtIndex:other];
            check(shown(view, next, 0, .5).x <= NSMinX(beside) + slack && shown(view, next, 1, .5).x >= NSMaxX(beside) - slack,
                  @"the other page keeps its line ends");
        }
        [p.window close];
    }

    // One page at a time, and scroll bars that take room when they appear.
    context = @"single page with scroll bars";
    {
        PDFDocument *document = makeDocument(0, NSZeroRect);
        Preview p = makePreview(document, kPDFDisplaySinglePage);
        MyPDFKitView *view = p.lower;
        NSScrollView *scroll = view.documentView.enclosingScrollView;
        scroll.scrollerStyle = NSScrollerStyleLegacy;
        scroll.hasVerticalScroller = YES; scroll.hasHorizontalScroller = YES; scroll.autohidesScrollers = YES;
        show(view, 2);
        [view zoomToContentWidthOnly:YES]; settle(p.window);
        CGFloat width = NSWidth(clipOf(view).frame);
        check(view.scaleFactor * NSWidth(ink) <= width + 0.5,
              [NSString stringWithFormat:@"content %.1f within the view %.1f after a scroller appears", view.scaleFactor * NSWidth(ink), width]);
        check(fabs(shown(view, [document pageAtIndex:2], .5, 0).y - NSMaxY(ink)) < 1.5, @"top of the content at the top");
        [p.window close];
    }

    // A blank page leaves the magnification alone.
    context = @"blank page";
    {
        Preview p = makePreview(makeDocument(0, NSZeroRect), kPDFDisplaySinglePage);
        show(p.lower, 5);
        p.lower.scaleFactor = 0.7; p.field.integerValue = 70;
        [p.lower zoomToContentWidthOnly:YES]; [p.lower zoomToContentWidthOnly:NO]; settle(p.window);
        check(fabs(p.lower.scaleFactor - 0.7) < 0.001 && p.field.integerValue == 70, @"no change on a blank page");
        [p.window close];
    }

    // The toolbar group: two buttons that act on the active part.
    context = @"toolbar";
    {
        Preview p = makePreview(makeDocument(0, NSZeroRect), kPDFDisplaySinglePageContinuous);
        NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"PDFKit Toolbar Identifier"];
        toolbar.delegate = p.document;
        p.window.toolbar = toolbar; settle(p.window);
        NSToolbarItemGroup *group = (NSToolbarItemGroup *)toolbar.items.firstObject;
        check([group isKindOfClass:NSToolbarItemGroup.class] && group.subitems.count == 2 &&
              group.selectionMode == NSToolbarItemGroupSelectionModeMomentary &&
              group.controlRepresentation == NSToolbarItemGroupControlRepresentationExpanded, @"two buttons kept apart");
        NSArray *names = @[@"Zoom to Content", @"Zoom to Content Width"];
        for (NSUInteger i = 0; i < 2; i++)
            check([group.subitems[i].toolTip isEqual:names[i]] && [group.subitems[i].label isEqual:names[i]] && group.subitems[i].image,
                  @"names and symbols");
        check([group.paletteLabel isEqual:names[0]], @"name in Customize Toolbar");
        show(p.lower, 2); show(p.upper, 2);
        CGFloat upperScale = p.upper.scaleFactor;
        [p.document zoomPreviewToContent:group.subitems[1]]; settle(p.window);
        CGFloat width = NSWidth(clipOf(p.lower).frame);
        check(fabs(p.lower.scaleFactor * NSWidth(ink) - width) < width * 0.02, @"the second button fits the content width of the active part");
        check(p.upper.scaleFactor == upperScale, @"the other part is unchanged");
        group.selectedIndex = 0;
        [p.document zoomPreviewToContent:group]; settle(p.window);
        check(p.lower.scaleFactor * NSHeight(ink) <= NSHeight(clipOf(p.lower).frame) + 0.5, @"the first button fits the whole content");
        [p.window close];
    }
    printf("PASS: %lu checks\n", (unsigned long)checks);
    return 0;
}}
'''
program = (program.replace('ZOOMHEADER', zoom_text).replace('IDENTIFIER', identifier.group(1))
           .replace('VIEWMETHODS', view_text).replace('TOOLBARMETHODS', toolbar_text))
if not args.mutation:
    verify_embedded(program, fragments)
with tempfile.TemporaryDirectory() as temp:
    temp = Path(temp)
    (temp / 'test.m').write_text(program, encoding='utf-8')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'PDFKit',
                    '-I', str(root / 'Tests'), *include_args(root), str(temp / 'test.m'),
                    str(root / 'Sources/Preview/TSPreviewScrollerKeeper.m'), '-o', str(temp / 'test')], check=True)
    result = subprocess.run([str(temp / 'test')], capture_output=True, text=True)
    output = result.stdout + result.stderr
    if args.mutation:
        assert result.returncode != 0, 'mutation not detected: ' + args.mutation
        print('PASS: detected mutation ' + args.mutation + ': ' + output.strip().splitlines()[-1])
    else:
        print(output.strip())
        sys.exit(result.returncode)
