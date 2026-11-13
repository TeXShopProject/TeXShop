// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSAdvancedFindPanelController+Private.h"
#import "TSRegexFindPattern.h"
#import "TSAdvancedFindTextView.h"

@implementation TSAdvancedFindFieldView

- (TSAdvancedFindPanelController *)panelController
{
    id controller = self.window.windowController;
    return [controller isKindOfClass:[TSAdvancedFindPanelController class]] ? controller : nil;
}

- (void)performFindPanelAction:(id)sender
{
    TSAdvancedFindPanelController *controller = [self panelController];
    if (controller)
        [controller performFindMenuAction:sender];
    else
        [super performFindPanelAction:sender];
}

- (void)performTextFinderAction:(id)sender
{
    [self performFindPanelAction:sender];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    TSAdvancedFindPanelController *controller = [self panelController];
    if (controller && (item.action == @selector(performFindPanelAction:) || item.action == @selector(performTextFinderAction:)))
        return [controller validateFindMenuItem:item];
    return [super validateMenuItem:item];
}

- (BOOL)resignFirstResponder
{
    BOOL resigned = [super resignFirstResponder];
    if (resigned)
        self.box.focused = NO;
    return resigned;
}
- (void)insertTab:(id)sender { [self.window selectNextKeyView:self]; }
- (void)insertBacktab:(id)sender { [self.window selectPreviousKeyView:self]; }
- (void)insertTabIgnoringFieldEditor:(id)sender { [self insertText:@"\t" replacementRange:self.selectedRange]; }
- (void)insertNewlineIgnoringFieldEditor:(id)sender { [self insertText:@"\n" replacementRange:self.selectedRange]; }
- (void)insertNewline:(id)sender { [NSApp sendAction:@selector(advancedFindNext:) to:self.window.windowController from:self]; }
- (BOOL)becomeFirstResponder
{
    BOOL accepted = [super becomeFirstResponder];
    if (accepted) {
        [self selectAll:nil];
        self.box.focused = YES;
    }
    return accepted;
}
@end


@implementation TSAdvancedFindPanelController

static TSAdvancedFindPanelController *TSSharedPanelController;

+ (TSAdvancedFindPanelController *)sharedPanelController
{
    if (!TSSharedPanelController)
        TSSharedPanelController = [[TSAdvancedFindPanelController alloc] initWithFindController:TSAdvancedFindController.sharedController];
    return TSSharedPanelController;
}

+ (BOOL)hasSharedPanelController
{
    return TSSharedPanelController != nil;
}

- (instancetype)initWithFindController:(TSAdvancedFindController *)findController
{
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 600, 300)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow
                                                  backing:NSBackingStoreBuffered defer:YES];
    panel.title = TSLocalized(@"AdvancedFind.Title", @"Find and Replace");
    panel.floatingPanel = YES;
    panel.hidesOnDeactivate = YES;
    panel.becomesKeyOnlyIfNeeded = NO;
    panel.contentMinSize = NSMakeSize(560, 250);
    if (!(self = [super initWithWindow:panel]))
        return nil;
    _findController = findController;
    _showsResults = YES;
    _resultsHeight = 260;
    [self buildContent];
    [panel center];
    self.windowFrameAutosaveName = @"AdvancedFindPanel"; // "NSWindow Frame AdvancedFindPanel", kept by the profiles
    __weak typeof(self) weakSelf = self;
    // Results ("3 of 12", "Not found") go into the find field, errors to the message line below the options.
    findController.statusHandler = ^(NSString *message, BOOL isError) {
        if (isError)
            [weakSelf showStatus:message color:NSColor.systemRedColor];
        else
            weakSelf.findBox.statusLabel.stringValue = message;
    };
    findController.showPanelHandler = ^(BOOL replacing) { [weakSelf showPanelSelectingReplaceField:replacing]; };
    findController.hidePanelHandler = ^{ [weakSelf.window orderOut:nil]; };
    findController.stringsChangedHandler = ^{ [weakSelf loadStrings]; };
    findController.findAllHandler = ^(TSAdvancedFindResults *results, NSTextView *textView) { [weakSelf showResults:results textView:textView]; };
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];
    // A long action starts or ends: every button is gray meanwhile, since every action is refused.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidUpdate:) name:TSAdvancedFindTaskDidChangeNotification object:findController];
    // After every event, as menu items are: the target may have changed (another window) or become read-only.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidUpdate:) name:NSApplicationDidUpdateNotification object:nil];
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark Building

