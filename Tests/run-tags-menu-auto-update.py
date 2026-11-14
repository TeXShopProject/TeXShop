#!/usr/bin/env python3
"""Check that the Tags and Labels menus are filled each time they open, without an Update button.

The Tags menu in the menu bar (Settings → Editor → Tags Menu in Menubar) is filled with
the tags of the frontmost document each time it opens: the document of the key window,
else of the main window, else of the frontmost visible window of a document. Every window
of a document counts (source, preview, single window, console, log, HTML, full screen,
the Experiment windows, and sheets on them), as the real compiled TSDocument.nib of each
language gives them to the document; windows of no document are passed over. It is emptied when the frontmost
document is configured for an external editor or shows no source, and when there is no
document. The menus of the Tags and Labels toolbar items, in the source window and in the
single window, are filled each time they open, also from the item's label when the toolbar
shows text only and from the overflow menu: in all three cases AppKit opens the same menu,
the one whose delegate is the document. With the hidden setting UseNewTagsAndLabels NO
nothing is filled on opening, as before. Looking for a key equivalent does not fill them.

The Update toolbar item (Update and UpdateSplit) is gone: its identifiers, its image, its
strings in the 12 languages and its command. A toolbar saved with Update shows the other
items, and nothing is written to the console.

The production code is compiled from TSDocument.m, TSAppDelegate.m and
TSToolbarController.m onto small stand-ins. Windows are never shown and no menu is opened:
the test checks which menu AppKit would open and calls its delegate as AppKit does before
opening it. Preferences stay in memory.
"""
import argparse, json, os, plistlib, re, shutil, subprocess, sys, tempfile
from pathlib import Path
from production_fragments import method as production_method, verify_embedded
from source_tree import include_args, source_file

MUTATIONS = {
    'notifications': 'the toolbar menus are filled on NSMenuDidBeginTrackingNotification, as before',
    'no-menu-bar-delegate': 'the Tags menu in the menu bar gets no delegate',
    'menu-bar-only-when-shown': 'the delegate is set only when Tags Menu in Menubar is on at launch',
    'ignore-external-editor': 'a document for an external editor fills the menu bar Tags menu',
    'no-log-window': 'the log window is not counted as a window of its document',
    'ordered-windows-only': 'the key and main windows are not asked first',
    'no-sheet-parent': 'a sheet is not followed to the window it is on',
    'old-method-fills': 'with UseNewTagsAndLabels NO the menu bar Tags menu is filled on opening',
    'no-key-equivalent-answer': 'the delegates do not answer menuHasKeyEquivalent:',
    'update-strings': 'English ToolbarItems.strings keeps tiLabelUpdate',
}
parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
toolbar = (root/'Sources/Windows/TSToolbarController.m').read_text()
document = source_file(root, 'TSDocument.m').read_text()
header = source_file(root, 'TSDocument.h').read_text()
delegate = source_file(root, 'TSAppDelegate.m').read_text()
syntax = source_file(root, 'TSDocument-Syntax.m').read_text()

failures = []
def check(ok, what):
    if not ok:
        failures.append(what)
    print(('ok: ' if ok else 'FAIL: ') + what, flush=True)

# --- The Update item is gone. -------------------------------------------------------
sources = {p: p.read_text(errors='replace') for p in (root/'Sources').rglob('*') if p.suffix in ('.m', '.h', '.inc', '.swift')}
check(not any(re.search(r'\bdoUpdate\b', t) for t in sources.values()), 'No doUpdate: left in Sources')
check(not re.search(r'k?UpdateTID|@"Update(Split)?"|UpdateAction', toolbar), 'No Update identifiers or image in the toolbar code')
check(not (root/'Resources/Images.xcassets/UpdateAction.imageset').exists(), 'The UpdateAction image is removed')
check('UpdateAction' not in (root/'TeXShop.xcodeproj/project.pbxproj').read_text(), 'The project does not name UpdateAction')
removed_keys = {'tiLabelUpdate', 'tiPaletteLabelUpdate', 'tiToolTipUpdate',
                'tiLabelUpdateSplit', 'tiPaletteLabelUpdateSplit', 'tiToolTipUpdateSplit'}
strings_files = sorted((root/'Resources/Interfaces').glob('*.lproj/ToolbarItems.strings'))
check(len(strings_files) == 12, 'ToolbarItems.strings in 12 languages')
with tempfile.TemporaryDirectory(prefix='TeXShop-tags-strings-') as tmp:
    for path in strings_files:
        source = path
        if args.mutation == 'update-strings' and path.parent.name == 'en.lproj':
            source = Path(tmp)/'ToolbarItems.strings'
            source.write_text(path.read_text() + '\ntiLabelUpdate = "Update";\n')
        table = json.loads(subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(source)],
                                          check=True, capture_output=True, text=True).stdout)
        check(not removed_keys & set(table) and 'tiLabelTags' in table and 'tiLabelLabelsSplit' in table,
              f'No Update strings, Tags and Labels kept: {path.parent.name}')
