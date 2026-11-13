#!/usr/bin/env python3
"""Check the Back/Forward item of the preview toolbars with production toolbar code.

The Back/Forward item of the Preview window (BackForthKIT) and of the single window
(BackForthKITSplit) shows the chevrons of Apple's Preview (chevron.backward and
chevron.forward), highlights a segment only while it is clicked, dims Back or Forward
when the preview has no page to go back or forward to, and sends Back or Forward to
the preview. Back and Forward each have their own translated tool tip ("Go Back" and
"Go Forward" in English), and the item has none of its own over them. VoiceOver reads
Back and Forward, and a text-only toolbar shows them as a submenu, in the words of the
language. The label does not use the words of Previous Page and Next Page (Dutch and
European Portuguese used to). Identifiers and command are unchanged, and a saved
toolbar draws the item where it was saved:
the item is not a navigational item, which macOS draws at the leading edge.
Nothing is shown on screen and no user settings are read.
"""
import argparse, os, plistlib, shutil, subprocess, sys, tempfile
from pathlib import Path
from production_fragments import method as production_method, verify_embedded
from source_tree import include_args, source_file

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['triangles', 'select-one', 'navigational', 'swapped', 'always-enabled', 'no-history-observer',
                                               'no-segment-tips', 'keep-item-tip', 'swapped-tips', 'english-menu',
                                               'english-accessibility', 'no-menu', 'swapped-menu', 'dutch-previous-next'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
toolbar = (root/'Sources/Windows/TSToolbarController.m').read_text()
document = source_file(root, 'TSDocument.m').read_text()

fragments = []
def method(source, signature):
    fragment = production_method(source, signature)
    fragments.append(('complete method:'+signature, source, fragment))
    return fragment
def span(first, last):
    start = toolbar.index(first); end = toolbar.index(last, start) + len(last)
    fragment = toolbar[start:end]
    fragments.append(('statements:'+first, toolbar, fragment))
    return fragment

constants = span('static NSString* \tkSourceToolbarIdentifier', 'kHtmlSearchTID              = @"HtmlSearch";')
item_class = span('@interface TSBackForwardToolbarItem : NSToolbarItem',
                  '    [control setEnabled: view.canGoForward forSegment: 1];\n}\n@end')
methods = '\n'.join(method(toolbar, s) for s in [
    '- (NSToolbarItem*) makeToolbarItemWithItemIdentifier:(NSString*)itemIdent key:(NSString*)itemKey\n{',
    '- (NSToolbarItem*) makeBackForthItemWithItemIdentifier:'])
commands = '\n'.join(method(document, s) for s in [
    '- (void)doBackForward:(id)sender', '- (void)doForward:(id)sender', '- (void)doBack:(id)sender'])

# Both preview toolbars take the item, with its menu for text-only toolbars, as the
# helper compiled below makes it.
item_for = production_method(toolbar, '- (NSToolbarItem *) toolbar: (NSToolbar *)toolbar itemForItemIdentifier:')
assert item_for.count('makeBackForthItemWithItemIdentifier') == 1
assert item_for.count('if ([itemIdent isEqual: kBackForthKKTID] || [itemIdent isEqual: skBackForthKKTID])\n'
                      '\t\treturn [self makeBackForthItemWithItemIdentifier: itemIdent key:itemIdent];') == 1
# No English words for Back and Forward are left in the toolbar code.
assert '@"Back"' not in toolbar and '@"Forward"' not in toolbar, 'Back and Forward come from ToolbarItems.strings'
assert 'arrowtriangle' not in toolbar, 'No triangle symbols left in the toolbar'
# A new document in a preview and a change of the active preview validate the item
# at once: both go through updatePreviewLayoutControls, which validates it.
update = production_method(toolbar, '- (void)updatePreviewLayoutControls')
assert update.count('if ([item isKindOfClass:[TSBackForwardToolbarItem class]]) {\n                [item validate];\n                continue;\n            }') == 1
kit = source_file(root, 'MyPDFKitView.m').read_text()
for signature in ('- (void)setDocument:(PDFDocument *)document', '- (void)becomeActiveView'):
    assert production_method(kit, signature).count('[self.myDocument updatePreviewLayoutControls];') == 1, signature

def mutate(old, new):
    global methods, item_class
    assert (methods + item_class).count(old) == 1, old
    methods = methods.replace(old, new); item_class = item_class.replace(old, new)
if args.mutation == 'triangles':
    mutate('@"chevron.backward"', '@"arrowtriangle.left.fill"'); mutate('@"chevron.forward"', '@"arrowtriangle.right.fill"')
elif args.mutation == 'select-one':
    mutate('trackingMode: NSSegmentSwitchTrackingMomentary', 'trackingMode: NSSegmentSwitchTrackingSelectOne')
elif args.mutation == 'navigational':
    mutate('    toolbarItem.document = self;\n', '    toolbarItem.document = self;\n    toolbarItem.navigational = YES;\n')
elif args.mutation == 'swapped':
    mutate('@[backImage, forwardImage]', '@[forwardImage, backImage]')
elif args.mutation == 'no-history-observer':
    mutate('            [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(previewHistoryChanged:) name: name object: nil];', '            ;')
elif args.mutation == 'no-segment-tips':
    mutate('    [control setToolTip: NSLocalizedStringFromTable(@"tiToolTipGoBack", @"ToolbarItems", nil) forSegment: 0];\n', '')
elif args.mutation == 'keep-item-tip':
    mutate('    toolbarItem.paletteLabel = textItem.paletteLabel;\n', '    toolbarItem.paletteLabel = textItem.paletteLabel;\n    toolbarItem.toolTip = textItem.toolTip;\n')
elif args.mutation == 'swapped-tips':
    mutate('@"tiToolTipGoBack", @"ToolbarItems", nil) forSegment: 0', '@"tiToolTipGoForward", @"ToolbarItems", nil) forSegment: 0')
elif args.mutation == 'english-menu':
    mutate('[submenu addItemWithTitle: back action:', '[submenu addItemWithTitle: @"Back" action:')
elif args.mutation == 'english-accessibility':
    mutate('accessibilityDescription: forward]', 'accessibilityDescription: @"Forward"]')
elif args.mutation == 'no-menu':
    mutate('    toolbarItem.menuFormRepresentation = menuFormRep;\n', '')
elif args.mutation == 'swapped-menu':
    mutate('action: @selector(doBack:)', 'action: @selector(doForward:)')
elif args.mutation == 'always-enabled':
    mutate('    [control setEnabled: view.canGoBack forSegment: 0];\n    [control setEnabled: view.canGoForward forSegment: 1];\n', '')

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import "TestAppKitIsolation.h"
#import "TSPreviewLayout.h"
#import "TSPreviewAppearance.h"
#define MITSU_PDF 1
static BOOL atLeastMonterey = YES;
CONSTANTS
@interface HistoryView : NSObject
@property NSMutableArray *log;
@property BOOL canGoBack, canGoForward;
@end
@implementation HistoryView
- (void)goBack:(id)sender { [self.log addObject:@"back"]; }
- (void)goForward:(id)sender { [self.log addObject:@"forward"]; }
@end
@interface PreviewWindow : NSObject
@property id activeView;
@end
@implementation PreviewWindow
@end
@interface TSDocument : NSObject <NSToolbarDelegate>
@property PreviewWindow *pdfKitWindow;
@end
ITEM_CLASS
@implementation TSDocument
METHODS
COMMANDS
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)ident willBeInsertedIntoToolbar:(BOOL)inserted
{
 if ([ident isEqual:kBackForthKKTID] || [ident isEqual:skBackForthKKTID]) return [self makeBackForthItemWithItemIdentifier:ident key:ident];
 NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:ident];
 item.view = [NSButton buttonWithTitle:ident target:nil action:nil]; item.label = ident;
 return item;
}
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar { return @[]; }
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar { return @[]; }
@end
static void Check(BOOL ok, NSString *message) { if (!ok) { NSLog(@"FAIL: %@", message); exit(1); } }
static NSString *Localized(NSString *key) { return [NSBundle.mainBundle localizedStringForKey:key value:@"MISSING" table:@"ToolbarItems"]; }
static NSData *Pixels(NSImage *image) {
 NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:32 pixelsHigh:32 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
 [NSGraphicsContext saveGraphicsState]; NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
 [image drawInRect:NSMakeRect(0, 0, 32, 32)]; [NSGraphicsContext restoreGraphicsState];
 return [NSData dataWithBytes:rep.bitmapData length:rep.bytesPerRow * 32];
}
static PDFDocument *Pages(NSUInteger count) {
 NSMutableData *data = [NSMutableData data]; CGRect box = CGRectMake(0, 0, 200, 200);
 CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
 CGContextRef context = CGPDFContextCreate(consumer, &box, NULL);
 for (NSUInteger n = 0; n < count; n++) { CGContextBeginPage(context, &box); CGContextFillRect(context, CGRectMake(10, 10, 20 + n, 20)); CGContextEndPage(context); }
 CGPDFContextClose(context); CGContextRelease(context); CGDataConsumerRelease(consumer);
 return [[PDFDocument alloc] initWithData:data];
}
static NSData *Symbol(NSString *name) { return Pixels([NSImage imageWithSystemSymbolName:name accessibilityDescription:nil]); }
static NSWindow *OffscreenWindow(void) {
 // Never ordered front: TSInstallAppKitIsolation turns window ordering into a no-op.
 NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
 window.releasedWhenClosed = NO; window.toolbarStyle = NSWindowToolbarStyleExpanded;
 return window;
}
// A real click on one segment, tracked by the control itself from queued mouse events.
static void Click(NSSegmentedControl *control, NSInteger segment) {
 NSWindow *window = OffscreenWindow(); [window.contentView addSubview:control];
 [control sizeToFit]; [control setFrameOrigin:NSMakePoint(20, 20)];
 NSRect frame = control.frame; NSPoint point = NSMakePoint(NSMinX(frame) + NSWidth(frame) * (segment ? 0.75 : 0.25), NSMidY(frame));
 NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
 NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:0];
 [NSApp postEvent:up atStart:YES];
 [control mouseDown:down];
}
int main(int argc, char **argv) { @autoreleasepool {
 TSInstallAppKitIsolation(); [NSApplication sharedApplication];
 NSString *language = @(argv[1]); NSUInteger checkedText = 0;
 Check([NSBundle.mainBundle.preferredLocalizations.firstObject isEqual:language], @"Requested localization");
 Check([NSBundle.mainBundle.bundleIdentifier hasPrefix:@"org.texshop.BackForwardTest."], @"Isolated test bundle");
 Check([kBackForthKKTID isEqual:@"BackForthKIT"] && [skBackForthKKTID isEqual:@"BackForthKITSplit"], @"Saved toolbar identifiers keep their spelling");
 TSDocument *d = [TSDocument new]; d.pdfKitWindow = [PreviewWindow new];
 HistoryView *view = [HistoryView new]; view.log = [NSMutableArray array]; d.pdfKitWindow.activeView = view;
 NSData *back = Symbol(@"chevron.backward"), *forward = Symbol(@"chevron.forward");
 Check(back && forward && ![back isEqual:forward], @"Chevron symbols available");
 for (NSString *ident in @[kBackForthKKTID, skBackForthKKTID]) {
  NSToolbarItem *item = [d makeBackForthItemWithItemIdentifier:ident key:ident];
  NSString *where = [NSString stringWithFormat:@"%@ %@", language, ident];
  Check([item.itemIdentifier isEqual:ident] && item.tag == 0, [@"Identifier and tag: " stringByAppendingString:where]);
  NSSegmentedControl *tipped = (NSSegmentedControl *)item.view;
  Check(item.toolTip.length == 0 && tipped.toolTip.length == 0, [NSString stringWithFormat:@"No tool tip of the item over Back and Forward: %@ (%@ / %@)", where, item.toolTip, tipped.toolTip]);
  NSArray *text = @[item.label, item.paletteLabel, [tipped toolTipForSegment:0] ?: @"", [tipped toolTipForSegment:1] ?: @"",
                    [tipped imageForSegment:0].accessibilityDescription ?: @"", [tipped imageForSegment:1].accessibilityDescription ?: @""];
  Check([text isEqual:@[Localized([@"tiLabel" stringByAppendingString:ident]), Localized([@"tiPaletteLabel" stringByAppendingString:ident]), Localized(@"tiToolTipGoBack"), Localized(@"tiToolTipGoForward"), Localized(@"tiBack"), Localized(@"tiForward")]], [NSString stringWithFormat:@"Text from its own keys: %@ %@", where, text]);
  for (NSString *one in text) Check(one.length && ![one isEqual:@"MISSING"] && ![one hasPrefix:@"ti"], [@"Real text: " stringByAppendingString:where]);
  Check(![text[2] isEqual:text[3]], [@"Back and Forward have different tool tips: " stringByAppendingString:where]);
  Check(![text[4] isEqual:text[5]], [@"Back and Forward have different names: " stringByAppendingString:where]);
  if (![language isEqual:@"en"]) for (NSUInteger n = 0; n < text.count; n++) Check(![text[n] isEqual:EXPECTED_TEXT[@"en"][n]], [NSString stringWithFormat:@"Translated: %@ %@", where, text[n]]);
  // The label does not use the words of the Previous Page and Next Page buttons.
  for (NSString *word in [item.label componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/／"]])
   for (NSString *key in @[@"tiLabelPreviousPageButtonKIT", @"tiLabelNextPageButtonKIT"])
    Check([word caseInsensitiveCompare:Localized(key)] != NSOrderedSame, [NSString stringWithFormat:@"Not the word of %@: %@ %@", key, where, item.label]);
  // VoiceOver reads the name of each segment.
  NSMutableArray *spoken = [NSMutableArray array];
  for (id segment in [tipped.cell accessibilityChildren]) [spoken addObject:[NSString stringWithFormat:@"%@ %@", [segment accessibilityRole], [segment accessibilityLabel]]];
  Check([spoken isEqual:@[[@"AXButton " stringByAppendingString:text[4]], [@"AXButton " stringByAppendingString:text[5]]]], [NSString stringWithFormat:@"VoiceOver names: %@ %@", where, spoken]);
  // A text-only toolbar shows the item as a submenu with Back and Forward.
  NSMenuItem *menuForm = item.menuFormRepresentation;
  Check([menuForm.title isEqual:item.label] && menuForm.submenu.numberOfItems == 2, [NSString stringWithFormat:@"Menu of a text-only toolbar: %@ %@", where, menuForm]);
  Check([[menuForm.submenu.itemArray valueForKey:@"title"] isEqual:@[text[4], text[5]]], [NSString stringWithFormat:@"Menu names: %@ %@", where, [menuForm.submenu.itemArray valueForKey:@"title"]]);
  for (NSMenuItem *entry in menuForm.submenu.itemArray) Check(entry.target == d && entry.keyEquivalent.length == 0 && !entry.hasSubmenu, [@"Menu targets: " stringByAppendingString:where]);
  [view.log removeAllObjects]; [menuForm.submenu performActionForItemAtIndex:0]; [menuForm.submenu performActionForItemAtIndex:1];
  Check([view.log isEqual:@[@"back", @"forward"]], [NSString stringWithFormat:@"Menu commands: %@ %@", where, view.log]);
  NSArray *expected = EXPECTED_TEXT[language];
  if (expected) { Check([text isEqual:expected], [NSString stringWithFormat:@"Exact text: %@ %@", where, text]); checkedText++; }
  Check(!item.navigational, [@"Not a navigational item: " stringByAppendingString:where]);
  Check([item isKindOfClass:TSBackForwardToolbarItem.class] && ((TSBackForwardToolbarItem *)item).document == d && item.autovalidates, [@"Validated by the toolbar: " stringByAppendingString:where]);
  Check([item.view isKindOfClass:NSSegmentedControl.class], [@"Segmented control: " stringByAppendingString:where]);
  NSSegmentedControl *control = (NSSegmentedControl *)item.view;
  Check(control.segmentCount == 2, [@"Two segments: " stringByAppendingString:where]);
  Check([Pixels([control imageForSegment:0]) isEqual:back] && [Pixels([control imageForSegment:1]) isEqual:forward], [@"Preview's chevrons: " stringByAppendingString:where]);
  Check(![Pixels([control imageForSegment:0]) isEqual:Symbol(@"arrowtriangle.left.fill")] && ![Pixels([control imageForSegment:1]) isEqual:Symbol(@"arrowtriangle.right.fill")], [@"No triangles: " stringByAppendingString:where]);
  Check([control labelForSegment:0].length == 0 && [control labelForSegment:1].length == 0, [@"Icons only: " stringByAppendingString:where]);
  Check(control.trackingMode == NSSegmentSwitchTrackingMomentary, [@"Highlighted only while clicked: " stringByAppendingString:where]);
  Check([control tagForSegment:0] == 0 && [control tagForSegment:1] == 1, [@"Segment tags as before (0, 1): " stringByAppendingString:where]);
  Check(control.target == d && control.action == @selector(doBackForward:), [@"Command unchanged: " stringByAppendingString:where]);
  // Clicking each segment goes back or forward once, and no segment stays selected.
  for (NSInteger segment = 0; segment < 2; segment++) {
   NSSegmentedControl *fresh = (NSSegmentedControl *)[d makeBackForthItemWithItemIdentifier:ident key:ident].view;
   [view.log removeAllObjects];
   Click(fresh, segment);
   Check([view.log isEqual:@[segment ? @"forward" : @"back"]], [NSString stringWithFormat:@"Click on segment %ld: %@ %@", (long)segment, where, view.log]);
   Check(fresh.selectedSegment == -1, [NSString stringWithFormat:@"No segment stays selected after a click: %@ %ld", where, (long)fresh.selectedSegment]);
  }
  // Back or Forward is dimmed when the active preview has no page to go back or forward to.
  for (int state = 0; state < 4; state++) {
   view.canGoBack = state & 1; view.canGoForward = (state & 2) != 0;
   [item validate];
   Check([control isEnabledForSegment:0] == view.canGoBack && [control isEnabledForSegment:1] == view.canGoForward, [NSString stringWithFormat:@"Dimmed when there is no page to go to: %@ back=%d forward=%d", where, view.canGoBack, view.canGoForward]);
  }
  HistoryView *other = [HistoryView new]; other.canGoBack = YES; d.pdfKitWindow.activeView = other;
  [item validate];
  Check([control isEnabledForSegment:0] && ![control isEnabledForSegment:1], [@"Follows the active preview: " stringByAppendingString:where]);
  d.pdfKitWindow.activeView = nil; [item validate];
  Check(![control isEnabledForSegment:0] && ![control isEnabledForSegment:1], [@"Dimmed without a preview: " stringByAppendingString:where]);
  d.pdfKitWindow.activeView = view;
  @autoreleasepool {
   TSDocument *gone = [TSDocument new];
   NSToolbarItem *orphan = [gone makeBackForthItemWithItemIdentifier:ident key:ident];
   gone = nil;
   [orphan validate];
   Check(((TSBackForwardToolbarItem *)orphan).document == nil && ![(NSSegmentedControl *)orphan.view isEnabledForSegment:0], [@"An item outliving its document stays dimmed: " stringByAppendingString:where]);
  }
  // A dimmed segment does nothing when clicked.
  view.canGoBack = NO; view.canGoForward = YES;
  {
   NSToolbarItem *dimmed = [d makeBackForthItemWithItemIdentifier:ident key:ident];
   [dimmed validate]; [view.log removeAllObjects];
   Click((NSSegmentedControl *)dimmed.view, 0);
   Check(view.log.count == 0, [NSString stringWithFormat:@"Dimmed Back does nothing: %@ %@", where, view.log]);
  }
  view.canGoBack = YES;
 }
 Check([Localized(@"tiLabelBackForthKIT") isEqual:Localized(@"tiLabelBackForthKITSplit")] && [Localized(@"tiPaletteLabelBackForthKIT") isEqual:Localized(@"tiPaletteLabelBackForthKITSplit")], @"Both windows show the same text");
 Check([Localized(@"tiToolTipBackForthKIT") isEqual:@"MISSING"] && [Localized(@"tiToolTipBackForthKITSplit") isEqual:@"MISSING"], @"The tool tip of the whole item is gone");
 Check(checkedText == 2, @"Exact text checked in every language");

 // A real preview: the item follows the preview's history as pages change, with no
 // other validation, and follows the preview that is active.
 for (NSString *ident in @[kBackForthKKTID, skBackForthKKTID]) {
  NSWindow *previewWindow = OffscreenWindow();
  PDFView *upper = [[PDFView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)], *lower = [[PDFView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
  [previewWindow.contentView addSubview:upper]; [previewWindow.contentView addSubview:lower];
  upper.document = Pages(4); lower.document = Pages(4);
  d.pdfKitWindow.activeView = upper;
  NSToolbarItem *live = [d makeBackForthItemWithItemIdentifier:ident key:ident];
  NSSegmentedControl *control = (NSSegmentedControl *)live.view;
  [live validate];
  NSString *where = [NSString stringWithFormat:@"%@ %@", language, ident];
  Check(!upper.canGoBack && !upper.canGoForward && ![control isEnabledForSegment:0] && ![control isEnabledForSegment:1], [@"New preview: both dimmed: " stringByAppendingString:where]);
  [upper goToPage:[upper.document pageAtIndex:2]];
  Check(upper.canGoBack && [control isEnabledForSegment:0] && ![control isEnabledForSegment:1], [NSString stringWithFormat:@"After going to a page, Back is available: %@ (%d %d)", where, upper.canGoBack, upper.canGoForward]);
  [upper goBack:nil];
  Check(upper.canGoForward && [control isEnabledForSegment:1] == upper.canGoForward && [control isEnabledForSegment:0] == upper.canGoBack, [NSString stringWithFormat:@"After going back, Forward is available: %@ (%d %d)", where, upper.canGoBack, upper.canGoForward]);
  // The other part of a split preview becomes active: its own history counts.
  d.pdfKitWindow.activeView = lower; [live validate];
  Check(![control isEnabledForSegment:0] && ![control isEnabledForSegment:1], [@"Follows the active part of a split preview: " stringByAppendingString:where]);
  d.pdfKitWindow.activeView = upper; [live validate];
  // A page change in the inactive part does not enable the active part's segments.
  [lower goToPage:[lower.document pageAtIndex:3]];
  Check([control isEnabledForSegment:0] == upper.canGoBack && [control isEnabledForSegment:1] == upper.canGoForward, [@"Inactive part does not count: " stringByAppendingString:where]);
  // A new document: the segments match the history PDFKit keeps for the view.
  PDFDocument *former = upper.document;
  upper.document = Pages(3); [live validate];
  Check([control isEnabledForSegment:0] == upper.canGoBack && [control isEnabledForSegment:1] == upper.canGoForward, [NSString stringWithFormat:@"New document: segments match the history: %@ (%d %d)", where, upper.canGoBack, upper.canGoForward]);
  d.pdfKitWindow.activeView = view;
  (void)former;
 }

 // Saved toolbars, loaded the way AppKit loads a saved configuration, draw the item
 // where it was saved, and save it back in the same place. Nothing is saved to disk.
 NSUInteger placed = 0;
 for (NSString *toolbarIdent in @[kPDFKitToolbarIdentifier, kFullWindowToolbarIdentifier]) {
  NSString *B = [toolbarIdent isEqual:kPDFKitToolbarIdentifier] ? kBackForthKKTID : skBackForthKKTID;
  NSString *F = NSToolbarFlexibleSpaceItemIdentifier;
  for (NSArray *saved in @[@[kPreviousPageButtonKKTID, kNextPageButtonKKTID, B, kDrawerKKTID, F, kSearchKKTID],
                           @[skTypesetTID, skProgramTID, kPreviousPageButtonKKTID, kNextPageButtonKKTID, B, kDrawerKKTID],
                           @[kDrawerKKTID, kPreviousPageButtonKKTID, F, B],
                           @[kPreviousPageButtonKKTID, B, kNextPageButtonKKTID]]) {
   NSToolbar *bar = [[NSToolbar alloc] initWithIdentifier:toolbarIdent]; bar.autosavesConfiguration = NO; bar.delegate = d;
   NSWindow *window = OffscreenWindow(); window.toolbar = bar;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
   [bar setConfigurationFromDictionary:@{@"TB Item Identifiers": saved, @"TB Display Mode": @1, @"TB Is Shown": @YES, @"TB Size Mode": @1}];
   NSString *where = [NSString stringWithFormat:@"%@ %@", toolbarIdent, [saved componentsJoinedByString:@","]];
   Check([[bar.items valueForKey:@"itemIdentifier"] isEqual:saved], [@"Saved toolbar loads as saved: " stringByAppendingString:where]);
   Check([bar.configurationDictionary[@"TB Item Identifiers"] isEqual:saved], [@"Configuration to save is unchanged: " stringByAppendingString:where]);
#pragma clang diagnostic pop
   [window.contentView.superview layoutSubtreeIfNeeded]; [window layoutIfNeeded];
   CGFloat last = -1; NSUInteger drawn = 0;
   for (NSToolbarItem *item in bar.items) {
    if (!item.view) continue;
    Check(item.view.window == window, [@"Item drawn in the toolbar: " stringByAppendingString:where]);
    CGFloat x = [item.view convertRect:item.view.bounds toView:nil].origin.x;
    Check(x > last, [NSString stringWithFormat:@"Drawn in the saved order: %@ (%@ at %.0f after %.0f)", where, item.itemIdentifier, x, last]);
    last = x; drawn++;
   }
   Check(drawn == [saved indexesOfObjectsPassingTest:^BOOL(id o, NSUInteger i, BOOL *s) { return ![o isEqual:F]; }].count, [@"Every item drawn: " stringByAppendingString:where]);
   // The toolbar itself dims the item.
   view.canGoBack = NO; view.canGoForward = YES;
   [bar validateVisibleItems];
   NSToolbarItem *shown = bar.items[[saved indexOfObject:B]];
   Check([bar.visibleItems containsObject:shown], [@"Item visible: " stringByAppendingString:where]);
   Check(![(NSSegmentedControl *)shown.view isEnabledForSegment:0] && [(NSSegmentedControl *)shown.view isEnabledForSegment:1], [@"Toolbar validation dims Back: " stringByAppendingString:where]);
   view.canGoBack = YES; view.canGoForward = NO;
   [bar validateVisibleItems];
   Check([(NSSegmentedControl *)shown.view isEnabledForSegment:0] && ![(NSSegmentedControl *)shown.view isEnabledForSegment:1], [@"Toolbar validation dims Forward: " stringByAppendingString:where]);
   view.canGoBack = YES; view.canGoForward = YES;
   placed++;
  }
 }
 Check(placed == 8, @"All saved toolbars checked");
 NSLog(@"%@ PASS: Back/Forward shows Preview's chevrons with their own tool tips and translated names and menu, highlights only while clicked, is dimmed with no page to go to, keeps its labels, command and saved place", language);
}}
'''
# Label, palette label, the tool tips of Back and Forward, and the names of Back and
# Forward that VoiceOver reads and the menu of a text-only toolbar shows. They use the
# words of Back and Forward in the Preview menu. Dutch uses the words of Back and
# Forward in Apple's Preview and in TeXShop's Settings window (Terug, Vooruit), since its
# Preview menu uses Vorige and Volgende, the label of Previous Page and Next Page. In
# European Portuguese Anterior and Seguinte also name Previous Page and Next Page.
expected = {
    'en': [('Back/Forward', 'Back/Forward', 'Go Back', 'Go Forward', 'Back', 'Forward')] * 2,
    'de': [('Zurück/Vorwärts', 'Zurück/Vorwärts', 'Zurück', 'Vorwärts', 'Zurück', 'Vorwärts')] * 2,
    'es': [('Atrás/Adelante', 'Atrás/Adelante', 'Atrás', 'Adelante', 'Atrás', 'Adelante')] * 2,
    'fr': [('Revenir/Avancer', 'Revenir/Avancer', 'Revenir', 'Avancer', 'Revenir', 'Avancer')] * 2,
    'it': [('Indietro/Avanti', 'Indietro/Avanti', 'Indietro', 'Avanti', 'Indietro', 'Avanti')] * 2,
    'ja': [('戻る／進む', '戻る／進む', '戻る', '進む', '戻る', '進む')] * 2,
    'ko': [('뒤로/앞으로', '뒤로/앞으로', '뒤로', '앞으로', '뒤로', '앞으로')] * 2,
    'nl': [('Terug/Vooruit', 'Terug/Vooruit', 'Terug', 'Vooruit', 'Terug', 'Vooruit')] * 2,
    'pt-PT': [('Retroceder/Avançar', 'Retroceder/Avançar', 'Retroceder', 'Avançar', 'Retroceder', 'Avançar')] * 2,
    'pt': [('Voltar/Avançar', 'Voltar/Avançar', 'Voltar', 'Avançar', 'Voltar', 'Avançar')] * 2,
    'ro': [('Înapoi/Înainte', 'Înapoi/Înainte', 'Înapoi', 'Înainte', 'Înapoi', 'Înainte')] * 2,
    'zh_CN': [('返回/前进', '返回/前进', '返回', '前进', '返回', '前进')] * 2,
}
objc = lambda text: '@"' + text.replace('\\', '\\\\').replace('"', '\\"') + '"'
table = '@{' + ', '.join('@"%s": @[%s]' % (language, ', '.join(map(objc, items[0])))
                         for language, items in expected.items()) + '}'
languages = sorted(p.parent.stem for p in (root/'Resources/Interfaces').glob('*.lproj/ToolbarItems.strings'))
assert len(languages) == 12 and set(expected) == set(languages), languages
program = program.replace('CONSTANTS', constants).replace('METHODS', methods).replace('COMMANDS', commands).replace('ITEM_CLASS', item_class).replace('EXPECTED_TEXT', table)
if not args.mutation:
    verify_embedded(program, fragments)
with tempfile.TemporaryDirectory(prefix='TeXShop-back-forward-') as tmp:
    tmp = Path(tmp)
    app = tmp/'BackForwardTest.app'; mac = app/'Contents/MacOS'; mac.mkdir(parents=True)
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'org.texshop.BackForwardTest.'+tmp.name,
        'CFBundleExecutable': 'BackForwardTest', 'CFBundlePackageType': 'APPL', 'LSUIElement': True, 'CFBundleDevelopmentRegion': 'en'}))
    for language in languages:
        res = app/f'Contents/Resources/{language}.lproj'; res.mkdir(parents=True)
        shutil.copy(root/f'Resources/Interfaces/{language}.lproj/ToolbarItems.strings', res)
    if args.mutation == 'dutch-previous-next':
        strings = app/'Contents/Resources/nl.lproj/ToolbarItems.strings'
        strings.write_text(strings.read_text().replace('"Terug/Vooruit"', '"Vorige/Volgende"'))
    source = tmp/'Test.m'; source.write_text(program)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-w', *include_args(root), '-I'+str(root/'Tests'),
                    '-framework', 'Cocoa', str(source), '-o', str(mac/'BackForwardTest')], check=True)
    home = tmp/'Home'; (home/'Library/Preferences').mkdir(parents=True)
    try:
        for language in languages:
            result = subprocess.run([str(mac/'BackForwardTest'), language, '-AppleLanguages', f'({language})'],
                                    env={**os.environ, 'CFFIXED_USER_HOME': str(home)}, capture_output=True, text=True)
            sys.stderr.write(result.stderr)
            if result.returncode:
                sys.exit(result.returncode)
    finally:
        subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister', '-u', str(app)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
