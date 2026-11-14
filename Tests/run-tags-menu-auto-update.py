#!/usr/bin/env python3
"""Check that the Tags and Labels menus are filled each time they open, without an Update button.

The Tags menu in the menu bar (Settings → Editor → Tags Menu in Menubar) is filled with
the tags of the frontmost document each time it opens. It is emptied when the frontmost
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
    'main-window-only': 'only a window controller finds the document of a window',
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
    '+ (void)updateTagsMenuInMenuBar:(NSMenu *)menu', '- (void)setupTagsAndLabelsAfterLoading'])
install = span(delegate, '    if ( ![[NSUserDefaults standardUserDefaults] boolForKey:TagMenuInMenuBarKey])',
               '    [[[[NSApp mainMenu] itemWithTitle:NSLocalizedString(@"Tags", @"Tags")] submenu] setDelegate: self];')
app_menus = '\n'.join(method(delegate, s) for s in [
    '- (void)menuNeedsUpdate:(NSMenu *)menu', '- (BOOL)menuHasKeyEquivalent:(NSMenu *)menu forEvent:'])
# The registration is part of registerForNotifications, for documents that show a source.
register = production_method(document, '- (void)registerForNotifications')
check(registration in register[register.index('if ( ! skipTextWindow) {'):], 'Registration is in registerForNotifications')
check('NSMenuDidBeginTrackingNotification' not in document, 'No menu tracking notification is observed')

program = r'''
#import <Cocoa/Cocoa.h>
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
static NSArray *HarnessOrderedWindows(id self, SEL _cmd) { return orderedWindows; }

@interface HarnessWindow : NSWindow
@property BOOL shown;
@end
@implementation HarnessWindow
- (BOOL)isVisible { return self.shown; }
@end
// Like TSPreviewWindow, TSConsoleWindow and TSHTMLWindow: no window controller, but -document.
@interface HarnessPreviewWindow : HarnessWindow
@property (weak) TSDocument *owner;
- (TSDocument *)document;
@end
@implementation HarnessPreviewWindow
- (TSDocument *)document { return self.owner; }
@end

@interface TSDocument : NSDocument <NSMenuDelegate, NSToolbarDelegate>
{
@public
    NSPopUpButton *tags, *stags, *labels, *slabels;
    BOOL _externalEditor, skipTextWindow, fileIsTex;
    NSToolbarItem *theLabels, *theSLabels;
}
@property NSString *name;
@property NSInteger tagsFilled, labelsFilled, tags2Filled;
@end
@implementation TSDocument
- (BOOL)externalEditor { return _externalEditor; }
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

static TSDocument *NewDocument(NSString *name)
{
    TSDocument *d = [[TSDocument alloc] init];
    d.name = name; d->fileIsTex = YES;
    d->tags = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 24) pullsDown:YES];
    d->stags = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 24) pullsDown:YES];
    d->labels = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 24) pullsDown:YES];
    d->slabels = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 24) pullsDown:YES];
    for (NSPopUpButton *b in @[d->tags, d->stags, d->labels, d->slabels]) [b addItemWithTitle:@"old"];
    [d registerTagsAndLabels];
    return d;
}
static HarnessWindow *SourceWindow(TSDocument *d, BOOL shown)
{
    HarnessWindow *w = [[HarnessWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    w.releasedWhenClosed = NO; w.shown = shown;
    NSWindowController *wc = [[NSWindowController alloc] initWithWindow:w];
    [d addWindowController:wc];
    return w;
}
static NSArray *Titles(NSMenu *m) { return [m.itemArray valueForKey:@"title"]; }
static NSString *Joined(NSArray *a) { return [NSString stringWithFormat:@"[%@]", [a componentsJoinedByString:@", "]]; }
static void SetDefaults(BOOL useNew, BOOL menuBar)
{
    [SUD removeVolatileDomainForName:NSRegistrationDomain];
    [SUD setVolatileDomain:@{UseNewTagsAndLabelsKey: @(useNew), TagMenuInMenuBarKey: @(menuBar)} forName:NSRegistrationDomain];
}
static void SetUseNew(BOOL on) { SetDefaults(on, YES); }

int main(int argc, char **argv) { @autoreleasepool {
    [NSApplication sharedApplication];
    method_setImplementation(class_getInstanceMethod([NSApplication class], @selector(orderedWindows)), (IMP)HarnessOrderedWindows);
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

    // The menu bar Tags menu follows the frontmost document.
    void (^open)(void) = ^{ [bar.delegate menuNeedsUpdate:bar]; };
    HarnessWindow *aSource = SourceWindow(a, YES), *bSource = SourceWindow(b, YES);
    HarnessPreviewWindow *aPreview = [[HarnessPreviewWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    aPreview.releasedWhenClosed = NO; aPreview.owner = a; aPreview.shown = YES;
    HarnessWindow *aDelegateWindow = [[HarnessWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    aDelegateWindow.releasedWhenClosed = NO; aDelegateWindow.shown = YES; aDelegateWindow.delegate = (id<NSWindowDelegate>)a;
    HarnessWindow *settings = [[HarnessWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    settings.releasedWhenClosed = NO; settings.shown = YES;
    HarnessWindow *bHidden = SourceWindow(b, NO);
    a.name = @"A"; b.name = @"B";
    struct { const char *what; NSArray *windows; NSArray *expected; } cases[] = {
        {"source window of A in front of B", @[aSource, bSource], @[@"A"]},
        {"source window of B in front of A", @[bSource, aSource], @[@"B"]},
        {"preview window of A in front of B", @[aPreview, bSource], @[@"A"]},
        {"window whose delegate is A in front of B", @[aDelegateWindow, bSource], @[@"A"]},
        {"hidden window of B in front of A", @[bHidden, aSource], @[@"A"]},
        {"window of no document in front of B", @[settings, bSource], @[@"B"]},
        {"no document", @[settings], @[]},
        {"no window", @[], @[]},
    };
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        [bar removeAllItems]; [bar addItemWithTitle:@"stale" action:nil keyEquivalent:@""];
        orderedWindows = cases[i].windows;
        open();
        Check([Titles(bar) isEqual:cases[i].expected], [NSString stringWithFormat:@"Menu bar Tags menu, %s: %@", cases[i].what, Joined(Titles(bar))]);
    }
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
elif args.mutation == 'main-window-only':
    mutate('''        if ((! [owner isKindOfClass:[TSDocument class]]) && [window respondsToSelector:@selector(document)])
            owner = [(id)window document];
        if (! [owner isKindOfClass:[TSDocument class]])
            owner = [window delegate];
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
                    ('NO_ITEM', no_item), ('ITEMS', items), ('INSTALL', install), ('APP_MENUS', app_menus)):
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
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-w', '-framework', 'Cocoa', str(source), '-o', str(mac/'TagsMenuTest')], check=True)
    home = tmp/'Home'; (home/'Library/Preferences').mkdir(parents=True)
    try:
        result = subprocess.run([str(mac/'TagsMenuTest'), '-AppleLanguages', '(en)'], env={**os.environ, 'CFFIXED_USER_HOME': str(home)},
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