# The allowed toolbar items list Tags and Labels but no longer Update; a saved Update
# reaches the end of toolbar:itemForItemIdentifier:, which answers nil.
item_for = production_method(toolbar, '- (NSToolbarItem *) toolbar: (NSToolbar *)toolbar itemForItemIdentifier:')
check(item_for.rstrip().endswith('return nil;\n}'), 'Unknown saved identifiers get no item')
allowed = production_method(toolbar, '- (NSArray *) toolbarAllowedItemIdentifiers: (NSToolbar *) toolbar {')
defaults = production_method(toolbar, '- (NSArray *) toolbarDefaultItemIdentifiers: (NSToolbar *) toolbar {')
check(len(re.findall(r'\bkTagsTID,', allowed)) == 2 and len(re.findall(r'\bskLabelsTID,', allowed)) == 2 and 'Update' not in allowed,
      'Allowed items keep Tags and Labels without Update')
check('Update' not in defaults, 'Default toolbars have no Update')
# After loading, the menus are filled once, as the Update button did; the command is internal now.
check(syntax.count('[self setupTagsAndLabelsAfterLoading];') == 1, 'Syntax coloring fills the menus after loading')
check('- (void) setupTagsAndLabelsAfterLoading;' in header and 'IBAction) doUpdate' not in header, 'No toolbar action left in TSDocument.h')
# setupTags1 empties the menu bar Tags menu before it returns for a file that is not TeX.
setup = production_method(document, '- (void) setupTags1\n{')
check(setup.index('[tagsMenu removeAllItems];') < setup.index('if (!fileIsTex) return;'), 'setupTags1 empties the menu bar menu for other files')

# --- The harness. --------------------------------------------------------------------
fragments = []
def method(source, signature):
    fragment = production_method(source, signature)
    fragments.append(('complete method:' + signature, source, fragment))
    return fragment
def span(source, first, last):
    assert source.count(first) == 1, first
    start = source.index(first); end = source.index(last, start) + len(last)
    fragment = source[start:end]
    fragments.append(('statements:' + first, source, fragment))
    return fragment

constants = span(toolbar, 'static NSString* \tkSourceToolbarIdentifier', 'kHtmlSearchTID              = @"HtmlSearch";')
items = span(toolbar, '\tif ([itemIdent isEqual: kTagsTID]) {', '        theSLabels = toolbarItem;\n        return toolbarItem;\n    }')
no_item = span(toolbar, '\t// itemIdent refered to a toolbar item that is not provide or supported by us or cocoa', '\treturn nil;')
make = '\n'.join(method(toolbar, s) for s in [
    '- (NSToolbarItem*) makeToolbarItemWithItemIdentifier:(NSString*)itemIdent key:(NSString*)itemKey\n{',
    '- (NSToolbarItem*) makeToolbarItemWithItemIdentifier:(NSString*)itemIdent key:(NSString*)itemKey customView:(id)customView'])
registration = span(document, '    // The Tags and Labels menus of the toolbars are filled each time they open:', '    [[slabels menu] setDelegate: self];')
menus = '\n'.join(method(document, s) for s in [
    '- (void)menuNeedsUpdate:(NSMenu *)menu', '- (BOOL)menuHasKeyEquivalent:(NSMenu *)menu forEvent:',
    '- (BOOL)ownsWindow:(NSWindow *)window', '+ (TSDocument *)documentOwningWindow:(NSWindow *)window',
    '+ (void)updateTagsMenuInMenuBar:(NSMenu *)menu', '- (void)setupTagsAndLabelsAfterLoading'])
install = span(delegate, '    if ( ![[NSUserDefaults standardUserDefaults] boolForKey:TagMenuInMenuBarKey])',
               '    [[[[NSApp mainMenu] itemWithTitle:NSLocalizedString(@"Tags", @"Tags")] submenu] setDelegate: self];')
log_header = source_file(root, 'TSLogWindow.h').read_text()
log_source = source_file(root, 'TSLogWindow.m').read_text()
log_impl = log_source[log_source.index('@implementation TSLogWindow'):]
fragments.append(('statements:@implementation TSLogWindow', log_source, log_impl))
fragments.append(('statements:TSLogWindow.h', log_header, log_header))
log_window = log_header + '\n' + log_impl
app_menus = '\n'.join(method(delegate, s) for s in [
    '- (void)menuNeedsUpdate:(NSMenu *)menu', '- (BOOL)menuHasKeyEquivalent:(NSMenu *)menu forEvent:'])
# The registration is part of registerForNotifications, for documents that show a source.
register = production_method(document, '- (void)registerForNotifications')
check(registration in register[register.index('if ( ! skipTextWindow) {'):], 'Registration is in registerForNotifications')
check('NSMenuDidBeginTrackingNotification' not in document, 'No menu tracking notification is observed')

