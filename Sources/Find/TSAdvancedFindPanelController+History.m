// SPDX-License-Identifier: GPL-2.0-or-later
// The recent find and replacement strings of the Advanced Find panel, in the menus of the fields' icons.
#import "TSAdvancedFindPanelController+Private.h"

@implementation TSAdvancedFindPanelController (History)

#pragma mark History

/// The recent strings of a field (tag 0: find, 1: replace) under a gray title, as in CotEditor, one step smaller
/// than a menu's own 13 points (the user found 13 points a step larger than CotEditor's history menu).
- (NSMenu *)historyMenuForField:(NSInteger)tag
{
    BOOL find = tag == 0;
    TSAdvancedFindSettings *settings = self.findController.settings;
    NSArray<NSString *> *history = find ? settings.findHistory : settings.replaceHistory;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    menu.font = [NSFont menuFontOfSize:NSFont.systemFontSize - 1];
    menu.autoenablesItems = NO; // the clear item is off when there is nothing to clear
    [menu addItem:[NSMenuItem sectionHeaderWithTitle:find ? TSLocalized(@"AdvancedFind.FindHistory", @"Recent Searches")
                                                         : TSLocalized(@"AdvancedFind.ReplaceHistory", @"Recent Replacements")]];
    if (history.count == 0)
        [menu addItemWithTitle:TSLocalized(@"AdvancedFind.NoHistory", @"No Recent Strings") action:NULL keyEquivalent:@""].enabled = NO;
    for (NSString *string in history) {
        NSString *title = [string stringByReplacingOccurrencesOfString:@"\n" withString:@"⏎"];
        NSMenuItem *item = [menu addItemWithTitle:title action:@selector(chooseHistory:) keyEquivalent:@""];
        item.representedObject = string;
        item.tag = tag;
        item.target = self;
    }
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *clear = [menu addItemWithTitle:find ? TSLocalized(@"AdvancedFind.ClearFindHistory", @"Clear Recent Searches")
                                                    : TSLocalized(@"AdvancedFind.ClearReplaceHistory", @"Clear Recent Replacements")
                                        action:@selector(clearHistory:) keyEquivalent:@""];
    clear.tag = tag;
    clear.target = self;
    clear.enabled = history.count > 0;
    return menu;
}

/// The recent strings of the field, under its icon; choosing one puts it into the field.
- (void)showHistory:(NSButton *)sender
{
    NSMenu *menu = [self historyMenuForField:sender.tag];
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight(sender.bounds) + 4) inView:sender];
}

- (void)chooseHistory:(NSMenuItem *)sender
{
    NSString *string = sender.representedObject;
    if (!string)
        return;
    if (sender.tag == 0)
        self.findController.settings.findString = string;
    else
        self.findController.settings.replaceString = string;
    [self loadStrings];
}

/// Clears the recent strings of one field (the menu item's tag), as CotEditor's "Clear Recent Searches" does.
- (void)clearHistory:(NSMenuItem *)sender
{
    if (sender.tag == 0)
        [self.findController.settings clearFindHistory];
    else
        [self.findController.settings clearReplaceHistory];
}

@end