- (TSAdvancedFindFieldView *)makeField
{
    TSAdvancedFindFieldView *field = [[TSAdvancedFindFieldView alloc] initWithFrame:NSMakeRect(0, 0, 400, 40)];
    field.richText = NO;
    field.importsGraphics = NO;
    field.allowsUndo = YES;
    field.automaticQuoteSubstitutionEnabled = NO;
    field.automaticDashSubstitutionEnabled = NO;
    field.automaticTextReplacementEnabled = NO;
    field.automaticSpellingCorrectionEnabled = NO;
    field.continuousSpellCheckingEnabled = NO;
    field.font = [NSFont monospacedSystemFontOfSize:NSFont.systemFontSize + 1 weight:NSFontWeightRegular];
    field.textContainerInset = NSMakeSize(0, 4);
    field.verticallyResizable = YES;
    field.horizontallyResizable = NO;
    field.autoresizingMask = NSViewWidthSizable;
    field.textContainer.widthTracksTextView = YES;
    field.delegate = self;
    return field;
}

- (TSAdvancedFindInputBox *)boxForField:(TSAdvancedFindFieldView *)field symbol:(NSString *)symbol tag:(NSInteger)tag
{
    TSAdvancedFindInputBox *box = [[TSAdvancedFindInputBox alloc] initWithTextView:field symbolName:symbol
                                                                     historyTitle:TSLocalized(@"AdvancedFind.History", @"Recent Strings")];
    box.historyButton.target = self;
    box.historyButton.action = @selector(showHistory:);
    box.historyButton.tag = tag;
    field.box = box;
    return box;
}

- (NSButton *)checkBox:(NSString *)key english:(NSString *)english
{
    return [NSButton checkboxWithTitle:TSLocalized(key, english) target:self action:@selector(optionChanged:)];
}

- (NSButton *)button:(NSString *)key english:(NSString *)english action:(SEL)action
{
    return [NSButton buttonWithTitle:TSLocalized(key, english) target:self action:action];
}