program = r'''
#import "TestAppKitIsolation.h"
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#define SUD [NSUserDefaults standardUserDefaults]
static NSString *UseNewTagsAndLabelsKey = @"UseNewTagsAndLabels";
static NSString *TagMenuInMenuBarKey = @"TagMenuInMenuBar";
static BOOL atLeastMonterey = YES;
static int failures;
static void Check(BOOL ok, NSString *what) {
    if (!ok) failures++;
    fprintf(stderr, "%s%s\n", ok ? "ok: " : "FAIL: ", what.UTF8String);
}
@@CONSTANTS@@

@class TSDocument;
static NSArray *orderedWindows;
static NSWindow *harnessKey, *harnessMain;
static NSArray *HarnessOrderedWindows(id self, SEL _cmd) { return orderedWindows; }
static NSWindow *HarnessKeyWindow(id self, SEL _cmd) { return harnessKey; }
static NSWindow *HarnessMainWindow(id self, SEL _cmd) { return harnessMain; }

// Windows are never ordered in; a test says which are visible, and which window a sheet is on.
static NSHashTable *shownWindows;
static BOOL HarnessIsVisible(NSWindow *self, SEL _cmd) { return [shownWindows containsObject:self]; }
static void SetShown(NSWindow *w, BOOL shown) { if (shown) [shownWindows addObject:w]; else [shownWindows removeObject:w]; }
@interface HarnessWindow : NSWindow
@property (weak) NSWindow *harnessSheetParent;
@end
@implementation HarnessWindow
- (NSWindow *)sheetParent { return self.harnessSheetParent; }
@end
static HarnessWindow *NewWindow(BOOL shown)
{
    HarnessWindow *w = [[HarnessWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    w.releasedWhenClosed = NO; SetShown(w, shown);
    return w;
}
// The window classes of TSDocument.nib, to load the compiled nibs without TeXShop.
static void RegisterNibClass(NSString *name, Class base)
{
    if (NSClassFromString(name)) return;
    Class c = objc_allocateClassPair(base, name.UTF8String, 0);
    objc_registerClassPair(c);
}

@interface TSDocument : NSDocument <NSMenuDelegate, NSToolbarDelegate>
{
@public
    NSPopUpButton *tags, *stags, *labels, *slabels;
    BOOL _externalEditor, skipTextWindow, fileIsTex;
    NSToolbarItem *theLabels, *theSLabels;
    NSWindow *textWindow, *pdfWindow, *fullSplitWindow, *outputWindow;
    NSPanel *scrapWindow, *scrapPDFWindow;
}
@property NSWindow *pdfKitWindow, *logWindow, *htmlWindow, *fullscreenWindow;
@property NSWindowController *experimentConsole;
@property NSString *name;
@property NSInteger tagsFilled, labelsFilled, tags2Filled;
@end
@implementation TSDocument
- (BOOL)externalEditor { return _externalEditor; }
// Outlets of TSDocument.nib this stand-in does not have.
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {}
- (void)doTypeset:(id)sender {} - (void)doAlternateTypeset:(id)sender {} - (void)displayLog:(id)sender {} - (void)displayConsole:(id)sender {}
- (BOOL)skipTextWindow { return skipTextWindow; }
// Stand-in for setupTags1: like it, empties the toolbar menus and the menu bar menu, then
// lists the document's tags (here one tag, named after the document) when it is TeX.
- (void)setupTags1
{
    self.tagsFilled++;
    NSMenu *tagsMenu = [[[NSApp mainMenu] itemWithTitle:@"Tags"] submenu];
    [tags removeAllItems]; [stags removeAllItems]; [tagsMenu removeAllItems];
    [tags addItemWithTitle:@"Tags"]; [stags addItemWithTitle:@"Tags"];
    if (!fileIsTex) return;
    [tags addItemWithTitle:self.name]; [stags addItemWithTitle:self.name];
    [[tagsMenu addItemWithTitle:self.name action:@selector(doTag:) keyEquivalent:@""] setTarget:self];
}
- (void)setupLabels1
{
    self.labelsFilled++;
    [labels removeAllItems]; [slabels removeAllItems];
    [labels addItemWithTitle:@"Labels"]; [slabels addItemWithTitle:@"Labels"];
    [labels addItemWithTitle:[self.name stringByAppendingString:@" label"]];
    [slabels addItemWithTitle:[self.name stringByAppendingString:@" label"]];
}
- (void)setupTags2 { self.tags2Filled++; }
- (void)doTag:(id)sender {}
- (void)registerTagsAndLabels
{
@@REGISTRATION@@
}
@@MENUS@@
@@MAKE@@
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdent willBeInsertedIntoToolbar:(BOOL)willBeInserted
{
    NSToolbarItem *toolbarItem = 0;
    NSMenuItem *menuFormRep;
@@ITEMS@@
@@NO_ITEM@@
}
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    return [toolbar.identifier isEqual:kSourceToolbarIdentifier] ? @[kTagsTID, kLabelsTID] : @[skTagsTID, skLabelsTID];
}
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar { return [self toolbarAllowedItemIdentifiers:toolbar]; }
@end

@interface TSAppDelegate : NSObject <NSMenuDelegate>
- (void)install;
@end
@implementation TSAppDelegate
- (void)install
{
@@INSTALL@@
}
@@APP_MENUS@@
@end
@@LOG_WINDOW@@

static TSDocument *NewDocument(NSString *name)
{
    TSDocument *d = [[TSDocument alloc] init];
    [[NSDocumentController sharedDocumentController] addDocument:d];
    d.name = name; d->fileIsTex = YES;
    d->tags = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 24) pullsDown:YES];
    d->stags = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 24) pullsDown:YES];
    d->labels = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 24) pullsDown:YES];
    d->slabels = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 24) pullsDown:YES];
    for (NSPopUpButton *b in @[d->tags, d->stags, d->labels, d->slabels]) [b addItemWithTitle:@"old"];
    [d registerTagsAndLabels];
    return d;
}
// The source window, as in TeXShop: an outlet of the document and its window controller's window.
static HarnessWindow *SourceWindow(TSDocument *d, BOOL shown)
{
    HarnessWindow *w = NewWindow(shown);
    NSWindowController *wc = [[NSWindowController alloc] initWithWindow:w];
    [d addWindowController:wc];
    d->textWindow = w;
    return w;
}
static NSArray *Titles(NSMenu *m) { return [m.itemArray valueForKey:@"title"]; }
static NSString *Joined(NSArray *a) { return [NSString stringWithFormat:@"[%@]", [a componentsJoinedByString:@", "]]; }
static void SetDefaults(BOOL useNew, BOOL menuBar)
{
    [SUD setVolatileDomain:@{UseNewTagsAndLabelsKey: @(useNew), TagMenuInMenuBarKey: @(menuBar)} forName:NSArgumentDomain];
}
static void SetUseNew(BOOL on) { SetDefaults(on, YES); }

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    method_setImplementation(class_getInstanceMethod([NSApplication class], @selector(orderedWindows)), (IMP)HarnessOrderedWindows);
    method_setImplementation(class_getInstanceMethod([NSApplication class], @selector(keyWindow)), (IMP)HarnessKeyWindow);
    method_setImplementation(class_getInstanceMethod([NSApplication class], @selector(mainWindow)), (IMP)HarnessMainWindow);
    shownWindows = [NSHashTable weakObjectsHashTable];
    for (NSString *name in @[@"TSConsoleWindow", @"TSFullSplitWindow", @"TSFullscreenWindow", @"TSHTMLWindow", @"TSPreviewWindow", @"TSTextEditorWindow"]) RegisterNibClass(name, NSWindow.class);
    RegisterNibClass(@"MyPDFView", NSView.class); RegisterNibClass(@"MyPDFKitView", PDFView.class); RegisterNibClass(@"ScrapPDFKitView", PDFView.class);
    RegisterNibClass(@"TSTextView", NSTextView.class); RegisterNibClass(@"ScrapTextView", NSTextView.class);
    method_setImplementation(class_getInstanceMethod([NSWindow class], @selector(isVisible)), (IMP)HarnessIsVisible);
    SetUseNew(YES);
    NSMenu *main = [[NSMenu alloc] initWithTitle:@"Main"];
    NSMenuItem *top = [main addItemWithTitle:@"Tags" action:nil keyEquivalent:@""];
    NSMenu *bar = [[NSMenu alloc] initWithTitle:@"Tags"]; top.submenu = bar;
    [NSApp setMainMenu:main];
    NSEvent *commandKey = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:0 context:nil characters:@"k" charactersIgnoringModifiers:@"k" isARepeat:NO keyCode:40];

    // The menu bar Tags menu gets its delegate at launch, whether or not it is shown.
    TSAppDelegate *app = [[TSAppDelegate alloc] init];
    for (NSNumber *shown in @[@NO, @YES]) {
        bar.delegate = nil; top.hidden = NO;
        SetDefaults(YES, shown.boolValue);
        [app install];
        SetUseNew(YES);
        Check(bar.delegate == app, [NSString stringWithFormat:@"Menu bar Tags menu has the app delegate as delegate (Tags Menu in Menubar %@)", shown]);
        Check(top.hidden == !shown.boolValue, @"Tags Menu in Menubar still shows or hides the menu");
    }

    TSDocument *a = NewDocument(@"A"), *b = NewDocument(@"B");
    // The toolbar menus have the document as delegate.
    for (NSPopUpButton *p in @[a->tags, a->stags, a->labels, a->slabels])
        Check(p.menu.delegate == a, @"Toolbar Tags and Labels menus have the document as delegate");

    // Text-only toolbars of the source window and of the single window, saved with Update.
    // AppKit opens the menu of the item's menu form; in the overflow menu, the same menu.
    fprintf(stderr, "SAVED-TOOLBAR-BEGIN\n");
    NSDictionary *saved = @{kSourceToolbarIdentifier: @[kTagsTID, @"Update", kLabelsTID],
                            @"Single Window Toolbar": @[skTagsTID, @"UpdateSplit", skLabelsTID]};
    for (NSString *ident in saved) {
        HarnessWindow *w = SourceWindow(a, NO);
        NSToolbar *tb = [[NSToolbar alloc] initWithIdentifier:ident]; tb.autosavesConfiguration = NO; tb.delegate = a;
        w.toolbar = tb;
        [tb setConfigurationFromDictionary:@{@"TB Item Identifiers": saved[ident], @"TB Display Mode": @(NSToolbarDisplayModeLabelOnly), @"TB Is Shown": @YES, @"TB Size Mode": @1}];
        [w.contentView.superview layoutSubtreeIfNeeded];
        NSArray *expected = [ident isEqual:kSourceToolbarIdentifier] ? @[kTagsTID, kLabelsTID] : @[skTagsTID, skLabelsTID];
        Check([[tb.items valueForKey:@"itemIdentifier"] isEqual:expected], [NSString stringWithFormat:@"Saved Update is dropped, the other items stay: %@", Joined([tb.items valueForKey:@"itemIdentifier"])]);
        Check(tb.displayMode == NSToolbarDisplayModeLabelOnly, @"Toolbar shows text only");
        for (NSToolbarItem *item in tb.items) {
            BOOL isTags = [item.itemIdentifier hasPrefix:@"Tags"];
            NSPopUpButton *popup = (NSPopUpButton *)item.view;
            NSMenu *menu = item.menuFormRepresentation.submenu;
            Check(menu != nil && menu == popup.menu, [@"Text-only item opens the item's own menu: " stringByAppendingString:item.itemIdentifier]);
            SEL uses = NSSelectorFromString(@"usesMenuFormRepresentationInDisplayMode:");
            if ([item respondsToSelector:uses]) {
                BOOL (*f)(id, SEL, NSInteger) = (BOOL (*)(id, SEL, NSInteger))objc_msgSend;
                Check(f(item, uses, NSToolbarDisplayModeLabelOnly), @"AppKit uses the menu form when the toolbar shows text only");
            }
            SEL overflow = NSSelectorFromString(@"_menuFormRepresentationForOverflowMenu");
            if ([item respondsToSelector:overflow]) {
                NSMenuItem *(*g)(id, SEL) = (NSMenuItem *(*)(id, SEL))objc_msgSend;
                Check(g(item, overflow).submenu == popup.menu, @"The overflow menu opens the same menu");
            }
            // AppKit asks the menu's delegate just before opening it.
            a.name = isTags ? @"A2" : @"A3";
            NSInteger t = a.tagsFilled, l = a.labelsFilled;
            [menu.delegate menuNeedsUpdate:menu];
            Check(a.tagsFilled == t + (isTags ? 1 : 0) && a.labelsFilled == l + (isTags ? 0 : 1), [@"Opening fills only this menu: " stringByAppendingString:item.itemIdentifier]);
            Check([Titles(popup.menu) containsObject:isTags ? @"A2" : @"A3 label"], [@"The menu shows the current tags or labels: " stringByAppendingString:item.itemIdentifier]);
            // With the old method nothing is filled on opening.
            SetUseNew(NO); t = a.tagsFilled; l = a.labelsFilled;
            [menu.delegate menuNeedsUpdate:menu];
            Check(a.tagsFilled == t && a.labelsFilled == l, @"UseNewTagsAndLabels NO: nothing is filled on opening");
            SetUseNew(YES);
            // Looking for a key equivalent does not fill the menu.
            Check([menu.delegate respondsToSelector:@selector(menuHasKeyEquivalent:forEvent:target:action:)], @"The document answers menuHasKeyEquivalent:");
            if ([menu.delegate respondsToSelector:@selector(menuHasKeyEquivalent:forEvent:target:action:)]) {
                id target = nil; SEL action = NULL;
                Check(![menu.delegate menuHasKeyEquivalent:menu forEvent:commandKey target:&target action:&action], @"No key equivalent in the menu");
            }
            t = a.tagsFilled; l = a.labelsFilled;
            [popup performKeyEquivalent:commandKey];
            Check(a.tagsFilled == t && a.labelsFilled == l, @"A key equivalent does not fill the menu");
        }
        // A menu the document does not own is left alone.
        NSMenu *other = [[NSMenu alloc] initWithTitle:@"Other"]; NSInteger t = a.tagsFilled, l = a.labelsFilled;
        [a menuNeedsUpdate:other];
        Check(a.tagsFilled == t && a.labelsFilled == l, @"Other menus are not filled");
    }
    fprintf(stderr, "SAVED-TOOLBAR-END\n");

    // After loading, both menus are filled once (tags only when shown in the menu bar or
    // in a text-only toolbar, as setupTags2 decides).
    NSInteger t2 = a.tags2Filled, l = a.labelsFilled;
    [a setupTagsAndLabelsAfterLoading];
    Check(a.tags2Filled == t2 + 1 && a.labelsFilled == l + 1, @"After loading, tags and labels are filled");

    // The menu bar Tags menu follows the frontmost document: the key window's, else the
    // main window's, else that of the frontmost visible window of a document.
    void (^open)(void) = ^{ [bar.delegate menuNeedsUpdate:bar]; };
    HarnessWindow *aSource = SourceWindow(a, YES), *bSource = SourceWindow(b, YES);
    HarnessWindow *aPreview = NewWindow(YES); a.pdfKitWindow = aPreview;
    HarnessWindow *aLog = NewWindow(YES); a.logWindow = aLog;
    HarnessWindow *aConsole = NewWindow(YES); a->outputWindow = aConsole;
    HarnessWindow *aHTML = NewWindow(YES); a.htmlWindow = aHTML;
    HarnessWindow *aExperiment = NewWindow(YES); a->scrapWindow = (NSPanel *)aExperiment;
    HarnessWindow *aExperimentPreview = NewWindow(YES); a->scrapPDFWindow = (NSPanel *)aExperimentPreview;
    a.experimentConsole = [[NSWindowController alloc] initWithWindow:NewWindow(YES)];
    HarnessWindow *aSheet = NewWindow(YES); aSheet.harnessSheetParent = aSource;
    HarnessWindow *settings = NewWindow(YES), *panel = NewWindow(YES);
    HarnessWindow *bHidden = NewWindow(NO); b->fullSplitWindow = bHidden;
    a.name = @"A"; b.name = @"B";
    NSNull *none = [NSNull null];
    struct { const char *what; id key, main; NSArray *windows; NSArray *expected; } cases[] = {
        {"source window of A in front of B", aSource, aSource, @[aSource, bSource], @[@"A"]},
        {"source window of B in front of A", bSource, bSource, @[bSource, aSource], @[@"B"]},
        {"preview window of A in front of B", aPreview, aPreview, @[aPreview, bSource], @[@"A"]},
        {"log window of A in front of B", aLog, aLog, @[aLog, bSource], @[@"A"]},
        {"log window of A in front of B, neither key nor main", none, none, @[aLog, bSource], @[@"A"]},
        {"console of A key, B main", aConsole, bSource, @[aConsole, bSource], @[@"A"]},
        {"HTML window of A key", aHTML, aHTML, @[aHTML, bSource], @[@"A"]},
        {"Experiment window of A key, B main", aExperiment, bSource, @[bSource], @[@"A"]},
        {"Experiment preview of A key, B main", aExperimentPreview, bSource, @[bSource], @[@"A"]},
        {"Experiment console of A key, B main", a.experimentConsole.window, bSource, @[bSource], @[@"A"]},
        {"sheet on the source window of A key, B main", aSheet, bSource, @[bSource, aSource], @[@"A"]},
        {"key B over main A", bSource, aSource, @[bSource, aSource], @[@"B"]},
        {"panel of no document key, A main, B in front", panel, aPreview, @[bSource, aPreview], @[@"A"]},
        {"Settings main, B behind it", none, settings, @[settings, bSource], @[@"B"]},
        {"hidden window of B in front of A", none, none, @[bHidden, aSource], @[@"A"]},
        {"no document", settings, settings, @[settings], @[]},
        {"no window", none, none, @[], @[]},
    };
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        [bar removeAllItems]; [bar addItemWithTitle:@"stale" action:nil keyEquivalent:@""];
        harnessKey = cases[i].key == none ? nil : cases[i].key; harnessMain = cases[i].main == none ? nil : cases[i].main;
        orderedWindows = cases[i].windows;
        open();
        Check([Titles(bar) isEqual:cases[i].expected], [NSString stringWithFormat:@"Menu bar Tags menu, %s: %@", cases[i].what, Joined(Titles(bar))]);
    }
    harnessKey = harnessMain = nil;

    // The real compiled TSDocument.nib of each language, with the real TSLogWindow: every
    // window the nib gives the document belongs to it, and its log window in front makes
    // the menu show its tags.
    for (int i = 1; i < argc; i++) {
        if (![@(argv[i]) hasSuffix:@".nib"]) continue;
        TSDocument *n = [[TSDocument alloc] init]; n.name = @"N"; n->fileIsTex = YES;
        NSNib *nib = [[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:@(argv[i])] bundle:nil];
        NSArray *objects = nil;
        Check([nib instantiateWithOwner:n topLevelObjects:&objects], [NSString stringWithFormat:@"Nib loads: %s", argv[i]]);
        [[NSDocumentController sharedDocumentController] addDocument:n];
        NSDictionary *windows = @{@"textWindow": n->textWindow ?: none, @"pdfWindow": n->pdfWindow ?: none, @"fullSplitWindow": n->fullSplitWindow ?: none,
                                  @"outputWindow": n->outputWindow ?: none, @"scrapWindow": n->scrapWindow ?: none, @"scrapPDFWindow": n->scrapPDFWindow ?: none,
                                  @"pdfKitWindow": n.pdfKitWindow ?: none, @"logWindow": n.logWindow ?: none, @"htmlWindow": n.htmlWindow ?: none,
                                  @"fullscreenWindow": n.fullscreenWindow ?: none};
        for (NSString *key in windows) {
            id w = windows[key];
            Check(w != none && [TSDocument documentOwningWindow:w] == n, [NSString stringWithFormat:@"%s: the %@ belongs to its document", argv[i], key]);
        }
        Check([n.logWindow isKindOfClass:[TSLogWindow class]] && [(TSLogWindow *)n.logWindow myDocument] == n && n.logWindow.windowController == nil && n.logWindow.delegate == nil,
              [NSString stringWithFormat:@"%s: the log window is a TSLogWindow that knows its document only as myDocument", argv[i]]);
        SetShown(n.logWindow, YES);
        [bar removeAllItems];
        harnessKey = harnessMain = n.logWindow; orderedWindows = @[n.logWindow, bSource]; open();
        Check([Titles(bar) isEqual:@[@"N"]], [NSString stringWithFormat:@"%s: log window in front, key and main: %@", argv[i], Joined(Titles(bar))]);
        harnessKey = harnessMain = nil; open();
        Check([Titles(bar) isEqual:@[@"N"]], [NSString stringWithFormat:@"%s: log window in front, neither key nor main: %@", argv[i], Joined(Titles(bar))]);
        SetShown(n.logWindow, NO);
        [[NSDocumentController sharedDocumentController] removeDocument:n];
    }
    harnessKey = harnessMain = nil;
    // A front document that is not TeX, is configured for an external editor, or shows no source.
    struct { const char *what; BOOL tex, external, skip; NSInteger calls; } kinds[] = {
        {"not a TeX file", NO, NO, NO, 1}, {"external editor", YES, YES, NO, 0}, {"no source window", YES, NO, YES, 0}};
    for (size_t i = 0; i < 3; i++) {
        a->fileIsTex = kinds[i].tex; a->_externalEditor = kinds[i].external; a->skipTextWindow = kinds[i].skip;
        [bar removeAllItems]; [bar addItemWithTitle:@"stale" action:nil keyEquivalent:@""];
        orderedWindows = @[aSource, bSource]; NSInteger before = a.tagsFilled;
        open();
        Check(bar.numberOfItems == 0, [NSString stringWithFormat:@"Menu bar Tags menu is empty: front document %s", kinds[i].what]);
        Check(a.tagsFilled == before + kinds[i].calls, [NSString stringWithFormat:@"Front document %s is filled only when it shows its own source", kinds[i].what]);
    }
    a->fileIsTex = YES; a->_externalEditor = NO; a->skipTextWindow = NO;
    // With the old method the menu bar menu is left as it is on opening.
    SetUseNew(NO);
    [bar removeAllItems]; [bar addItemWithTitle:@"kept" action:nil keyEquivalent:@""];
    orderedWindows = @[aSource]; NSInteger before = a.tagsFilled;
    open();
    Check([Titles(bar) isEqual:@[@"kept"]] && a.tagsFilled == before, @"UseNewTagsAndLabels NO: menu bar Tags menu is not filled on opening");
    SetUseNew(YES);
    // Another menu of the app delegate, and key equivalents, leave it alone.
    NSMenu *other = [[NSMenu alloc] initWithTitle:@"Other"]; before = a.tagsFilled;
    [app menuNeedsUpdate:other];
    Check(a.tagsFilled == before, @"The app delegate fills only the Tags menu");
    Check([app respondsToSelector:@selector(menuHasKeyEquivalent:forEvent:target:action:)], @"The app delegate answers menuHasKeyEquivalent:");
    [main performKeyEquivalent:commandKey];
    Check(a.tagsFilled == before, @"A key equivalent does not fill the menu bar Tags menu");
    // A menu item jumps in the document whose tags it shows.
    orderedWindows = @[bSource, aSource]; open();
    Check(bar.numberOfItems == 1 && [bar itemAtIndex:0].target == b, @"Menu bar tags go to the frontmost document");
    if (failures) { fprintf(stderr, "%d FAILURES\n", failures); return 1; }
    fprintf(stderr, "PASS: the Tags and Labels menus are filled each time they open\n");
    return 0;
}}
'''
def mutate(old, new):
    global registration, menus, install, app_menus
    texts = [registration, menus, install, app_menus]
    assert sum(t.count(old) for t in texts) == 1, old
    registration, menus, install, app_menus = (t.replace(old, new) for t in texts)

