#!/usr/bin/env python3
"""Check that the split toolbar buttons show a side-by-side split while Option is held over them.

Compiles TSSplitToggleCue.h and the production split-button code of
TSToolbarController.m with a stand-in document and toolbar, and the Preview's
splitPdfKitWindow: with a stand-in window. Option held over the Split Source or
Split Preview button of a window that is not split shows the side-by-side symbol;
anything else (no Option, Command or Control with it, the pointer elsewhere, a split
window, a window that is not key) keeps the button's own image. The Window menu has
an Option alternate for Split Window in every language, a customized shortcut of
either command keeps its orientation in the Preview, and the button tool tips
mention Option-click in every language. Nothing is shown on screen and no user
settings are read.
"""
import argparse, json, re, subprocess, sys, tempfile
from pathlib import Path
from production_fragments import method as production_method, verify_embedded
from source_tree import include_args

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['split-ignored', 'no-hover', 'command-allowed',
                                           'menu-orientation-ignored', 'no-resign-reset', 'unturned'])
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

cue = span(toolbar, 'static char TSSplitToggleCueKey', '            return event;\n        }];\n    });\n}')
splitter = production_method(window_source, '- (void) splitPdfKitWindow: (id)sender')
fragments.append(('complete method:splitPdfKitWindow', window_source, splitter))

# Wiring that the compiled harness does not cover.
setup = production_method(toolbar, '- (void) setupToolbar')
assert setup.count('TSInstallSplitToggleOptionMonitor();') == 1, 'Every document window installs the Option monitor'
assert 'addLocalMonitorForEventsMatchingMask: NSEventMaskFlagsChanged' in cue
assert splitter.index('[self mainSplitPdfKitWindow];') < splitter.index('TSSplitToggleItemsFollowSplit();'), 'Preview buttons follow a split'
source_split = production_method(document, '- (void) splitWindow: sender')
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
for language, word in option_words.items():
    strings = subprocess.run(['plutil', '-convert', 'json', '-o', '-',
                              str(root/'Resources/Interfaces'/(language+'.lproj')/'ToolbarItems.strings')],
                             check=True, capture_output=True, text=True).stdout
    table = json.loads(strings)
    for key in ('tiToolTipSplit', 'tiToolTipSplitKIT'):
        assert word in table[key], 'Option-click in %s %s: %s' % (language, key, table[key])

if args.mutation == 'split-ignored':
    old = 'return TSSplitToggleOptionHeld(flags) && !windowIsSplit && pointerOverButton;'
    assert header.count(old) == 1
    header = header.replace(old, 'return TSSplitToggleOptionHeld(flags) && pointerOverButton;')
elif args.mutation == 'command-allowed':
    old = '(flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) == 0'
    assert header.count(old) == 1
    header = header.replace(old, '(flags & NSEventModifierFlagControl) == 0')
elif args.mutation == 'unturned':
    old = 'static NSString * const TSSplitToggleSideBySideSymbolName = @"rectangle.split.2x1";'
    assert header.count(old) == 1
    header = header.replace(old, 'static NSString * const TSSplitToggleSideBySideSymbolName = @"rectangle.split.1x2";')
elif args.mutation == 'no-hover':
    old = 'option && TSSplitTogglePointOnItem(window, item, point)'
    assert cue.count(old) == 1
    cue = cue.replace(old, 'option')
elif args.mutation == 'no-resign-reset':
    old = '[[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(windowResignedKey:)'
    assert cue.count(old) == 1
    cue = cue.replace(old, 'if (0) [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(windowResignedKey:)')
elif args.mutation == 'menu-orientation-ignored':
    old = '                sideBySide = [[sender identifier] isEqualToString:@"TSShortcut.splitWindow:.vertical"];'
    assert splitter.count(old) == 1
    splitter = splitter.replace(old, '                ;')