/// The options in daily use, small and close under the fields, as in CotEditor; the rest behind "…" on the right.
- (NSView *)makeOptionsRow
{
    self.regexBox = [self checkBox:@"AdvancedFind.RegularExpression" english:@"Regular expression"];
    self.ignoreCaseBox = [self checkBox:@"AdvancedFind.IgnoreCase" english:@"Ignore case"];
    self.inSelectionBox = [self checkBox:@"AdvancedFind.InSelection" english:@"In selection"];
    for (NSButton *box in @[self.regexBox, self.ignoreCaseBox, self.inSelectionBox]) {
        box.controlSize = NSControlSizeSmall;
        box.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    }
    NSImage *moreImage = [NSImage imageWithSystemSymbolName:@"ellipsis.circle" accessibilityDescription:TSLocalized(@"AdvancedFind.MoreOptions", @"More Options")] ?: [NSImage new];
    NSButton *more = [NSButton buttonWithImage:moreImage target:self action:@selector(showOptions:)];
    more.controlSize = NSControlSizeSmall;
    more.toolTip = TSLocalized(@"AdvancedFind.MoreOptions", @"More Options");
    // The cheat sheet's "?" right after "Regular expression"
    self.cheatSheetButton = [NSButton buttonWithTitle:@"" target:self action:@selector(showCheatSheet:)];
    self.cheatSheetButton.bezelStyle = NSBezelStyleHelpButton;
    self.cheatSheetButton.controlSize = NSControlSizeMini;
    self.cheatSheetButton.toolTip = TSLocalized(@"AdvancedFind.CheatSheetTip", @"Show the regular expression reference");
    self.cheatSheetButton.accessibilityLabel = TSLocalized(@"AdvancedFind.Cheat.Title", @"Regular Expression Reference");
    NSStackView *regex = [NSStackView stackViewWithViews:@[self.regexBox, self.cheatSheetButton]];
    regex.spacing = 4;
    regex.alignment = NSLayoutAttributeCenterY;
    [regex setHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *row = [NSStackView stackViewWithViews:@[regex, self.ignoreCaseBox, self.inSelectionBox]];
    row.spacing = 16;
    [row addView:more inGravity:NSStackViewGravityTrailing];
    return row;
}

/// As in CotEditor: the actions on all matches on the left, those on the current match on the right, ending with
/// previous / next. A button with ▾ has more actions of its kind: Highlight All and Select All under Find All, with
/// Remove Highlights after them (TeXShop's Find menu has no item for it), Replace (without finding on) under
/// Replace & Find. Return in the find field is "Next".
- (NSView *)makeButtonRow
{
    NSMenu *allMenu = [[NSMenu alloc] initWithTitle:@""];
    [allMenu addItemWithTitle:TSLocalized(@"AdvancedFind.HighlightAll", @"Highlight All") action:@selector(advancedHighlight:) keyEquivalent:@""].target = self;
    [allMenu addItemWithTitle:TSLocalized(@"AdvancedFind.SelectAll", @"Select All") action:@selector(advancedSelectAll:) keyEquivalent:@""].target = self;
    [allMenu addItem:NSMenuItem.separatorItem];
    [allMenu addItemWithTitle:TSLocalized(@"AdvancedFind.Unhighlight", @"Remove Highlights") action:@selector(advancedUnhighlight:) keyEquivalent:@""].target = self;
    NSComboButton *findAll = [NSComboButton comboButtonWithTitle:TSLocalized(@"AdvancedFind.FindAll", @"Find All") menu:allMenu
                                                          target:self action:@selector(advancedFindAll:)];
    findAll.toolTip = TSLocalized(@"AdvancedFind.FindAllTip", @"Find and list all matches.");
    NSButton *replaceAll = [self button:@"AdvancedFind.ReplaceAll" english:@"Replace All" action:@selector(advancedReplaceAll:)];
    NSMenu *replaceMenu = [[NSMenu alloc] initWithTitle:@""];
    [replaceMenu addItemWithTitle:TSLocalized(@"AdvancedFind.Replace", @"Replace") action:@selector(advancedReplace:) keyEquivalent:@""].target = self;
    NSComboButton *replace = [NSComboButton comboButtonWithTitle:TSLocalized(@"AdvancedFind.ReplaceAndFind", @"Replace & Find") menu:replaceMenu
                                                          target:self action:@selector(advancedReplaceAndFind:)];
    replace.toolTip = TSLocalized(@"AdvancedFind.ReplaceAndFindTip", @"Replace the selection, then find the next match.");
    NSImage *left = [NSImage imageWithSystemSymbolName:@"chevron.left" accessibilityDescription:TSLocalized(@"AdvancedFind.Previous", @"Previous")] ?: [NSImage new];
    NSImage *right = [NSImage imageWithSystemSymbolName:@"chevron.right" accessibilityDescription:TSLocalized(@"AdvancedFind.Next", @"Next")] ?: [NSImage new];
    NSSegmentedControl *previousNext = [NSSegmentedControl segmentedControlWithImages:@[left, right] trackingMode:NSSegmentSwitchTrackingMomentary
                                                                               target:self action:@selector(previousOrNext:)];
    [previousNext setToolTip:TSLocalized(@"AdvancedFind.Previous", @"Previous") forSegment:0];
    [previousNext setToolTip:TSLocalized(@"AdvancedFind.Next", @"Next") forSegment:1];
    [previousNext setWidth:36 forSegment:0];
    [previousNext setWidth:36 forSegment:1];
    self.buttons = @[findAll, replaceAll, replace, previousNext];
    NSStackView *row = [NSStackView stackViewWithViews:@[findAll, replaceAll]];
    row.spacing = 12;
    for (NSView *view in @[replace, previousNext])
        [row addView:view inGravity:NSStackViewGravityTrailing];
    return row;
}

- (void)buildContent
{
    self.findFieldView = [self makeField];
    self.replaceFieldView = [self makeField];
    self.findBox = [self boxForField:self.findFieldView symbol:@"magnifyingglass" tag:0];
    self.replaceBox = [self boxForField:self.replaceFieldView symbol:@"pencil" tag:1];
    self.findBox.textView.accessibilityLabel = TSLocalized(@"AdvancedFind.FindLabel", @"Find:");
    self.replaceBox.textView.accessibilityLabel = TSLocalized(@"AdvancedFind.ReplaceLabel", @"Replace:");

    NSView *options = [self makeOptionsRow];
    NSView *buttons = [self makeButtonRow];
    self.status = [NSTextField labelWithString:@""];
    self.status.textColor = NSColor.secondaryLabelColor;
    self.status.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    self.status.lineBreakMode = NSLineBreakByTruncatingTail;
    self.status.selectable = YES;
    [self.status setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.resultsView = [[TSAdvancedFindResultsView alloc] initWithSettings:self.findController.settings];
    self.resultsView.hidden = YES;
    __weak typeof(self) weakSelf = self;
    self.resultsView.closeHandler = ^{ [weakSelf hideResults]; };

    // The two fields take the room the window grows by, in equal shares; the rows below keep their size.
    // The list of all matches, when shown, runs from edge to edge and takes the room instead (+Results).
    NSStackView *content = [NSStackView stackViewWithViews:@[self.findBox, self.replaceBox, options, self.resultsView, buttons]];
    content.orientation = NSUserInterfaceLayoutOrientationVertical;
    content.alignment = NSLayoutAttributeCenterX;
    content.distribution = NSStackViewDistributionFill;
    content.spacing = 10;
    content.edgeInsets = NSEdgeInsetsMake(20, 0, 20, 0);
    // The options sit close under the fields, as in CotEditor.
    [content setCustomSpacing:5 afterView:self.replaceBox];
    [content setCustomSpacing:20 afterView:options];
    [content setCustomSpacing:0 afterView:self.resultsView]; // the list has its own room above the buttons
    for (NSView *view in @[self.findBox, self.replaceBox, options, self.resultsView, buttons]) {
        [view.widthAnchor constraintEqualToAnchor:content.widthAnchor constant:view == self.resultsView ? 0 : -40].active = YES;
        if (view != self.findBox && view != self.replaceBox && view != self.resultsView)
            [view setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    }
    [self.findBox.heightAnchor constraintEqualToAnchor:self.replaceBox.heightAnchor].active = YES;
    // Errors and notes on the pattern go into the room under the options: an empty line takes no room of its own.
    self.status.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:self.status];
    [NSLayoutConstraint activateConstraints:@[
        [self.status.topAnchor constraintEqualToAnchor:options.bottomAnchor constant:3],
        [self.status.leadingAnchor constraintEqualToAnchor:options.leadingAnchor],
        [self.status.trailingAnchor constraintLessThanOrEqualToAnchor:options.trailingAnchor],
    ]];
    self.window.contentView = content;
    self.window.contentMinSize = NSMakeSize(MAX(560, content.fittingSize.width), 250);
    self.window.initialFirstResponder = self.findFieldView;
    self.findFieldView.nextKeyView = self.replaceFieldView;
    self.replaceFieldView.nextKeyView = self.regexBox;
}

#pragma mark State

- (NSTextView *)findField { return self.findFieldView; }
- (NSTextView *)replaceField { return self.replaceFieldView; }
- (NSTextField *)statusField { return self.status; }
- (NSArray<NSButton *> *)optionBoxes { return @[self.regexBox, self.ignoreCaseBox, self.inSelectionBox]; }

- (void)showStatus:(NSString *)message color:(nullable NSColor *)color
{
    self.status.stringValue = message;
    self.status.toolTip = message.length > 0 ? message : nil; // the line may be cut
    self.status.textColor = color ?: NSColor.secondaryLabelColor;
}

- (void)reloadFromSettings
{
    [self loadStrings];
    [self loadOptions];
}

- (void)loadStrings
{
    if (![self.findFieldView.string isEqualToString:self.findController.settings.findString])
        self.findFieldView.string = self.findController.settings.findString;
    if (![self.replaceFieldView.string isEqualToString:self.findController.settings.replaceString])
        self.replaceFieldView.string = self.findController.settings.replaceString;
    [self.findBox textDidChange];
    [self.replaceBox textDidChange];
    [self validatePattern];
}

- (void)loadOptions
{
    TSAdvancedFindSettings *settings = self.findController.settings;
    self.regexBox.state = (settings.options & TSRegexFindRegularExpression) ? NSControlStateValueOn : NSControlStateValueOff;
    self.ignoreCaseBox.state = (settings.options & TSRegexFindIgnoreCase) ? NSControlStateValueOn : NSControlStateValueOff;
    self.wrapBox.state = settings.wraps ? NSControlStateValueOn : NSControlStateValueOff;
    self.inSelectionBox.state = settings.inSelection ? NSControlStateValueOn : NSControlStateValueOff;
    [self validatePattern];
    [self updateCheatSheet];
}

- (void)showPanel
{
    [self showPanelSelectingReplaceField:NO];
}

- (void)showPanelSelectingReplaceField:(BOOL)replacing
{
    [self.findController.settings reloadFindStringFromPasteboard];
    [self reloadFromSettings];
    [self showWindow:nil];
    [self.window makeFirstResponder:nil];
    [self.window makeFirstResponder:replacing ? self.replaceFieldView : self.findFieldView];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    if (!self.window.isVisible)
        return;
    [self.findController.settings reloadFindStringFromPasteboard];
    [self loadStrings];
}

/// The engine's error on the find pattern, in the line under the options.
- (void)validatePattern
{
    TSAdvancedFindSettings *settings = self.findController.settings;
    NSError *error = nil;
    if ((settings.options & TSRegexFindRegularExpression) && settings.findString.length > 0
        && ![[TSRegexFindPattern alloc] initWithFindString:settings.findString options:settings.options error:&error])
        [self showStatus:error.localizedDescription color:NSColor.systemRedColor];
    else if (self.status.stringValue.length > 0)
        [self showStatus:@"" color:nil];
}

- (void)optionChanged:(NSControl *)sender
{
    TSAdvancedFindSettings *settings = self.findController.settings;
    TSRegexFindOptions options = settings.options;
    BOOL on = [sender isKindOfClass:[NSButton class]] && ((NSButton *)sender).state == NSControlStateValueOn;
    if (sender == self.regexBox)
        options = on ? options | TSRegexFindRegularExpression : options & ~TSRegexFindRegularExpression;
    else if (sender == self.ignoreCaseBox)
        options = on ? options | TSRegexFindIgnoreCase : options & ~TSRegexFindIgnoreCase;
    else if (sender == self.wrapBox)
        settings.wraps = on;
    else if (sender == self.inSelectionBox)
        settings.inSelection = on;
    else if ([sender.identifier isEqualToString:@"startsFromTop"])
        settings.startsFromTop = on;
    else if ([sender.identifier isEqualToString:@"closesWhenDone"])
        settings.closesWhenDone = on;
    settings.options = options;
    [self optionsDidChange];
}

- (void)optionsDidChange
{
    [self updateModeControls];
    [self validatePattern];
    [self updateCheatSheet];
}

#pragma mark Text fields

- (void)textDidChange:(NSNotification *)notification
{
    [self.findBox textDidChange];
    [self.replaceBox textDidChange];
    if (notification.object == self.findFieldView) {
        self.findController.settings.findString = self.findFieldView.string;
        self.findBox.statusLabel.stringValue = @""; // the last result no longer applies
        [self validatePattern];
        if ([NSUserDefaults.standardUserDefaults boolForKey:@"IncrementalSearch"]) {
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(incrementalSearch) object:nil];
            [self performSelector:@selector(incrementalSearch) withObject:nil afterDelay:0.2];
        }
    } else if (notification.object == self.replaceFieldView) {
        self.findController.settings.replaceString = self.replaceFieldView.string;
    }
}

- (void)incrementalSearch
{
    NSTextView *target = [self targetTextView];
    if (target)
        [self.findController incrementalSearchInTextView:target];
}

@end
