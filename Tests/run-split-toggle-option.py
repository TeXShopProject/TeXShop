#!/usr/bin/env python3
"""Check that the split toolbar buttons show a side-by-side split while Option is held.

Compiles TSSplitToggleCue.h and the production split-button code of
TSToolbarController.m with a stand-in document and toolbar, and the Preview's
splitPdfKitWindow: with a stand-in window. Option held in a window with the Split Source or
Split Preview button of a window that is not split shows the side-by-side symbol,
wherever the pointer is; anything else (no Option, Command or Control with it, a window
that is not key) keeps the button's own image. A window that becomes key with Option
held shows it, one that resigns key does not. A split window shows how it is split,
whatever the modifiers, also on a button added to the toolbar later,
and its tool tip and spoken name tell that a click unsplits. The Window menu has
an Option alternate for Split Window in every language, a customized shortcut of
either command keeps its orientation in the Preview, and the button tool tips
mention Option-click in every language. With pages one below the other, the
Split Preview button's tool tip also mentions Shift-click (#66), and follows a change of
the display format; in the other display formats it does not. Nothing is shown on screen and no user
settings are read.
"""
import argparse, json, re, subprocess, sys, tempfile
from pathlib import Path
from production_fragments import method as production_method, verify_embedded
from source_tree import include_args

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['split-ignored', 'no-become-key', 'command-allowed', 'key-ignored', 'no-flags-monitor', 'no-catch-up', 'catch-up-default-mode-only', 'monitor-not-recorded',
                                           'menu-orientation-ignored', 'no-resign-reset', 'unturned',
                                           'split-shows-own-image', 'source-orientation-ignored', 'added-item-unturned',
                                           'added-item-condition-negated', 'split-tool-tip-kept', 'added-source-unturned',
                                           'shift-tip-everywhere', 'shift-tip-never', 'shift-tip-on-source'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
toolbar = (root/'Sources/Windows/TSToolbarController.m').read_text()
window_source = (root/'Sources/Windows/TSPreviewWindow.m').read_text()
document = (root/'Sources/Document/TSDocument.m').read_text()
header = (root/'Sources/Windows/TSSplitToggleCue.h').read_text()

fragments = []
def span(source, first, last):
    start = source.index(first); end = source.index(last, start) + len(last)
    fragment = source[start:end]
    fragments.append(('statements:'+first, source, fragment))
    return fragment

cue = span(toolbar, 'static char TSSplitToggleSideBySideKey', '                    TSSplitToggleItemsFollow(window, NSEvent.modifierFlags);\n            }];\n    });\n}')
splitter = production_method(window_source, '- (void) splitPdfKitWindow: (id)sender')
fragments.append(('complete method:splitPdfKitWindow', window_source, splitter))

# Wiring that the compiled harness does not cover.
setup = production_method(toolbar, '- (void) setupToolbar')
assert setup.count('TSInstallSplitToggleOptionMonitor();') == 1, 'Every document window installs the Option monitor'
assert 'addLocalMonitorForEventsMatchingMask: NSEventMaskFlagsChanged' in cue
assert splitter.index('[self mainSplitPdfKitWindow];') < splitter.index('TSSplitToggleItemsFollowSplit();'), 'Preview buttons follow a split'
source_split = production_method(document, '- (void) splitWindow: sender')
side_by_side = production_method(document, '- (BOOL) isSplitSideBySide')
assert 'return windowIsSplit && [splitView isVertical];' in side_by_side, 'The source tells a side-by-side split'
will_add = production_method(toolbar, '- (void) toolbarWillAddItem: (NSNotification *) notif')
layout_controls = production_method(toolbar, '- (void)updatePreviewLayoutControls')
assert layout_controls.rstrip().endswith('TSSplitToggleItemsFollowSplit();\n}'), 'The Split Preview tool tip follows a change of the display format'
assert source_split.rstrip().endswith('TSSplitToggleItemsFollowSplit();\n}'), 'Source buttons follow a split'
for ident, action in (('kSplitID', 'splitWindow:'), ('kSplitKKTID', 'splitPreviewWindow:')):
    branch = toolbar[toolbar.index('if ([itemIdent isEqual: %s])' % ident):]
    branch = branch[:branch.index('}')]
    assert 'symbolName: @"rectangle.split.1x2"' in branch and '@selector(%s)' % action in branch, ident + ' shows the top-and-bottom split'

# The Window menu: Split Window and its Option alternate, in every language.
nibs = sorted((root/'Resources/Interfaces').glob('*.lproj/MainMenu.nib/designable.nib'))
assert len(nibs) == 12, 'MainMenu in 12 languages'
for nib in nibs:
    text = nib.read_text()
    plain = re.search(r'<menuItem title="[^"]+" keyEquivalent="2" id="[^"]+" identifier="TSShortcut\.splitWindow:\.0">\s*'
                      r'<modifierMask key="keyEquivalentModifierMask" control="YES"/>\s*<connections>\s*'
                      r'<action selector="splitWindow:"[^>]*/>\s*</connections>\s*</menuItem>\s*', text)
    assert plain, 'Split Window in ' + nib.parent.parent.name
    alternate = re.match(r'<menuItem title="[^"]+" alternate="YES" keyEquivalent="2" id="[^"]+" identifier="TSShortcut\.splitWindow:\.vertical">\s*'
                         r'<modifierMask key="keyEquivalentModifierMask" control="YES" option="YES"/>\s*<connections>\s*'
                         r'<action selector="splitWindow:"', text[plain.end():])
    assert alternate, 'Split Window Vertically right after Split Window as its Option alternate in ' + nib.parent.parent.name

# Tool tips: both split buttons mention Option-click in every language.
option_words = {'en': 'Option-click', 'de': 'Option-Taste-Klicken', 'es': 'tecla Opción', 'fr': 'touche Option',
                'it': 'tasto Opzione', 'ja': 'Option+クリック', 'ko': 'Option-클릭', 'nl': 'Option + klik',
                'pt': 'tecla Option', 'pt-PT': 'tecla Opção', 'ro': 'Opțiune-clic', 'zh_CN': '按住Option键点按'}
shift_words = {'en': 'Shift-click', 'de': 'Umschalttaste', 'es': 'Mayúsculas', 'fr': 'touche Maj',
               'it': 'tasto Maiuscole', 'ja': 'Shift+クリック', 'ko': 'Shift-클릭', 'nl': 'Shift + klik',
               'pt': 'tecla Shift', 'pt-PT': 'tecla Shift', 'ro': 'Shift-clic', 'zh_CN': '按住Shift键点按'}
for language, word in option_words.items():
    strings = subprocess.run(['plutil', '-convert', 'json', '-o', '-',
                              str(root/'Resources/Interfaces'/(language+'.lproj')/'ToolbarItems.strings')],
                             check=True, capture_output=True, text=True).stdout
    table = json.loads(strings)
    for key in ('tiToolTipSplit', 'tiToolTipSplitKIT', 'tiToolTipSplitKITContinuous'):
        assert word in table[key], 'Option-click in %s %s: %s' % (language, key, table[key])
    # Shift-click only with pages one below the other (#66).
    shift = shift_words[language]
    assert shift in table['tiToolTipSplitKITContinuous'], 'Shift-click in %s: %s' % (language, table['tiToolTipSplitKITContinuous'])
    for key in ('tiToolTipSplit', 'tiToolTipSplitKIT'):
        assert shift not in table[key], 'No Shift-click in %s %s: %s' % (language, key, table[key])
    for key in ('tiToolTipUnsplit', 'tiToolTipUnsplitKIT'):
        assert table.get(key) and word not in table[key] and table[key] != table[key.replace('Unsplit', 'Split')], \
            'Unsplit tool tip in %s %s' % (language, key)

added_first = '    // A split button added to a split window'
added_last = 'TSSplitToggleItemsFollowSplit(); });\n'
added = span(toolbar, added_first, added_last)
assert added in will_add, 'The split branch is in toolbarWillAddItem:'
if args.mutation == 'added-item-unturned':
    added = added.replace('dispatch_async(dispatch_get_main_queue(), ^{ TSSplitToggleItemsFollowSplit(); });', ';')
elif args.mutation == 'added-item-condition-negated':
    added = added.replace('if ([[addedItem', 'if (!([[addedItem').replace('kSplitKKTID])\n', 'kSplitKKTID]))\n')
elif args.mutation == 'added-source-unturned':
    old = 'if ([[addedItem itemIdentifier] isEqual: kSplitID] || '
    assert added.count(old) == 1
    added = added.replace(old, 'if (')
elif args.mutation == 'split-tool-tip-kept':
    old = '    if (windowIsSplit)\n        return preview ?'
    assert header.count(old) == 1
    header = header.replace(old, '    if (0)\n        return preview ?')

if args.mutation == 'shift-tip-everywhere':
    old = '    if (preview && continuousPages)\n'
    assert header.count(old) == 1
    header = header.replace(old, '    if (preview)\n')
elif args.mutation == 'shift-tip-never':
    old = '    if (preview && continuousPages)\n'
    assert header.count(old) == 1
    header = header.replace(old, '    if (0)\n')
elif args.mutation == 'shift-tip-on-source':
    old = '    if (preview && continuousPages)\n'
    assert header.count(old) == 1
    header = header.replace(old, '    if (continuousPages || (preview && continuousPages))\n')

if args.mutation == 'split-ignored':
    old = '    if (windowIsSplit)\n        return splitSideBySide;\n'
    assert header.count(old) == 1
    header = header.replace(old, '')
elif args.mutation == 'split-shows-own-image':
    old = '        return splitSideBySide;'
    assert header.count(old) == 1
    header = header.replace(old, '        return NO;')
elif args.mutation == 'source-orientation-ignored':
    old = ': document.isSplitSideBySide;'
    assert cue.count(old) == 1
    cue = cue.replace(old, ': NO;')
elif args.mutation == 'command-allowed':
    old = '(flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) == 0'
    assert header.count(old) == 1
    header = header.replace(old, '(flags & NSEventModifierFlagControl) == 0')
elif args.mutation == 'unturned':
    old = 'static NSString * const TSSplitToggleSideBySideSymbolName = @"rectangle.split.2x1";'
    assert header.count(old) == 1
    header = header.replace(old, 'static NSString * const TSSplitToggleSideBySideSymbolName = @"rectangle.split.1x2";')
elif args.mutation == 'no-become-key':
    old = '@[NSWindowDidBecomeKeyNotification, NSWindowDidResignKeyNotification]'
    assert cue.count(old) == 1
    cue = cue.replace(old, '@[NSWindowDidResignKeyNotification]')
elif args.mutation == 'no-resign-reset':
    old = '@[NSWindowDidBecomeKeyNotification, NSWindowDidResignKeyNotification]'
    assert cue.count(old) == 1
    cue = cue.replace(old, '@[NSWindowDidBecomeKeyNotification]')
elif args.mutation == 'key-ignored':
    old = 'NSEventModifierFlags held = window.isKeyWindow ? flags : 0;'
    assert cue.count(old) == 1
    cue = cue.replace(old, 'NSEventModifierFlags held = flags;')
elif args.mutation == 'no-catch-up':
    old = '        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, kCFRunLoopCommonModes);\n'
    assert cue.count(old) == 1
    cue = cue.replace(old, '')
elif args.mutation == 'catch-up-default-mode-only':
    old = 'CFRunLoopAddObserver(CFRunLoopGetMain(), observer, kCFRunLoopCommonModes);'
    assert cue.count(old) == 1
    cue = cue.replace(old, 'CFRunLoopAddObserver(CFRunLoopGetMain(), observer, kCFRunLoopDefaultMode);')
elif args.mutation == 'monitor-not-recorded':
    old = '        TSSplitToggleShownHeld = TSSplitToggleOptionHeld(flags);\n    }\n'
    assert cue.count(old) == 1
    cue = cue.replace(old, '    }\n')
elif args.mutation == 'no-flags-monitor':
    old = '                TSSplitToggleItemsFollow(window, event.modifierFlags);\n            return event;'
    assert cue.count(old) == 1
    cue = cue.replace(old, '                ;\n            return event;')
elif args.mutation == 'menu-orientation-ignored':
    old = '                sideBySide = [[sender identifier] isEqualToString:@"TSShortcut.splitWindow:.vertical"];'
    assert splitter.count(old) == 1
    splitter = splitter.replace(old, '                ;')

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "TSSplitToggleCue.h"
static NSString *kSplitID = @"Split";
static NSString *kSplitKKTID = @"SplitKIT";
static NSEventModifierFlags flags;
static NSEventModifierFlags currentFlags(id s, SEL c) { return flags; }
static NSWindow *keyWin;
static NSWindow *currentKeyWindow(id s, SEL c) { return keyWin.isKeyWindow ? keyWin : nil; }
void TSSplitToggleItemsFollowSplit(void);

@interface PreviewWindow : NSObject
@property BOOL windowIsSplit, horizontal;
@property (strong) NSSplitView *pdfKitSplitView;
@property (strong) PDFView *myPDFKitView;
@property NSInteger splits;
@end
@implementation PreviewWindow
- (void) mainSplitPdfKitWindow { self.windowIsSplit = !self.windowIsSplit; self.splits++; }
SPLITTER
@end

@interface TSDocument : NSObject <NSToolbarDelegate>
@property (strong) PreviewWindow *pdfKitWindow;
@property BOOL isSplit, isSplitSideBySide;
@end
@implementation TSDocument
- (void)splitWindow:(id)sender {}
- (void)splitPreviewWindow:(id)sender {}
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)t { return @[kSplitID, kSplitKKTID]; }
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)t { return @[kSplitID, kSplitKKTID]; }
- (void)toolbarWillAddItem:(NSNotification *)notif
{
    NSToolbarItem *addedItem = [[notif userInfo] objectForKey: @"item"];
ADDED}
- (NSToolbarItem *)toolbar:(NSToolbar *)t itemForItemIdentifier:(NSString *)ident willBeInsertedIntoToolbar:(BOOL)inserted
{
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:ident];
    item.image = [NSImage imageWithSystemSymbolName:@"rectangle.split.1x2" accessibilityDescription:ident];
    item.target = self;
    item.action = [ident isEqual:kSplitID] ? @selector(splitWindow:) : @selector(splitPreviewWindow:);
    return item;
}
@end