program = r'''
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "TSSplitToggleCue.h"
static NSString *kSplitID = @"Split";
static NSString *kSplitKKTID = @"SplitKIT";
static NSEventModifierFlags flags;
static NSEventModifierFlags currentFlags(id s, SEL c) { return flags; }
void TSSplitToggleItemsFollowSplit(void);

@interface PreviewWindow : NSObject
@property BOOL windowIsSplit, horizontal;
@property (strong) NSSplitView *pdfKitSplitView;
@property NSInteger splits;
@end
@implementation PreviewWindow
- (void) mainSplitPdfKitWindow { self.windowIsSplit = !self.windowIsSplit; self.splits++; }
SPLITTER
@end

@interface TSDocument : NSObject <NSToolbarDelegate>
@property (strong) PreviewWindow *pdfKitWindow;
@property BOOL isSplit;
@end
@implementation TSDocument
- (void)splitWindow:(id)sender {}
- (void)splitPreviewWindow:(id)sender {}
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)t { return @[kSplitID, kSplitKKTID]; }
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)t { return @[kSplitID, kSplitKKTID]; }
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
@property NSPoint pointer;
@end
@implementation KeyWindow
- (BOOL)isKeyWindow { return self.key; }
- (NSPoint)mouseLocationOutsideOfEventStream { return self.pointer; }
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
static NSUInteger CueAreas(NSView *view) {
    NSUInteger n = 0;
    for (NSTrackingArea *area in view.trackingAreas) if ([area.owner isKindOfClass:[TSSplitToggleCue class]]) n++;
    return n;
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    method_setImplementation(class_getClassMethod(NSEvent.class, @selector(modifierFlags)), (IMP)currentFlags);
    const NSEventModifierFlags O = NSEventModifierFlagOption, S = NSEventModifierFlagShift,
        C = NSEventModifierFlagCommand, K = NSEventModifierFlagControl;

    // When the button shows the side-by-side split.
    Check(TSSplitToggleShowsSideBySide(O, NO, YES) && TSSplitToggleShowsSideBySide(O | S, NO, YES), @"Option, with or without Shift");
    Check(!TSSplitToggleShowsSideBySide(0, NO, YES) && !TSSplitToggleShowsSideBySide(S, NO, YES), @"Not without Option");
    Check(!TSSplitToggleShowsSideBySide(O | C, NO, YES) && !TSSplitToggleShowsSideBySide(O | K, NO, YES), @"Not with Command or Control");
    Check(!TSSplitToggleShowsSideBySide(O, YES, YES), @"Not in a split window");
    Check(!TSSplitToggleShowsSideBySide(O, NO, NO), @"Not with the pointer elsewhere");

    // A window with both split buttons. AppKit draws each toolbar item with a button
    // that carries the item's target and action; stand-in buttons take that place.
    TSDocument *doc = [TSDocument new]; doc.pdfKitWindow = [PreviewWindow new];
    KeyWindow *w = [[KeyWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    NSToolbar *bar = [[NSToolbar alloc] initWithIdentifier:@"SplitToggleTest"]; bar.autosavesConfiguration = NO; bar.delegate = doc;
    w.toolbar = bar;
    NSToolbarItem *source = bar.items[0], *preview = bar.items[1];
    Check([source.itemIdentifier isEqual:kSplitID] && [preview.itemIdentifier isEqual:kSplitKKTID], @"Toolbar has both split items");
    NSImage *sourceImage = source.image, *previewImage = preview.image;
    NSButton *sourceButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, 20, 36, 36)];
    NSButton *previewButton = [[NSButton alloc] initWithFrame:NSMakeRect(80, 20, 36, 36)];
    sourceButton.target = doc; sourceButton.action = @selector(splitWindow:);
    previewButton.target = doc; previewButton.action = @selector(splitPreviewWindow:);
    [w.contentView addSubview:sourceButton]; [w.contentView addSubview:previewButton];
    NSPoint onSource = NSMakePoint(38, 38), onPreview = NSMakePoint(98, 38), elsewhere = NSMakePoint(300, 38), nearPreview = NSMakePoint(118, 38);
    NSView *frameView = w.contentView.superview;
    NSEvent *moved = [NSEvent mouseEventWithType:NSEventTypeMouseMoved location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:0 pressure:0];
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

    // Which button the pointer is on.
    Check(TSSplitTogglePointOnItem(w, preview, onPreview) && !TSSplitTogglePointOnItem(w, source, onPreview), @"Pointer on the preview button");
    Check(TSSplitTogglePointOnItem(w, source, onSource), @"Pointer on the source button");
    Check(!TSSplitTogglePointOnItem(w, preview, elsewhere) && !TSSplitTogglePointOnItem(w, preview, nearPreview), @"Pointer beside the buttons");
    NSView *cover = [[NSView alloc] initWithFrame:NSMakeRect(70, 10, 60, 60)]; [w.contentView addSubview:cover];
    Check(!TSSplitTogglePointOnItem(w, preview, onPreview), @"A view covering the button");
    [cover removeFromSuperview];
    previewButton.hidden = YES; Check(!TSSplitTogglePointOnItem(w, preview, onPreview), @"A hidden button"); previewButton.hidden = NO;

    // Option pressed with the pointer on the preview button of the key window.
    w.key = YES; w.pointer = onPreview; flags = O;
    TSSplitToggleOptionChanged(w, flags);
    Check([Pixels(preview.image) isEqual:sideBySide], @"Option over Split Preview shows the side-by-side split");
    Check(source.image == sourceImage, @"Split Source keeps its image");
    Check(CueAreas(frameView) == 1, @"The window follows the pointer while Option is held");
    NSTrackingArea *area = nil;
    for (NSTrackingArea *a in frameView.trackingAreas) if ([a.owner isKindOfClass:[TSSplitToggleCue class]]) area = a;
    // The pointer moves to Split Source, then leaves the window.
    w.pointer = onSource; [area.owner mouseMoved:moved];
    Check(preview.image == previewImage && [Pixels(source.image) isEqual:sideBySide], @"The side-by-side split follows the pointer");
    w.pointer = elsewhere; [area.owner mouseMoved:moved];
    Check(preview.image == previewImage && source.image == sourceImage, @"Pointer off the buttons");
    w.pointer = onPreview; [area.owner mouseEntered:moved];
    Check([Pixels(preview.image) isEqual:sideBySide], @"Pointer back on the button");
    [area.owner mouseExited:moved];
    Check(preview.image == previewImage, @"Pointer out of the window");
    // Command joins Option (dragging a toolbar item), then Option is released.
    [area.owner mouseEntered:moved]; flags = O | C; TSSplitToggleOptionChanged(w, flags);
    Check(preview.image == previewImage && CueAreas(frameView) == 0, @"Command with Option");
    flags = O; TSSplitToggleOptionChanged(w, flags);
    Check([Pixels(preview.image) isEqual:sideBySide] && CueAreas(frameView) == 1, @"Option again");
    flags = 0; TSSplitToggleOptionChanged(w, flags);
    Check(preview.image == previewImage && source.image == sourceImage && CueAreas(frameView) == 0, @"Option released");

    // In a split window the button unsplits: only the other window part's button turns.
    doc.pdfKitWindow.windowIsSplit = YES; flags = O; TSSplitToggleOptionChanged(w, flags);
    Check(preview.image == previewImage, @"Split preview keeps its image");
    w.pointer = onSource;
    for (NSTrackingArea *a in frameView.trackingAreas) if ([a.owner isKindOfClass:[TSSplitToggleCue class]]) area = a;
    [area.owner mouseMoved:moved];
    Check([Pixels(source.image) isEqual:sideBySide], @"Unsplit source turns while the preview is split");
    doc.isSplit = YES; [area.owner mouseMoved:moved];
    Check(source.image == sourceImage, @"Split source keeps its image");
    doc.isSplit = NO; doc.pdfKitWindow.windowIsSplit = NO; flags = 0; TSSplitToggleOptionChanged(w, flags);

    // After a click splits the window, the button shows what the next click does.
    w.pointer = onPreview; flags = O; TSSplitToggleOptionChanged(w, flags);
    Check([Pixels(preview.image) isEqual:sideBySide], @"Before the split");
    Check([NSApp.windows containsObject:w], @"The test window is one of the application's windows");
    doc.pdfKitWindow.windowIsSplit = YES; TSSplitToggleItemsFollowSplit();
    Check(preview.image == previewImage, @"After the split");
    doc.pdfKitWindow.windowIsSplit = NO; TSSplitToggleItemsFollowSplit();
    Check([Pixels(preview.image) isEqual:sideBySide], @"After unsplitting, with Option still held");

    // Another window becomes key while Option is held.
    w.key = NO; [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowDidResignKeyNotification object:w];
    Check(preview.image == previewImage && CueAreas(frameView) == 0, @"The window resigns key");
    TSSplitToggleOptionChanged(w, O);
    Check(preview.image == previewImage && CueAreas(frameView) == 0, @"Option in a window that is not key");
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
program = program.replace('SPLITTER', splitter).replace('CUE', cue)
if not args.mutation:
    verify_embedded(program, fragments)
with tempfile.TemporaryDirectory() as temp:
    temp = Path(temp)
    (temp/'TSSplitToggleCue.h').write_text(header)
    (temp/'test.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa', '-I', str(temp), '-I', str(root/'Tests'),
                    *include_args(root), str(temp/'test.m'), '-o', str(temp/'test')], check=True)
    result = subprocess.run([str(temp/'test')], capture_output=True, text=True)
    output = (result.stdout + result.stderr).strip()
    if args.mutation:
        assert result.returncode != 0, 'mutation not detected: ' + args.mutation
        print('PASS: detected mutation ' + args.mutation + ': ' + output.splitlines()[-1])
    else:
        print(output)
        sys.exit(result.returncode)
