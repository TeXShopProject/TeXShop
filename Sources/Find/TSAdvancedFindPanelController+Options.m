// SPDX-License-Identifier: GPL-2.0-or-later
// The "More Options" popover of the Advanced Find panel. The options themselves are TSAdvancedFindOptionsForm,
// shared with the multiple replacement sets.
#import "TSAdvancedFindPanelController+Private.h"

@implementation TSAdvancedFindPanelController (Options)

- (NSView *)makeOptionsView
{
    TSAdvancedFindSettings *settings = self.findController.settings;
    TSAdvancedFindOptionsForm *form = [[TSAdvancedFindOptionsForm alloc] initWithStyle:TSAdvancedFindOptionsFormStylePanel
                                                                         textualOptions:settings.options
                                                               regularExpressionOptions:settings.options
                                                                      replacementSyntax:settings.replacementSyntax];
    __weak typeof(self) weakSelf = self;
    form.changeHandler = ^(TSAdvancedFindOptionsForm *changed) {
        // The panel keeps one set of options: the text section's bits come from one side, the rest from the other.
        TSRegexFindOptions text = TSAdvancedFindOptionsForm.textualItemOptions;
        TSAdvancedFindSettings *current = weakSelf.findController.settings;
        current.options = (changed.regularExpressionOptions & ~text) | (changed.textualOptions & text);
        current.replacementSyntax = changed.replacementSyntax;
        [weakSelf optionsDidChange];
    };
    NSButton *wrap = [self checkBox:@"AdvancedFind.Wrap" english:@"Wrap around"];
    wrap.state = settings.wraps ? NSControlStateValueOn : NSControlStateValueOff;
    self.wrapBox = wrap;
    NSButton *top = [self checkBox:@"AdvancedFind.StartsFromTop" english:@"Start the next search at the top"];
    top.identifier = @"startsFromTop";
    top.state = settings.startsFromTop ? NSControlStateValueOn : NSControlStateValueOff;
    NSButton *close = [self checkBox:@"AdvancedFind.ClosesWhenDone" english:@"Close the panel after finding"];
    close.identifier = @"closesWhenDone";
    close.state = settings.closesWhenDone ? NSControlStateValueOn : NSControlStateValueOff;
    [form insertTitle:TSLocalized(@"AdvancedFind.OptionsTitle", @"Find Options") rows:@[wrap, top, close]];
    self.optionsForm = form;
    return form.view;
}

/// Text options work without regular expressions, regular expression options with them, as in CotEditor.
- (void)updateModeControls
{
    self.optionsForm.usesRegularExpression = (self.findController.settings.options & TSRegexFindRegularExpression) != 0;
}

- (NSViewController *)makeOptionsViewController
{
    NSViewController *controller = [NSViewController new];
    NSView *view = [self makeOptionsView];
    [view layoutSubtreeIfNeeded];
    // Without its own size the popover would squeeze the rows; this is also the size of the images.
    controller.preferredContentSize = view.fittingSize;
    [view setFrameSize:view.fittingSize];
    controller.view = view;
    return controller;
}

- (void)showOptions:(NSButton *)sender
{
    NSViewController *controller = [self makeOptionsViewController];
    self.optionsPopover = [NSPopover new];
    self.optionsPopover.behavior = NSPopoverBehaviorTransient;
    self.optionsPopover.contentViewController = controller;
    self.optionsPopover.contentSize = controller.preferredContentSize;
    [self.optionsPopover showRelativeToRect:sender.bounds ofView:sender preferredEdge:NSRectEdgeMaxY];
}

@end
