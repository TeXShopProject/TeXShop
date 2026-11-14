// SPDX-License-Identifier: GPL-2.0-or-later
// The regular expression cheat sheet of the Advanced Find panel, behind the "?" next to "Regular expression".
#import "TSAdvancedFindPanelController+Private.h"

@implementation TSAdvancedFindPanelController (CheatSheet)

- (TSAdvancedFindCheatSheet *)makeCheatSheet
{
    TSAdvancedFindCheatSheet *sheet = [[TSAdvancedFindCheatSheet alloc] initWithReplacementSyntax:self.findController.settings.replacementSyntax];
    [sheet view];
    return sheet;
}

/// The "?" opens the cheat sheet, or closes it when it is open; dragged off, it stays as a window of its own.
- (void)showCheatSheet:(nullable id)sender
{
    if (self.cheatSheetPopover.isShown) {
        [self.cheatSheetPopover close];
        return;
    }
    TSAdvancedFindCheatSheet *sheet = [self makeCheatSheet];
    self.cheatSheetPopover = [NSPopover new];
    self.cheatSheetPopover.behavior = NSPopoverBehaviorTransient;
    self.cheatSheetPopover.contentViewController = sheet; // its size follows the sheet's preferredContentSize
    self.cheatSheetPopover.delegate = self;
    [self.cheatSheetPopover showRelativeToRect:self.cheatSheetButton.bounds ofView:self.cheatSheetButton preferredEdge:NSRectEdgeMaxY];
}

- (BOOL)popoverShouldDetach:(NSPopover *)popover
{
    return popover == self.cheatSheetPopover;
}

- (void)updateCheatSheet
{
    TSAdvancedFindCheatSheet *sheet = (TSAdvancedFindCheatSheet *)self.cheatSheetPopover.contentViewController;
    if (![sheet isKindOfClass:[TSAdvancedFindCheatSheet class]])
        return;
    sheet.replacementSyntax = self.findController.settings.replacementSyntax;
}

@end