@interface KeyWindow : NSWindow
@property BOOL key;
@end
@implementation KeyWindow
- (BOOL)isKeyWindow { return self.key; }
@end

CUE

static NSUInteger checks;
static void Check(BOOL ok, NSString *message) { checks++; if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); } }
static NSData *Pixels(NSImage *image) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:32 pixelsHigh:32 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState]; NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [image drawInRect:NSMakeRect(0, 0, 32, 32)]; [NSGraphicsContext restoreGraphicsState];
    return [NSData dataWithBytes:rep.bitmapData length:rep.bytesPerRow * 32];
}
// Option pressed or released: a flagsChanged event through the application, as AppKit
// delivers it to the key window.
static void Press(NSWindow *window, NSEventModifierFlags f) {
    flags = f;
    [NSApp sendEvent:[NSEvent keyEventWithType:NSEventTypeFlagsChanged location:NSZeroPoint modifierFlags:f timestamp:0
                                  windowNumber:window.windowNumber context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:58]];
}
static void Key(KeyWindow *window, BOOL key) {
    window.key = key;
    [[NSNotificationCenter defaultCenter] postNotificationName:key ? NSWindowDidBecomeKeyNotification : NSWindowDidResignKeyNotification object:window];
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    method_setImplementation(class_getClassMethod(NSEvent.class, @selector(modifierFlags)), (IMP)currentFlags);
    method_setImplementation(class_getInstanceMethod(NSApplication.class, @selector(keyWindow)), (IMP)currentKeyWindow);
    const NSEventModifierFlags O = NSEventModifierFlagOption, S = NSEventModifierFlagShift,
        C = NSEventModifierFlagCommand, K = NSEventModifierFlagControl;

    // When the button shows the side-by-side split.
    Check(TSSplitToggleShowsSideBySide(O, NO, NO) && TSSplitToggleShowsSideBySide(O | S, NO, NO), @"Option, with or without Shift");
    Check(!TSSplitToggleShowsSideBySide(0, NO, NO) && !TSSplitToggleShowsSideBySide(S, NO, NO), @"Not without Option");
    Check(!TSSplitToggleShowsSideBySide(O | C, NO, NO) && !TSSplitToggleShowsSideBySide(O | K, NO, NO), @"Not with Command or Control");
    Check(!TSSplitToggleShowsSideBySide(O, YES, NO) && !TSSplitToggleShowsSideBySide(0, YES, NO), @"Not in a window split top and bottom");
    Check(TSSplitToggleShowsSideBySide(0, YES, YES) && TSSplitToggleShowsSideBySide(O, YES, YES) &&
          TSSplitToggleShowsSideBySide(O | C, YES, YES), @"In a window split side by side, whatever the modifiers");

    // A window with both split buttons. AppKit draws each toolbar item with a button
    // that carries the item's target and action; stand-in buttons take that place.
    TSDocument *doc = [TSDocument new]; doc.pdfKitWindow = [PreviewWindow new];
    doc.pdfKitWindow.myPDFKitView = [PDFView new]; doc.pdfKitWindow.myPDFKitView.displayMode = kPDFDisplaySinglePage;
    KeyWindow *w = [[KeyWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    NSToolbar *bar = [[NSToolbar alloc] initWithIdentifier:@"SplitToggleTest"]; bar.autosavesConfiguration = NO; bar.delegate = doc;
    w.toolbar = bar;
    NSToolbarItem *source = bar.items[0], *preview = bar.items[1];
    Check([source.itemIdentifier isEqual:kSplitID] && [preview.itemIdentifier isEqual:kSplitKKTID], @"Toolbar has both split items");
    NSImage *sourceImage = source.image, *previewImage = preview.image;
    NSData *sideBySide = Pixels(TSSplitToggleSideBySideImage(previewImage));
    Check(![Pixels(previewImage) isEqual:sideBySide], @"The two images differ");
    // The side-by-side image is the SF symbol rectangle.split.2x1, so that the
    // toolbar draws it as it draws the button's own symbol.
    NSImage *turned = TSSplitToggleSideBySideImage(previewImage);
    NSImage *split = [NSImage imageWithSystemSymbolName:@"rectangle.split.2x1" accessibilityDescription:nil];
    Check(split && [Pixels(turned) isEqual:Pixels(split)], @"The side-by-side image is rectangle.split.2x1");
    Check(turned.template && [turned.accessibilityDescription isEqual:previewImage.accessibilityDescription], @"Template image with the same description");
    Check(NSEqualSizes(turned.size, previewImage.size),
          [NSString stringWithFormat:@"The same size as the button's own symbol: %@ and %@", NSStringFromSize(turned.size), NSStringFromSize(previewImage.size)]);

    TSInstallSplitToggleOptionMonitor(); keyWin = w;
    // The toolbar's own update after adding its items runs first.
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    Check(w.windowNumber > 0 && [NSApp windowWithWindowNumber:w.windowNumber] == w, @"The window has a number for its events");

    // Option pressed in the key window: both buttons show the side-by-side split,
    // wherever the pointer is.
    Key(w, YES); Press(w, O);
    Check([Pixels(preview.image) isEqual:sideBySide] && [Pixels(source.image) isEqual:sideBySide], @"Option shows the side-by-side split on both buttons");
    Press(w, O | S);
    Check([Pixels(preview.image) isEqual:sideBySide], @"Shift with Option");
    // Command joins Option (dragging a toolbar item), then Option is released.
    Press(w, O | C);
    Check(preview.image == previewImage && source.image == sourceImage, @"Command with Option");
    Press(w, O);
    Check([Pixels(preview.image) isEqual:sideBySide], @"Option again");
    Press(w, 0);
    Check(preview.image == previewImage && source.image == sourceImage, @"Option released");
    // The window stops being key while Option is held, and becomes key again.
    Press(w, O); Key(w, NO);
    Check(preview.image == previewImage && source.image == sourceImage, @"A window that resigns key shows its own images");
    Key(w, YES);
    Check([Pixels(preview.image) isEqual:sideBySide], @"A window that becomes key with Option held shows the side-by-side split");
    Press(w, 0);

    // A tracking loop, such as the magnifying glass or a menu, takes the flagsChanged
    // events itself: the buttons catch up while the loop waits for events, and after it.
    Check(preview.image == previewImage, @"Before the tracking loop");
    flags = O; CFRunLoopRunInMode((CFStringRef)NSEventTrackingRunLoopMode, 0.05, false);
    Check([Pixels(preview.image) isEqual:sideBySide] && [Pixels(source.image) isEqual:sideBySide], @"Option pressed during a tracking loop");
    flags = 0; CFRunLoopRunInMode((CFStringRef)NSEventTrackingRunLoopMode, 0.05, false);
    Check(preview.image == previewImage && source.image == sourceImage, @"Option released during a tracking loop");
    flags = O; CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    Check([Pixels(preview.image) isEqual:sideBySide], @"Option pressed while no event reached the monitor, after the loop");
    flags = 0; CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    Check(preview.image == previewImage, @"Option released while no event reached the monitor, after the loop");
    // Option pressed through the monitor, then released inside a tracking loop that
    // takes the event, without a wait in between; and the other way round.
    Press(w, O); flags = 0; CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    Check(preview.image == previewImage && source.image == sourceImage, @"Option pressed through the monitor and released in a tracking loop");
    flags = O; CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    Press(w, 0); flags = O; CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    Check([Pixels(preview.image) isEqual:sideBySide] && [Pixels(source.image) isEqual:sideBySide], @"Option released through the monitor and pressed in a tracking loop");
    Press(w, 0);

    // In a split window the button unsplits: only the other window part's button turns.
    doc.pdfKitWindow.pdfKitSplitView = [NSSplitView new];
    doc.pdfKitWindow.windowIsSplit = YES; Press(w, O);
    Check(preview.image == previewImage, @"Split preview keeps its image");
    Check([Pixels(source.image) isEqual:sideBySide], @"Unsplit source turns while the preview is split");
    doc.isSplit = YES; Press(w, O);
    Check(source.image == sourceImage, @"Split source keeps its image");
    doc.isSplit = NO; doc.pdfKitWindow.windowIsSplit = NO; Press(w, 0);

    // A window split side by side shows that split, with or without Option, and after
    // the window resigns key.
    doc.pdfKitWindow.pdfKitSplitView.vertical = YES; doc.pdfKitWindow.windowIsSplit = YES;
    TSSplitToggleItemsFollowSplit();
    Check([Pixels(preview.image) isEqual:sideBySide] && source.image == sourceImage, @"Preview split side by side");
    Press(w, O);
    Check([Pixels(preview.image) isEqual:sideBySide], @"Option in a window split side by side");
    Press(w, 0);
    Check([Pixels(preview.image) isEqual:sideBySide], @"Option released in a window split side by side");
    Key(w, NO); w.key = YES;
    Check([Pixels(preview.image) isEqual:sideBySide], @"A window split side by side that resigns key");
    doc.isSplit = YES; doc.isSplitSideBySide = YES; TSSplitToggleItemsFollowSplit();
    Check([Pixels(source.image) isEqual:sideBySide], @"Source split side by side");
    // Tool tips and spoken names: a click on the button of a split window unsplits.
    Check([preview.toolTip isEqual:TSSplitToggleToolTip(YES, YES, NO)] && [source.toolTip isEqual:TSSplitToggleToolTip(NO, YES, NO)] &&
          [preview.image.accessibilityDescription isEqual:preview.toolTip] && [source.image.accessibilityDescription isEqual:source.toolTip],
          @"Split windows tell that a click unsplits");
    Check(![TSSplitToggleToolTip(YES, YES, NO) isEqual:TSSplitToggleToolTip(YES, NO, NO)] && ![TSSplitToggleToolTip(NO, YES, NO) isEqual:TSSplitToggleToolTip(NO, NO, NO)],
          @"The unsplit tool tips differ from the split ones");
    // The Split Preview button is taken out of the toolbar and put back while the
    // window is split side by side: once in the toolbar it shows that split.
    [bar removeItemAtIndex:1]; [bar insertItemWithItemIdentifier:kSplitKKTID atIndex:1];
    NSToolbarItem *again = bar.items[1];
    Check([again.itemIdentifier isEqual:kSplitKKTID] && again != preview, @"The button is put back");
    for (int i = 0; i < 5; i++) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
    Check([Pixels(again.image) isEqual:sideBySide] && [again.toolTip isEqual:TSSplitToggleToolTip(YES, YES, NO)],
          @"A button put back into a window split side by side shows that split");
    preview = again;
    // The same with the Split Source button of a source split side by side.
    Check(doc.isSplit && doc.isSplitSideBySide, @"The source is split side by side");
    [bar removeItemAtIndex:0]; [bar insertItemWithItemIdentifier:kSplitID atIndex:0];
    NSToolbarItem *sourceAgain = bar.items[0];
    Check([sourceAgain.itemIdentifier isEqual:kSplitID] && sourceAgain != source, @"The source button is put back");
    for (int i = 0; i < 5; i++) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
    Check([Pixels(sourceAgain.image) isEqual:sideBySide] && [sourceAgain.toolTip isEqual:TSSplitToggleToolTip(NO, YES, NO)] &&
          [sourceAgain.image.accessibilityDescription isEqual:sourceAgain.toolTip],
          @"A Split Source button put back into a source split side by side shows that split");
    source = sourceAgain;
    doc.isSplitSideBySide = NO; doc.pdfKitWindow.pdfKitSplitView.vertical = NO; TSSplitToggleItemsFollowSplit();
    Check([Pixels(source.image) isEqual:Pixels(sourceImage)] && [Pixels(preview.image) isEqual:Pixels(previewImage)], @"Split again top and bottom");
    doc.isSplit = NO; doc.pdfKitWindow.windowIsSplit = NO; TSSplitToggleItemsFollowSplit();
    Check([Pixels(source.image) isEqual:Pixels(sourceImage)] && [Pixels(preview.image) isEqual:Pixels(previewImage)], @"Unsplit");
    Check([preview.toolTip isEqual:TSSplitToggleToolTip(YES, NO, NO)] && [source.toolTip isEqual:TSSplitToggleToolTip(NO, NO, NO)] &&
          [preview.image.accessibilityDescription isEqual:preview.toolTip], @"Unsplit windows tell how to split");
    previewImage = preview.image; sourceImage = source.image;

    // Shift-click with pages one below the other (#66): only on the Split Preview button
    // of a window that is not split, and following the display format.
    PDFDisplayMode modes[] = {kPDFDisplaySinglePageContinuous, kPDFDisplayTwoUpContinuous, kPDFDisplaySinglePage, kPDFDisplayTwoUp};
    for (unsigned i = 0; i < 4; i++) {
        BOOL continuous = i < 2;
        doc.pdfKitWindow.myPDFKitView.displayMode = modes[i]; TSSplitToggleItemsFollowSplit();
        Check([preview.toolTip isEqual:TSSplitToggleToolTip(YES, NO, continuous)] && [preview.image.accessibilityDescription isEqual:preview.toolTip] &&
              [source.toolTip isEqual:TSSplitToggleToolTip(NO, NO, NO)],
              [NSString stringWithFormat:@"The Split Preview tool tip follows display format %u", i]);
        doc.pdfKitWindow.windowIsSplit = YES; TSSplitToggleItemsFollowSplit();
        Check([preview.toolTip isEqual:TSSplitToggleToolTip(YES, YES, NO)], [NSString stringWithFormat:@"A split window unsplits in display format %u", i]);
        doc.pdfKitWindow.windowIsSplit = NO; TSSplitToggleItemsFollowSplit();
    }
    Check(![TSSplitToggleToolTip(YES, NO, YES) isEqual:TSSplitToggleToolTip(YES, NO, NO)] &&
          [TSSplitToggleToolTip(NO, NO, YES) isEqual:TSSplitToggleToolTip(NO, NO, NO)] &&
          [TSSplitToggleToolTip(YES, YES, YES) isEqual:TSSplitToggleToolTip(YES, YES, NO)],
          @"Shift-click only on the Split Preview button of a window that is not split");
    doc.pdfKitWindow.myPDFKitView.displayMode = kPDFDisplaySinglePage; TSSplitToggleItemsFollowSplit();

    // After a click splits the window, the button shows what the next click does.
    Press(w, O);
    Check([Pixels(preview.image) isEqual:sideBySide], @"Before the split");
    Check([NSApp.windows containsObject:w], @"The test window is one of the application's windows");
    doc.pdfKitWindow.windowIsSplit = YES; TSSplitToggleItemsFollowSplit();
    Check(preview.image == previewImage, @"After the split");
    doc.pdfKitWindow.windowIsSplit = NO; TSSplitToggleItemsFollowSplit();
    Check([Pixels(preview.image) isEqual:sideBySide], @"After unsplitting, with Option still held");

    // Another window becomes key while Option is held.
    Key(w, NO);
    Check(preview.image == previewImage, @"The window resigns key");
    Press(w, 0); Press(w, O);
    Check(preview.image == previewImage, @"Option in a window that is not key");
    flags = 0;

    // The Preview's splitPdfKitWindow: Option splits side by side; a menu command
    // keeps its own orientation whatever its customized shortcut.
    PreviewWindow *p = [PreviewWindow new]; p.pdfKitSplitView = [NSSplitView new];
    NSMenuItem *plain = [NSMenuItem new]; plain.identifier = @"TSShortcut.splitWindow:.0";
    NSMenuItem *vertical = [NSMenuItem new]; vertical.identifier = @"TSShortcut.splitWindow:.vertical";
    struct { NSEventModifierFlags flags; id sender; BOOL sideBySide; const char *what; } cases[] = {
        {0, nil, NO, "toolbar click"}, {O, nil, YES, "toolbar Option-click"},
        {0, plain, NO, "Split Window"}, {O, vertical, YES, "Split Window Vertically with Option"},
        {0, vertical, YES, "Split Window Vertically on a shortcut without Option"},
        {O, plain, NO, "Split Window on a shortcut with Option"}};
    for (unsigned i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        p.pdfKitSplitView.vertical = !cases[i].sideBySide;
        flags = cases[i].flags; [p splitPdfKitWindow:cases[i].sender]; flags = 0;
        Check(p.windowIsSplit && p.pdfKitSplitView.isVertical == cases[i].sideBySide && p.horizontal == !cases[i].sideBySide, @(cases[i].what));
        BOOL wasVertical = p.pdfKitSplitView.isVertical;
        flags = cases[i].flags ^ O; [p splitPdfKitWindow:cases[i].sender]; flags = 0;
        Check(!p.windowIsSplit && p.pdfKitSplitView.isVertical == wasVertical, [@"Unsplit keeps the orientation: " stringByAppendingString:@(cases[i].what)]);
    }
    [w close];
    printf("PASS: %lu checks\n", (unsigned long)checks);
    return 0;
}}
'''
program = program.replace('SPLITTER', splitter).replace('CUE', cue).replace('ADDED', added)
if not args.mutation:
    verify_embedded(program, fragments)
with tempfile.TemporaryDirectory() as temp:
    temp = Path(temp)
    (temp/'TSSplitToggleCue.h').write_text(header)
    (temp/'test.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'PDFKit', '-I', str(temp), '-I', str(root/'Tests'),
                    *include_args(root), str(temp/'test.m'), '-o', str(temp/'test')], check=True)
    result = subprocess.run([str(temp/'test')], capture_output=True, text=True)
    output = (result.stdout + result.stderr).strip()
    if args.mutation:
        assert result.returncode != 0, 'mutation not detected: ' + args.mutation
        print('PASS: detected mutation ' + args.mutation + ': ' + output.splitlines()[-1])
    else:
        print(output)
        sys.exit(result.returncode)