if args.mutation == 'notifications':
    mutate('''    [[tags menu] setDelegate: self];
    [[stags menu] setDelegate: self];
    [[labels menu] setDelegate: self];
    [[slabels menu] setDelegate: self];''', '''    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(setupTags1) name:NSMenuDidBeginTrackingNotification object:[tags menu]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(setupTags1) name:NSMenuDidBeginTrackingNotification object:[stags menu]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(setupLabels1) name:NSMenuDidBeginTrackingNotification object:[labels menu]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(setupLabels1) name:NSMenuDidBeginTrackingNotification object:[slabels menu]];''')
elif args.mutation == 'no-menu-bar-delegate':
    mutate('    [[[[NSApp mainMenu] itemWithTitle:NSLocalizedString(@"Tags", @"Tags")] submenu] setDelegate: self];', '')
elif args.mutation == 'menu-bar-only-when-shown':
    mutate('''
    }
    // The Tags menu in the menu bar is filled each time it opens.
    [[[[NSApp mainMenu] itemWithTitle:NSLocalizedString(@"Tags", @"Tags")] submenu] setDelegate: self];''', '''
    }
    else
    [[[[NSApp mainMenu] itemWithTitle:NSLocalizedString(@"Tags", @"Tags")] submenu] setDelegate: self];''')
