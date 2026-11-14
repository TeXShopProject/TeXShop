// SPDX-License-Identifier: GPL-2.0-or-later
// The Advanced Find panel's actions on the main window's text view, and the buttons that show which of them that text
// view takes (no replacing in a read-only text view).
#import "TSAdvancedFindPanelController+Private.h"
#import "TSAdvancedFindTextView.h"
#import "TSMultipleReplaceMenu.h"

@implementation TSAdvancedFindPanelController (Actions)

#pragma mark Buttons

- (void)applicationDidUpdate:(NSNotification *)notification
{
    [self updateButtons];
}

/// The buttons show which actions the target text view takes now: no replacing in a read-only text view.
/// With no target they stay as they are and beep.
- (void)updateButtons
{
    if (!self.window.isVisible && !TSAdvancedFindController.testTargetTextView)
        return;
    static const TSAdvancedFindAction actions[] = {TSAdvancedFindActionFindAll, TSAdvancedFindActionReplaceAll,
                                                   TSAdvancedFindActionReplaceAndFind, TSAdvancedFindActionNext};
    NSArray<NSControl *> *buttons = self.buttons;
    for (NSUInteger index = 0; index < buttons.count && index < sizeof(actions) / sizeof(actions[0]); index++) {
        BOOL enabled = [self canPerform:actions[index]];
        if (buttons[index].enabled != enabled)
            buttons[index].enabled = enabled;
    }
}

- (BOOL)canPerform:(TSAdvancedFindAction)action
{
    NSTextView *target = [self targetTextView];
    return target ? [self.findController validateAction:action forTextView:target] : self.findController.runningTask == nil;
}

/// The actions under the ▾ of Find All and of Replace & Find.
- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if (item.action == @selector(advancedReplace:))
        return [self canPerform:TSAdvancedFindActionReplace];
    if (item.action == @selector(advancedHighlight:))
        return [self canPerform:TSAdvancedFindActionHighlight];
    if (item.action == @selector(advancedSelectAll:))
        return [self canPerform:TSAdvancedFindActionSelectAll];
    return YES;
}

#pragma mark Actions

/// The text view of the main window, which the panel acts on.
- (nullable NSTextView *)targetTextView
{
    return TSAdvancedFindController.targetTextView;
}

- (void)perform:(TSAdvancedFindAction)action
{
    NSTextView *target = [self targetTextView];
    if (!target) {
        self.findController.beepHandler();
        return;
    }
    BOOL done = [self.findController performAction:action inTextView:target];
    // Find All keeps the panel: its list is in the panel.
    if (done && self.findController.settings.closesWhenDone && action != TSAdvancedFindActionFindAll)
        [self.window orderOut:nil];
}

- (IBAction)advancedFindNext:(id)sender { [self perform:TSAdvancedFindActionNext]; }
- (IBAction)advancedFindAll:(id)sender { [self perform:TSAdvancedFindActionFindAll]; }
- (IBAction)advancedFindPrevious:(id)sender { [self perform:TSAdvancedFindActionPrevious]; }
- (IBAction)advancedReplace:(id)sender { [self perform:TSAdvancedFindActionReplace]; }
- (IBAction)advancedReplaceAndFind:(id)sender { [self perform:TSAdvancedFindActionReplaceAndFind]; }
- (IBAction)advancedReplaceAll:(id)sender { [self perform:TSAdvancedFindActionReplaceAll]; }
- (IBAction)advancedSelectAll:(id)sender { [self perform:TSAdvancedFindActionSelectAll]; }
- (IBAction)advancedHighlight:(id)sender { [self perform:TSAdvancedFindActionHighlight]; }
- (IBAction)advancedUnhighlight:(id)sender { [self perform:TSAdvancedFindActionUnhighlight]; }

- (void)performFindMenuAction:(nullable id)sender
{
    TSAdvancedFindAction action = (TSAdvancedFindAction)([sender respondsToSelector:@selector(tag)] ? [sender tag] : 0);
    switch (action) {
        case TSAdvancedFindActionShowFindPanel:
        case TSAdvancedFindActionShowReplacePanel:
            [self showPanelSelectingReplaceField:action == TSAdvancedFindActionShowReplacePanel];
            return;
        case TSAdvancedFindActionHidePanel:
        case TSAdvancedFindActionHideReplacePanel:
            [self.window orderOut:nil];
            return;
        default:
            [self perform:action];
    }
}

- (BOOL)validateFindMenuItem:(NSMenuItem *)item
{
    return [self canPerform:(TSAdvancedFindAction)item.tag];
}

- (IBAction)previousOrNext:(NSSegmentedControl *)sender
{
    [self perform:sender.selectedSegment == 0 ? TSAdvancedFindActionPrevious : TSAdvancedFindActionNext];
}

/// As the menu's Edit Multiple Replace…: the application's window, in front.
- (IBAction)showMultipleReplace:(nullable id)sender
{
    TSMultipleReplaceMenu *menu = TSMultipleReplaceMenu.sharedMenu;
    if (menu)
        [menu showMultipleReplace:sender];
    else
        self.findController.beepHandler();
}

@end
