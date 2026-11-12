#!/usr/bin/env python3
"""Check the preview toolbar's previous/next page items with production toolbar code.

The customization lists and default sets offer one pair of page items (document
arrows). Toolbars saved with the former arrow-only identifiers still show working
document-arrow items. Toolbars saved with both pairs, or with the arrow-only pair,
keep one pair under the document arrow identifiers when the window is set up.
Nothing is shown on screen and no user settings are read.
"""
import argparse, os, plistlib, re, shutil, subprocess, sys, tempfile
from pathlib import Path
from production_fragments import method as production_method, verify_embedded
from source_tree import include_args

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['legacy-allowed', 'legacy-default', 'no-legacy-map', 'symbol-key',
                                           'keep-duplicates', 'keep-arrow-only-ident', 'keep-last'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
toolbar = (root/'Sources/Windows/TSToolbarController.m').read_text()

fragments = []
def method(signature):
    fragment = production_method(toolbar, signature)
    fragments.append(('complete method:'+signature, toolbar, fragment))
    return fragment
def span(first, last):
    start = toolbar.index(first); end = toolbar.index(last, start) + len(last)
    fragment = toolbar[start:end]
    fragments.append(('statements:'+first, toolbar, fragment))
    return fragment

constants = span('static NSString* \tkSourceToolbarIdentifier', 'kHtmlSearchTID              = @"HtmlSearch";')
signatures = ['static NSString *TSPreviewPageItemKey(NSString *itemIdent)',
              '- (NSToolbarItem*) makeToolbarItemWithItemIdentifier:(NSString*)itemIdent key:(NSString*)itemKey\n{',
              '- (NSToolbarItem*) makeToolbarItemWithItemIdentifier:(NSString*)itemIdent key:(NSString*)itemKey imageName:',
              '- (NSToolbarItem*) makeToolbarItemWithItemIdentifier:(NSString*)itemIdent key:(NSString*)itemKey image:',
              '- (NSToolbarItem*) makeToolbarSymbolsItemWithItemIdentifier:',
              '- (NSToolbarItem *)makePreviewPageItemWithItemIdentifier:',
              '- (void)keepOnePreviewPagePairInToolbar:',
              '- (void)doPreviousPageKK:', '- (void)doNextPageKK:',
              '- (NSArray *) toolbarDefaultItemIdentifiers:', '- (NSArray *) toolbarAllowedItemIdentifiers:',
              '- (BOOL) validateToolbarItem:']
methods = '\n'.join(method(s) for s in signatures)

# The full delegate method needs the whole document; check that it routes every
# page identifier through the helper compiled below.
item_for = production_method(toolbar, '- (NSToolbarItem *) toolbar: (NSToolbar *)toolbar itemForItemIdentifier:')
route = '    toolbarItem = [self makePreviewPageItemWithItemIdentifier:itemIdent];\n    if (toolbarItem)\n        return toolbarItem;'
assert item_for.count(route) == 1, 'itemForItemIdentifier routes page items through the helper'
for name in ('kPreviousPageKKTID', 'kNextPageKKTID', 'kPreviousPageButtonKKTID', 'kNextPageButtonKKTID'):
    assert name not in item_for, 'No other branch builds the preview page item '+name
# Every document window cleans up both preview toolbars once they are attached,
# before the layout items are inserted at fixed places.
setup = production_method(toolbar, '- (void) setupToolbar')
attach = ('    [[self fullSplitWindow] setToolbar: [self makeToolbar: kFullWindowToolbarIdentifier]];\n'
          '    [self keepOnePreviewPagePairInToolbar: self.pdfKitWindow.toolbar];\n'
          '    [self keepOnePreviewPagePairInToolbar: [[self fullSplitWindow] toolbar]];\n')
assert setup.count(attach) == 1 and setup.count('keepOnePreviewPagePairInToolbar') == 2, 'setupToolbar keeps one page pair in both preview toolbars'
assert setup.index(attach) < setup.index('TSPreviewAppearanceToolbarInstalled-') < setup.index('TSPreviewLayoutControlsInstalled-')
assert setup.index('[self.pdfKitWindow setToolbar: [self makeToolbar: kPDFKitToolbarIdentifier]];') < setup.index(attach)
# The arrow-only symbols remain only on the PDFView toolbar used for JPEG/TIFF images.
for symbol in ('@"arrow.up"', '@"arrow.down"'):
    for m in re.finditer(re.escape(symbol), toolbar):
        before = toolbar[:m.start()]
        branch = before[before.rindex('if ([itemIdent isEqual: '):]
        assert re.match(r'if \(\[itemIdent isEqual: k(Previous|Next)Page(Button)?TID\]', branch), 'Arrow-only symbol outside the PDFView toolbar'

if args.mutation == 'legacy-allowed':
    old = '\t\t\t\t\tkNextPageButtonKKTID,\n\t\t\t\t\tkBackForthKKTID,'
    assert old in methods
    methods = methods.replace(old, '\t\t\t\t\tkNextPageButtonKKTID,\n\t\t\t\t\tkPreviousPageKKTID,\n\t\t\t\t\tkNextPageKKTID,\n\t\t\t\t\tkBackForthKKTID,')
elif args.mutation == 'legacy-default':
    old = '                     kPreviousPageButtonKKTID,\n                     kNextPageButtonKKTID,\n                     kDrawerKKTID,'
    assert methods.count(old) == 2
    methods = methods.replace(old, '                     kPreviousPageKKTID,\n                     kNextPageKKTID,\n                     kDrawerKKTID,')
elif args.mutation == 'no-legacy-map':
    old = '    if ([itemIdent isEqual: kPreviousPageKKTID])\n        return kPreviousPageButtonKKTID;'
    assert methods.count(old) == 1
    methods = methods.replace(old, '')
elif args.mutation == 'symbol-key':
    old = 'return [self makeToolbarItemWithItemIdentifier:itemIdent key:itemKey\n                                                     image:symbolImage'
    assert methods.count(old) == 1
    methods = methods.replace(old, 'return [self makeToolbarItemWithItemIdentifier:itemIdent key:itemIdent\n                                                     image:symbolImage')
elif args.mutation == 'keep-duplicates':
    old = '            [extra addIndex: index];'
    assert methods.count(old) == 1
    methods = methods.replace(old, '            ;')
elif args.mutation == 'keep-arrow-only-ident':
    old = '            [toolbar removeItemAtIndex: index];\n            [toolbar insertItemWithItemIdentifier: itemKey atIndex: index];'
    assert methods.count(old) == 1
    methods = methods.replace(old, '            ;')
elif args.mutation == 'keep-last':
    old = '    for (NSUInteger index = 0; index < items.count; index++) {\n        NSString *itemKey'
    assert methods.count(old) == 1
    methods = methods.replace(old, '    for (NSUInteger index = items.count; index-- > 0;) {\n        NSString *itemKey')

program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSPreviewLayout.h"
#import "TSPreviewAppearance.h"
#define MITSU_PDF 1
static NSUserDefaults *defaults;
#define SUD defaults
static NSString *SwitchSidesKey = @"SwitchSides";
static BOOL atLeastMonterey = YES;
static BOOL sharing = YES;
enum { isTeX = 0, isOther = 1, isPDF = 2, isJPG = 4, isTIFF = 5 };
CONSTANTS
@interface PageView : NSObject
@property NSInteger previous, next;
@end
@implementation PageView
- (void)previousPage:(id)sender { self.previous++; }
- (void)nextPage:(id)sender { self.next++; }
@end
@interface TSDocument : NSObject <NSToolbarDelegate, NSToolbarItemValidation> { @public BOOL fileIsTex; }
@property NSInteger documentType;
@property PageView *view;
@end
@implementation TSDocument
- (BOOL)sharingExists { return sharing; }
- (PageView *)pdfKitView { return self.view; }
METHODS
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)ident willBeInsertedIntoToolbar:(BOOL)inserted
{ return [self makePreviewPageItemWithItemIdentifier:ident] ?: [[NSToolbarItem alloc] initWithItemIdentifier:ident]; }
@end
static void Check(BOOL ok, NSString *message) { if (!ok) { NSLog(@"FAIL: %@", message); exit(1); } }
static NSUInteger Count(NSArray *list, NSString *ident) { return [list indexesOfObjectsPassingTest:^BOOL(id o, NSUInteger i, BOOL *s) { return [o isEqual:ident]; }].count; }
static NSData *Pixels(NSImage *image) {
 NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:32 pixelsHigh:32 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
 [NSGraphicsContext saveGraphicsState]; NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
 [image drawInRect:NSMakeRect(0, 0, 32, 32)]; [NSGraphicsContext restoreGraphicsState];
 return [NSData dataWithBytes:rep.bitmapData length:rep.bytesPerRow * 32];
}
static NSString *Localized(NSString *key) { return [NSBundle.mainBundle localizedStringForKey:key value:@"MISSING" table:@"ToolbarItems"]; }
int main(int argc, char **argv) { @autoreleasepool {
 TSInstallAppKitIsolation(); [NSApplication sharedApplication];
 NSString *language = @(argv[1]); NSUInteger checkedText = 0;
 Check([NSBundle.mainBundle.preferredLocalizations.firstObject isEqual:language], @"Requested localization");
 Check([NSBundle.mainBundle.bundleIdentifier hasPrefix:@"org.texshop.ToolbarPageTest."], @"Isolated test bundle");
 defaults = [TSMemoryDefaults new];
 TSDocument *d = [TSDocument new]; d.view = [PageView new]; d.documentType = isPDF; d->fileIsTex = YES;
 NSArray *legacy = @[kPreviousPageKKTID, kNextPageKKTID], *current = @[kPreviousPageButtonKKTID, kNextPageButtonKKTID];
 Check([legacy isEqual:@[@"PreviousPageKIT", @"NextPageKIT"]] && [current isEqual:@[@"PreviousPageButtonKIT", @"NextPageButtonKIT"]], @"Saved toolbar identifiers keep their spelling");

 // A configuration saved with both pairs, loaded the way AppKit loads a saved
 // configuration: the configuration AppKit saves afterwards, and another window
 // with that toolbar, keep one pair. Nothing is saved to disk here.
 for (NSString *ident in @[kPDFKitToolbarIdentifier, kFullWindowToolbarIdentifier]) {
  NSArray *saved = @[legacy[0], legacy[1], current[0], current[1], kDrawerKKTID, NSToolbarPrintItemIdentifier];
  NSArray *kept = @[current[0], current[1], kDrawerKKTID, NSToolbarPrintItemIdentifier];
  NSToolbar *bar = [[NSToolbar alloc] initWithIdentifier:ident]; bar.autosavesConfiguration = NO; bar.delegate = d;
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
  window.releasedWhenClosed = NO; window.toolbar = bar;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  [bar setConfigurationFromDictionary:@{@"TB Item Identifiers": saved, @"TB Display Mode": @2, @"TB Is Shown": @YES, @"TB Size Mode": @1}];
  Check([[bar.items valueForKey:@"itemIdentifier"] isEqual:saved], @"Saved toolbar with both pairs loads as saved");
  [d keepOnePreviewPagePairInToolbar:bar];
  Check([[bar.items valueForKey:@"itemIdentifier"] isEqual:kept], @"One pair kept in the open window");
  Check([bar.configurationDictionary[@"TB Item Identifiers"] isEqual:kept], [NSString stringWithFormat:@"Configuration to save keeps one pair: %@", bar.configurationDictionary]);
  Check([bar.configurationDictionary[@"TB Display Mode"] isEqual:@2], @"Other toolbar settings kept");
#pragma clang diagnostic pop
  NSToolbar *again = [[NSToolbar alloc] initWithIdentifier:ident]; again.autosavesConfiguration = NO; again.delegate = d;
  NSWindow *other = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
  other.releasedWhenClosed = NO; other.toolbar = again;
  Check([[again.items valueForKey:@"itemIdentifier"] isEqual:kept], [NSString stringWithFormat:@"Another window with that toolbar shows one pair: %@", [again.items valueForKey:@"itemIdentifier"]]);
 }

 // Customization lists and default sets: one pair, the document arrows.
 NSUInteger lists = 0;
 for (NSString *ident in @[kPDFKitToolbarIdentifier, kFullWindowToolbarIdentifier]) for (int share = 0; share < 2; share++) for (int swap = 0; swap < 2; swap++) {
  sharing = share; [defaults setBool:swap forKey:SwitchSidesKey];
  NSToolbar *bar = [[NSToolbar alloc] initWithIdentifier:ident];
  NSArray *allowed = [d toolbarAllowedItemIdentifiers:bar], *standard = [d toolbarDefaultItemIdentifiers:bar];
  NSString *where = [NSString stringWithFormat:@"%@ sharing=%d swap=%d", ident, share, swap];
  for (NSString *page in legacy) {
   Check(Count(allowed, page) == 0, [@"Arrow-only item not offered: " stringByAppendingString:where]);
   Check(Count(standard, page) == 0, [@"Arrow-only item not in default set: " stringByAppendingString:where]);
  }
  for (NSString *page in current) {
   Check(Count(allowed, page) == 1, [@"Document arrow item offered once: " stringByAppendingString:where]);
   Check(Count(standard, page) == 1, [@"Document arrow item in default set: " stringByAppendingString:where]);
  }
  NSUInteger pageItems = 0;
  for (NSString *item in allowed) {
   NSToolbarItem *made = [d makePreviewPageItemWithItemIdentifier:item];
   if (made) { pageItems++; Check([current containsObject:item], @"Only the document arrow page items are offered"); }
  }
  Check(pageItems == 2, [@"Exactly two page items offered: " stringByAppendingString:where]);
  lists++;
 }
 Check(lists == 8, @"All preview and single-window variants checked");
 // The old PDFView toolbar (JPEG/TIFF images) has its own items and is unchanged here.
 NSArray *imageAllowed = [d toolbarAllowedItemIdentifiers:[[NSToolbar alloc] initWithIdentifier:kPDFToolbarIdentifier]];
 for (NSString *page in [legacy arrayByAddingObjectsFromArray:current]) Check(Count(imageAllowed, page) == 0, @"Image toolbar has no PDFKit page items");

 // Former identifiers produce the document arrow item with the same text and command.
 NSData *upArrow = Pixels([NSImage imageWithSystemSymbolName:@"arrow.up" accessibilityDescription:nil]);
 NSData *downArrow = Pixels([NSImage imageWithSystemSymbolName:@"arrow.down" accessibilityDescription:nil]);
 for (NSUInteger n = 0; n < 2; n++) {
  NSToolbarItem *now = [d makePreviewPageItemWithItemIdentifier:current[n]], *old = [d makePreviewPageItemWithItemIdentifier:legacy[n]];
  Check(now && old, @"Both identifiers make an item");
  Check([old.itemIdentifier isEqual:legacy[n]] && [now.itemIdentifier isEqual:current[n]], @"Items keep the requested identifier");
  NSString *key = current[n];
  Check([now.label isEqual:Localized([@"tiLabel" stringByAppendingString:key])], @"Document arrow label");
  Check([old.label isEqual:now.label] && [old.paletteLabel isEqual:now.paletteLabel] && [old.toolTip isEqual:now.toolTip], @"Former item shows the document arrow text");
  for (NSString *text in @[old.label, old.paletteLabel, old.toolTip])
   Check(![text isEqual:@"MISSING"] && ![text hasPrefix:@"ti"] && ![text isEqual:legacy[n]] && ![text isEqual:current[n]] && text.length > 0, @"Former item has real text");
  NSArray *text = EXPECTED_TEXT[language][n];
  if (text) Check([@[old.label, old.paletteLabel, old.toolTip] isEqual:text], [NSString stringWithFormat:@"Exact %@ text: %@ / %@ / %@", language, old.label, old.paletteLabel, old.toolTip]);
  if (text) checkedText++;
  Check([Pixels(old.image) isEqual:Pixels(now.image)], @"Former item shows the document arrow icon");
  Check([Pixels(now.image) isEqual:Pixels([NSImage imageWithSystemSymbolName:n ? @"arrow.down.doc" : @"arrow.up.doc" accessibilityDescription:nil])], @"Document arrow symbol");
  Check(![Pixels(old.image) isEqual:n ? downArrow : upArrow], @"Former item no longer shows the arrow-only icon");
  Check(old.target == d && old.action == now.action && now.action == (n ? @selector(doNextPageKK:) : @selector(doPreviousPageKK:)), @"Same command");
 }

 // A toolbar saved with the former identifiers, loaded the way AppKit loads a saved configuration.
 for (NSString *ident in @[kPDFKitToolbarIdentifier, kFullWindowToolbarIdentifier]) {
  NSToolbar *bar = [[NSToolbar alloc] initWithIdentifier:ident]; bar.autosavesConfiguration = NO; bar.delegate = d;
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
  window.releasedWhenClosed = NO; window.toolbar = bar;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  [bar setConfigurationFromDictionary:@{@"TB Item Identifiers": legacy, @"TB Display Mode": @1, @"TB Is Shown": @YES, @"TB Size Mode": @1}];
#pragma clang diagnostic pop
  Check([[bar.items valueForKey:@"itemIdentifier"] isEqual:legacy], @"Saved former items stay in the toolbar");
  for (NSToolbarItem *item in bar.items) Check(item.image && item.label.length && [Pixels(item.image) isEqual:Pixels([d makePreviewPageItemWithItemIdentifier:TSPreviewPageItemKey(item.itemIdentifier)].image)], @"Saved former item is not empty");
  NSInteger previous = d.view.previous, next = d.view.next;
  for (NSToolbarItem *item in bar.items) Check([NSApp sendAction:item.action to:item.target from:item], @"Former item sends its command");
  Check(d.view.previous == previous + 1 && d.view.next == next + 1, @"Former items turn the preview page");
  // Enabled exactly like the document arrow items: always for TeX sources, otherwise only for a PDF.
  NSArray *made = @[[d makePreviewPageItemWithItemIdentifier:current[0]], [d makePreviewPageItemWithItemIdentifier:current[1]]];
  for (int tex = 0; tex < 2; tex++) for (NSNumber *type in @[@(isPDF), @(isJPG), @(isTIFF)]) {
   d->fileIsTex = tex; d.documentType = type.integerValue;
   for (NSUInteger n = 0; n < 2; n++) {
    BOOL expected = tex || type.integerValue == isPDF;
    Check([d validateToolbarItem:bar.items[n]] == expected && [d validateToolbarItem:made[n]] == expected, @"Former and document arrow items are enabled alike");
   }
  }
  d->fileIsTex = YES; d.documentType = isPDF;
 }
 Check(checkedText == (EXPECTED_TEXT[language] ? 2 : 0), @"Exact text checked where listed");

 // Saved toolbars with both pairs (shown as the same buttons twice), or with the
 // arrow-only pair, keep the first previous and the first next page item in place
 // under the document arrow identifiers. Other items keep their order.
 NSString *P = current[0], *N = current[1], *p = legacy[0], *n = legacy[1];
 NSString *B = kBackForthKKTID, *D = kDrawerKKTID, *R = NSToolbarPrintItemIdentifier, *F = NSToolbarFlexibleSpaceItemIdentifier;
 NSArray *cases = @[
  @[@[p, n, P, N, B, D], @[P, N, B, D]],
  @[@[P, N, p, n, B, D], @[P, N, B, D]],
  @[@[P, N, B, D, R, F, p, n], @[P, N, B, D, R, F]],
  @[@[p, n, B, D, R], @[P, N, B, D, R]],
  @[@[D, p, F, N, n, P, R], @[D, P, F, N, R]],
  @[@[n, D, p, R], @[N, D, P, R]],
  @[@[D, n, F, N], @[D, N, F]],
  @[@[B, P, N, D, F, R], @[B, P, N, D, F, R]],
  @[@[p], @[P]], @[@[N], @[N]], @[@[D, R], @[D, R]], @[@[], @[]],
 ];
 NSUInteger merged = 0;
 for (NSString *ident in @[kPDFKitToolbarIdentifier, kFullWindowToolbarIdentifier]) for (NSArray *pair in cases) {
  NSToolbar *bar = [[NSToolbar alloc] initWithIdentifier:ident]; bar.autosavesConfiguration = NO; bar.delegate = d;
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
  window.releasedWhenClosed = NO; window.toolbar = bar;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  [bar setConfigurationFromDictionary:@{@"TB Item Identifiers": pair[0], @"TB Display Mode": @1, @"TB Is Shown": @YES, @"TB Size Mode": @1}];
#pragma clang diagnostic pop
  NSString *where = [NSString stringWithFormat:@"%@ %@", ident, [pair[0] componentsJoinedByString:@","]];
  Check([[bar.items valueForKey:@"itemIdentifier"] isEqual:pair[0]], [@"Saved toolbar loads as saved: " stringByAppendingString:where]);
  [d keepOnePreviewPagePairInToolbar:bar];
  Check([[bar.items valueForKey:@"itemIdentifier"] isEqual:pair[1]], [NSString stringWithFormat:@"One page pair kept in place: %@ -> %@", where, [[bar.items valueForKey:@"itemIdentifier"] componentsJoinedByString:@","]]);
  [d keepOnePreviewPagePairInToolbar:bar];
  Check([[bar.items valueForKey:@"itemIdentifier"] isEqual:pair[1]], [@"Keeping one page pair twice changes nothing: " stringByAppendingString:where]);
  NSInteger previous = d.view.previous, next = d.view.next;
  for (NSToolbarItem *item in bar.items) {
   if (![current containsObject:item.itemIdentifier]) continue;
   Check([Pixels(item.image) isEqual:Pixels([d makePreviewPageItemWithItemIdentifier:item.itemIdentifier].image)] && item.label.length, @"Kept page item shows the document arrow");
   Check([NSApp sendAction:item.action to:item.target from:item], @"Kept page item sends its command");
  }
  Check(d.view.previous == previous + Count(pair[1], P) && d.view.next == next + Count(pair[1], N), @"Kept page items turn the preview page");
  merged++;
 }
 Check(merged == 24, @"All saved toolbars checked");
 // The default sets are left as they are.
 for (NSString *ident in @[kPDFKitToolbarIdentifier, kFullWindowToolbarIdentifier]) for (int share = 0; share < 2; share++) for (int swap = 0; swap < 2; swap++) {
  sharing = share; [defaults setBool:swap forKey:SwitchSidesKey];
  NSToolbar *bar = [[NSToolbar alloc] initWithIdentifier:ident]; bar.autosavesConfiguration = NO; bar.delegate = d;
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
  window.releasedWhenClosed = NO; window.toolbar = bar;
  NSArray *standard = [d toolbarDefaultItemIdentifiers:bar];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  [bar setConfigurationFromDictionary:@{@"TB Item Identifiers": standard, @"TB Display Mode": @1, @"TB Is Shown": @YES, @"TB Size Mode": @1}];
#pragma clang diagnostic pop
  Check([[bar.items valueForKey:@"itemIdentifier"] isEqual:standard], @"Default set loads as listed");
  [d keepOnePreviewPagePairInToolbar:bar];
  Check([[bar.items valueForKey:@"itemIdentifier"] isEqual:standard], @"Default set unchanged");
 }
 sharing = YES; [defaults setBool:NO forKey:SwitchSidesKey];
 NSLog(@"%@ PASS: one previous/next pair offered and in default sets; former identifiers show working document-arrow items; saved toolbars keep one pair", language);
}}
'''
# Exact text in the languages where the two pairs had been translated differently.
expected = {
    'en': [('Previous', 'Previous Page', 'Show previous page'), ('Next', 'Next Page', 'Show next page')],
    'ja': [('前のページ', '前のページ', '前のページを表示します'), ('次のページ', '次のページ', '次のページを表示します')],
    'de': [('Vorherige', 'Vorherige Seite', 'Vorherige Seite anzeigen'), ('Nächste', 'Nächste Seite', 'Nächste Seite anzeigen')],
    'fr': [('Précédent', 'Page précédente', 'Affiche la page précédente'), ('Suivant', 'Page suivante', 'Affiche la page suivante')],
}
objc = lambda text: '@"' + text.replace('\\', '\\\\').replace('"', '\\"') + '"'
table = '@{' + ', '.join('@"%s": @[%s]' % (language, ', '.join('@[%s]' % ', '.join(map(objc, item)) for item in items))
                         for language, items in expected.items()) + '}'
languages = sorted(p.parent.stem for p in (root/'Resources/Interfaces').glob('*.lproj/ToolbarItems.strings'))
assert len(languages) == 12 and set(expected) <= set(languages)
program = program.replace('CONSTANTS', constants).replace('METHODS', methods).replace('EXPECTED_TEXT', table)
if not args.mutation:
    verify_embedded(program, fragments)
with tempfile.TemporaryDirectory(prefix='TeXShop-toolbar-pages-') as tmp:
    tmp = Path(tmp)
    app = tmp/'ToolbarPageTest.app'; mac = app/'Contents/MacOS'; mac.mkdir(parents=True)
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'org.texshop.ToolbarPageTest.'+tmp.name,
        'CFBundleExecutable': 'ToolbarPageTest', 'CFBundlePackageType': 'APPL', 'LSUIElement': True, 'CFBundleDevelopmentRegion': 'en'}))
    for language in languages:
        res = app/f'Contents/Resources/{language}.lproj'; res.mkdir(parents=True)
        shutil.copy(root/f'Resources/Interfaces/{language}.lproj/ToolbarItems.strings', res)
    source = tmp/'Test.m'; source.write_text(program)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-w', *include_args(root), '-I'+str(root/'Tests'),
                    '-framework', 'Cocoa', str(source), '-o', str(mac/'ToolbarPageTest')], check=True)
    home = tmp/'Home'; (home/'Library/Preferences').mkdir(parents=True)
    try:
        for language in languages:
            result = subprocess.run([str(mac/'ToolbarPageTest'), language, '-AppleLanguages', f'({language})'],
                                    env={**os.environ, 'CFFIXED_USER_HOME': str(home)}, capture_output=True, text=True)
            sys.stderr.write(result.stderr)
            if result.returncode:
                sys.exit(result.returncode)
    finally:
        subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister', '-u', str(app)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