elif args.mutation == 'ignore-external-editor':
    mutate('(! [document externalEditor]) && ', '')
elif args.mutation == 'no-log-window':
    mutate(' (window == self.logWindow) ||', '')
elif args.mutation == 'ordered-windows-only':
    mutate('''    if ([NSApp keyWindow] != nil)
        [windows addObject: [NSApp keyWindow]];
    if ([NSApp mainWindow] != nil)
        [windows addObject: [NSApp mainWindow]];
''', '')
elif args.mutation == 'no-sheet-parent':
    mutate('''    while ([window sheetParent] != nil)
        window = [window sheetParent];
''', '')
elif args.mutation == 'old-method-fills':
    start = menus.index('+ (void)updateTagsMenuInMenuBar:')
    check_old = '    if ( ! [SUD boolForKey:UseNewTagsAndLabelsKey])\n        return;\n'
    at = menus.index(check_old, start)
    menus = menus[:at] + menus[at + len(check_old):]
elif args.mutation == 'no-key-equivalent-answer':
    def without_answer(text):
        start = text.index('- (BOOL)menuHasKeyEquivalent:'); end = text.index('return NO;\n}', start) + len('return NO;\n}')
        return text[:start] + text[end:]
    menus, app_menus = without_answer(menus), without_answer(app_menus)

