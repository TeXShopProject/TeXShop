// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSMarkMenu.h"

static NSMenuItem *TSItemWithSubmenuAction(NSMenu *menu, SEL action)
{
    for (NSMenuItem *item in menu.itemArray) {
        if (item.submenu == nil) continue;
        for (NSMenuItem *child in item.submenu.itemArray)
            if (child.action == action) return item;
        NSMenuItem *found = TSItemWithSubmenuAction(item.submenu, action);
        if (found) return found;
    }
    return nil;
}

static NSMenuItem *TSItemWithAction(NSMenu *menu, SEL action)
{
    for (NSMenuItem *item in menu.itemArray) if (item.action == action) return item;
    return nil;
}

@implementation TSMarkMenu

+ (instancetype)sharedInstance
{
    static TSMarkMenu *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [self new]; });
    return shared;
}

+ (void)installInMenu:(NSMenu *)mainMenu
{
    NSMenuItem *markItem = TSItemWithSubmenuAction(mainMenu, @selector(doNextBullet:));
    NSMenuItem *editItem = nil;
    for (NSMenuItem *item in mainMenu.itemArray)
        if (item.submenu && TSItemWithAction(item.submenu, @selector(undo:))) { editItem = item; break; }
    if (markItem == nil || editItem == nil) return;
    NSMenu *edit = editItem.submenu, *marks = markItem.submenu;
    // The nibs place Mark in Edit, after Find. Moving it at run time would cost
    // Next Mark its ⌃⌘F, which AppKit refuses for items added to the main menu,
    // so this is only a fallback for a nib that still has the old place.
    if (markItem.menu != edit) {
        [markItem.menu removeItem:markItem];
        NSInteger index = edit.numberOfItems;
        for (NSInteger i = 0; i < edit.numberOfItems; i++)
            if ([edit itemAtIndex:i].submenu) { index = i + 1; break; }
        [edit insertItem:markItem atIndex:index];
    }
    NSMenuItem *note = TSItemWithAction(marks, @selector(placeComment:));
    if (note) { note.alternate = NO; note.title = NSLocalizedString(@"Insert Mark with Note", @"Edit › Mark"); }
    NSDictionary<NSString *, NSString *> *tips = @{
        @"placeBullet:": NSLocalizedString(@"Inserts a mark (•) to come back to later.", @"Edit › Mark tooltip"),
        @"placeComment:": NSLocalizedString(@"Inserts a mark with a note (•‹note›). Selected text becomes the note.", @"Edit › Mark tooltip"),
        @"doNextBullet:": NSLocalizedString(@"Selects the next mark, with its note; typing replaces it.", @"Edit › Mark tooltip"),
        @"doPreviousBullet:": NSLocalizedString(@"Selects the previous mark, with its note; typing replaces it.", @"Edit › Mark tooltip"),
        @"doNextBulletAndDelete:": NSLocalizedString(@"Deletes the next • and selects its note, if it has one.", @"Edit › Mark tooltip"),
        @"doPreviousBulletAndDelete:": NSLocalizedString(@"Deletes the previous • and selects its note, if it has one.", @"Edit › Mark tooltip")};
    for (NSMenuItem *item in marks.itemArray) {
        NSString *tip = item.action ? tips[NSStringFromSelector(item.action)] : nil;
        if (tip) item.toolTip = tip;
    }
    if (TSItemWithAction(marks, @selector(showMarkHelp:)) == nil) {
        NSMenuItem *help = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"How to Use Marks…", @"Edit › Mark") action:@selector(showMarkHelp:) keyEquivalent:@""];
        help.target = [self sharedInstance];
        help.identifier = @"TSShortcut.showMarkHelp:.0";
        [marks addItem:[NSMenuItem separatorItem]];
        [marks addItem:help];
    }
}

+ (NSString *)markGuide
{
    NSString *editTitle = NSLocalizedString(@"Edit", @"Edit menu"), *markTitle = NSLocalizedString(@"Marks", @"Edit › Mark");
    NSMenu *main = NSApp.mainMenu;
    NSMenuItem *markItem = main ? TSItemWithSubmenuAction(main, @selector(doNextBullet:)) : nil;
    if (markItem) {
        markTitle = markItem.title;
        NSMenu *parent = markItem.menu.supermenu;
        NSInteger index = parent ? [parent indexOfItemWithSubmenu:markItem.menu] : -1;
        if (index >= 0) editTitle = [parent itemAtIndex:index].title;
    }
    return [NSString stringWithFormat:NSLocalizedString(@"• = mark, •‹note› = mark with a note; %@ › %@ moves between them.", @"Mark guide below the macro and key binding editors"), editTitle, markTitle];
}

+ (NSURL *)markHelpPageForLocalization:(NSString *)localization inBundle:(NSBundle *)bundle
{
    if ([localization isEqualToString:@"en"])
        return nil;
    NSURL *page = [bundle URLForResource:@"basic_commandcompletion" withExtension:@"htm" subdirectory:@"TeXShopHelp/pgs" localization:@"en"];
    if (page == nil)
        return nil;
    NSURLComponents *components = [NSURLComponents componentsWithURL:page resolvingAgainstBaseURL:NO];
    components.fragment = @"marks";
    return components.URL;
}

- (IBAction)showMarkHelp:(id)sender
{
    NSBundle *bundle = NSBundle.mainBundle;
    NSURL *page = [TSMarkMenu markHelpPageForLocalization:bundle.preferredLocalizations.firstObject ?: @"en" inBundle:bundle];
    if (page) {
        [NSWorkspace.sharedWorkspace openURL:page];
        return;
    }
    NSString *book = [bundle objectForInfoDictionaryKey:@"CFBundleHelpBookName"];
    [NSHelpManager.sharedHelpManager openHelpAnchor:@"marks" inBook:book];
}

@end