for token, text in (('CONSTANTS', constants), ('REGISTRATION', registration), ('MENUS', menus), ('MAKE', make),
                    ('NO_ITEM', no_item), ('ITEMS', items), ('INSTALL', install), ('APP_MENUS', app_menus), ('LOG_WINDOW', log_window)):
    assert program.count('@@%s@@' % token) == 1, token
    program = program.replace('@@%s@@' % token, text)
if not args.mutation:
    verify_embedded(program, fragments)

with tempfile.TemporaryDirectory(prefix='TeXShop-tags-menu-') as tmp:
    tmp = Path(tmp)
    app = tmp/'TagsMenuTest.app'; mac = app/'Contents/MacOS'; mac.mkdir(parents=True)
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'org.texshop.TagsMenuTest.' + tmp.name,
        'CFBundleExecutable': 'TagsMenuTest', 'CFBundlePackageType': 'APPL', 'LSUIElement': True, 'CFBundleDevelopmentRegion': 'en'}))
    res = app/'Contents/Resources/en.lproj'; res.mkdir(parents=True)
    shutil.copy(root/'Resources/Interfaces/en.lproj/ToolbarItems.strings', res)
    source = tmp/'Test.m'; source.write_text(program)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-w', '-I' + str(root/'Tests'), '-framework', 'Cocoa', '-framework', 'PDFKit',
                    str(source), '-o', str(mac/'TagsMenuTest')], check=True)
    nibs = sorted((root/'Resources/Interfaces').glob('*.lproj/TSDocument.nib/keyedobjects*.nib'))
    check(len(nibs) == 12, 'Compiled TSDocument.nib in 12 languages')
    home = tmp/'Home'; (home/'Library/Preferences').mkdir(parents=True)
    try:
        result = subprocess.run([str(mac/'TagsMenuTest'), *map(str, nibs), '-AppleLanguages', '(en)'], env={**os.environ, 'CFFIXED_USER_HOME': str(home)},
                                capture_output=True, text=True, timeout=120)
    finally:
        subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister', '-u', str(app)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    sys.stdout.write(result.stderr)
    # A saved Update item leaves nothing on the console.
    between = result.stderr.split('SAVED-TOOLBAR-BEGIN\n', 1)[-1].split('SAVED-TOOLBAR-END', 1)[0]
    noise = [line for line in between.splitlines() if not line.startswith(('ok: ', 'FAIL: '))]
    check('SAVED-TOOLBAR-END' in result.stderr and not noise, 'Nothing written to the console for the saved Update item: %r' % noise)
    check(result.returncode == 0, 'Harness passes')

if failures:
    print('%d FAILURES' % len(failures))
    sys.exit(1)
print('PASS' + (' (mutation %s not detected)' % args.mutation if args.mutation else ''))
