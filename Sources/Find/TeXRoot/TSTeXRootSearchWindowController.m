// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSTeXRootSearchWindowController.h"
#import "TSAdvancedFindPanelController+Private.h"
#import "TSAdvancedFindOptionsForm.h"
#import "TSAdvancedFindFieldStyle.h"
#import "TSRegexMultipleReplace.h"
#import "TSRegexFindPattern.h"

#define TSLocalized TSAdvancedFindLocalized

/// The window's fields: Escape and ⌘. stop a long task, as anywhere in the window, rather than completing the word.
@interface TSTeXRootSearchFieldView : TSAdvancedFindFieldView
@end

@implementation TSTeXRootSearchFieldView
- (void)cancelOperation:(nullable id)sender
{
    TSTeXRootSearchWindowController *controller = self.window.windowController;
    if ([controller isKindOfClass:[TSTeXRootSearchWindowController class]] && controller.model.activity != TSTeXRootSearchActivityIdle)
        [controller cancelOperation:sender];
    else
        [super cancelOperation:sender];
}
@end

@interface TSTeXRootSearchWindowController ()
@property (nonatomic, readwrite, nullable) TSTeXRootSearchModel *model;
@property (nonatomic, strong) NSSegmentedControl *modeControl;
@property (nonatomic, strong) NSTextField *rootLabel;
@property (nonatomic, strong) NSTextField *explanationLabel;
@property (nonatomic, strong) NSButton *helpButton;
@property (nonatomic, strong) NSButton *refreshButton;
@property (nonatomic, strong) TSAdvancedFindFieldView *findFieldView;
@property (nonatomic, strong) TSAdvancedFindFieldView *replaceFieldView;
@property (nonatomic, strong) TSAdvancedFindInputBox *findBox;
@property (nonatomic, strong) TSAdvancedFindInputBox *replaceBox;
@property (nonatomic, strong) NSView *optionsRow;
@property (nonatomic, strong) NSView *setRow;
@property (nonatomic, strong) NSButton *regexBox;
@property (nonatomic, strong) NSButton *ignoreCaseBox;
@property (nonatomic, strong) NSButton *moreOptionsButton;
@property (nonatomic, strong, nullable) NSPopover *popover;
@property (nonatomic, strong, nullable) TSAdvancedFindOptionsForm *optionsForm;
@property (nonatomic, strong) NSPopUpButton *setPopUp;
@property (nonatomic, strong) NSTextField *ruleCountLabel;
@property (nonatomic, strong) NSButton *editSetButton;
@property (nonatomic, copy, nullable) NSString *setName;
@property (nonatomic, strong) NSProgressIndicator *spinner;
@property (nonatomic, strong) NSButton *stopButton;
@property (nonatomic, strong) NSTextField *statusField;
@property (nonatomic, strong) NSButton *unreadableButton;
@property (nonatomic, strong) NSButton *backupBox;
@property (nonatomic, strong) NSButton *replaceAllButton;
@property (nonatomic, strong) NSStackView *topStack;
@property (nonatomic, strong) NSStackView *bottomStack;
@property (nonatomic, strong) NSSplitView *splitView;
@property (nonatomic, strong, nullable) TSTeXRootSearchFileTree *fileTree;
@property (nonatomic, strong, nullable) TSTeXRootSearchResultsList *resultsList;
@property (nonatomic, strong) NSView *treeHolder;
@property (nonatomic, strong) NSView *resultsHolder;
/// What the list shows, to rebuild it only when the results or the mode changed.
@property (nonatomic, copy, nullable) NSArray *shownResults;
@property (nonatomic) TSTeXRootSearchMode shownMode;
@property (nonatomic) BOOL showsAnyResults;
@property (nonatomic) BOOL updatePending;
@end

@implementation TSTeXRootSearchWindowController

- (instancetype)initWithFindController:(TSAdvancedFindController *)findController library:(TSMultipleReplaceLibrary *)library
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 580)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                             | NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered defer:YES];
    window.title = TSLocalized(@"TeXRootSearch.Title", @"Find in TeX Sources");
    window.contentMinSize = NSMakeSize(720, 420);
    window.releasedWhenClosed = NO;
    if (!(self = [super initWithWindow:window]))
        return nil;
    _findController = findController;
    _library = library;
    [self buildContent];
    [window center];
    self.windowFrameAutosaveName = @"TeXRootSearchWindow";
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(settingsDidChange:) name:TSAdvancedFindSettingsDidChangeNotification object:findController.settings];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(libraryDidChange:) name:TSMultipleReplaceLibraryDidChangeNotification object:library];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(fieldStyleDidChange:) name:TSAdvancedFindFieldStyleDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(windowWillClose:) name:NSWindowWillCloseNotification object:window];
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark Building

- (NSButton *)checkBox:(NSString *)key english:(NSString *)english action:(SEL)action
{
    NSButton *box = [NSButton checkboxWithTitle:TSLocalized(key, english) target:self action:action];
    box.controlSize = NSControlSizeSmall;
    box.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    return box;
}

- (NSTextField *)smallLabel
{
    NSTextField *label = [NSTextField labelWithString:@""];
    label.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    label.textColor = NSColor.secondaryLabelColor;
    return label;
}

- (TSAdvancedFindFieldView *)makeField
{
    TSAdvancedFindFieldView *field = [[TSTeXRootSearchFieldView alloc] initWithFrame:NSMakeRect(0, 0, 400, 24)];
    field.richText = NO;
    field.importsGraphics = NO;
    field.allowsUndo = YES;
    field.automaticQuoteSubstitutionEnabled = NO;
    field.automaticDashSubstitutionEnabled = NO;
    field.automaticTextReplacementEnabled = NO;
    field.automaticSpellingCorrectionEnabled = NO;
    field.continuousSpellCheckingEnabled = NO;
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
    [box.heightAnchor constraintEqualToConstant:30].active = YES;
    return box;
}

- (NSView *)makeTopRow
{
    self.modeControl = [NSSegmentedControl segmentedControlWithLabels:@[TSLocalized(@"TeXRootSearch.Mode.Find", @"Find"),
                                                                        TSLocalized(@"TeXRootSearch.Mode.Replace", @"Replace"),
                                                                        TSLocalized(@"MultipleReplace.Title", @"Multiple Replace")]
                                                         trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(modeChanged:)];
    self.modeControl.selectedSegment = 0;
    self.modeControl.accessibilityLabel = TSLocalized(@"TeXRootSearch.AX.Mode", @"Mode");
    self.rootLabel = [self smallLabel];
    self.rootLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.rootLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSImage *refresh = [NSImage imageWithSystemSymbolName:@"arrow.clockwise" accessibilityDescription:TSLocalized(@"TeXRootSearch.Refresh", @"Collect the files again")] ?: [NSImage new];
    self.refreshButton = [NSButton buttonWithImage:refresh target:self action:@selector(collectAgain:)];
    self.refreshButton.bezelStyle = NSBezelStyleAccessoryBarAction;
    self.refreshButton.toolTip = TSLocalized(@"TeXRootSearch.Refresh", @"Collect the files again");
    self.refreshButton.keyEquivalent = @"r";
    self.refreshButton.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    NSStackView *row = [NSStackView stackViewWithViews:@[self.modeControl]];
    row.spacing = 8;
    [row addView:self.rootLabel inGravity:NSStackViewGravityTrailing];
    [row addView:self.refreshButton inGravity:NSStackViewGravityTrailing];
    return row;
}

/// What is searched, in one line (wrapped in long languages), and ? for the rule (spec §2.7.6).
- (NSView *)makeExplanationRow
{
    self.explanationLabel = [NSTextField wrappingLabelWithString:@""];
    self.explanationLabel.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    self.explanationLabel.textColor = NSColor.secondaryLabelColor;
    self.explanationLabel.selectable = NO;
    [self.explanationLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.explanationLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    self.helpButton = [NSButton buttonWithTitle:@"" target:self action:@selector(showExplanation:)];
    self.helpButton.bezelStyle = NSBezelStyleHelpButton;
    self.helpButton.controlSize = NSControlSizeSmall;
    self.helpButton.accessibilityLabel = TSLocalized(@"TeXRootSearch.WhichFiles", @"Which files are searched");
    self.helpButton.toolTip = self.helpButton.accessibilityLabel;
    NSStackView *row = [NSStackView stackViewWithViews:@[self.explanationLabel, self.helpButton]];
    row.spacing = 6;
    row.alignment = NSLayoutAttributeCenterY;
    [self.helpButton setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    return row;
}

- (NSView *)makeOptionsRow
{
    self.regexBox = [self checkBox:@"AdvancedFind.RegularExpression" english:@"Regular expression" action:@selector(optionChanged:)];
    self.ignoreCaseBox = [self checkBox:@"AdvancedFind.IgnoreCase" english:@"Ignore case" action:@selector(optionChanged:)];
    NSImage *more = [NSImage imageWithSystemSymbolName:@"ellipsis.circle" accessibilityDescription:TSLocalized(@"AdvancedFind.MoreOptions", @"More Options")] ?: [NSImage new];
    self.moreOptionsButton = [NSButton buttonWithImage:more target:self action:@selector(showOptions:)];
    self.moreOptionsButton.controlSize = NSControlSizeSmall;
    self.moreOptionsButton.toolTip = TSLocalized(@"AdvancedFind.MoreOptions", @"More Options");
    NSStackView *row = [NSStackView stackViewWithViews:@[self.regexBox, self.ignoreCaseBox]];
    row.spacing = 16;
    [row addView:self.moreOptionsButton inGravity:NSStackViewGravityTrailing];
    return row;
}

- (NSView *)makeSetRow
{
    self.setPopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.setPopUp.target = self;
    self.setPopUp.action = @selector(setChosen:);
    self.setPopUp.accessibilityLabel = TSLocalized(@"TeXRootSearch.AX.Set", @"Multiple replacement set");
    self.ruleCountLabel = [self smallLabel];
    self.editSetButton = [NSButton buttonWithTitle:TSLocalized(@"TeXRootSearch.EditSet", @"Edit…") target:self action:@selector(editSet:)];
    NSStackView *row = [NSStackView stackViewWithViews:@[self.setPopUp, self.ruleCountLabel, self.editSetButton]];
    row.spacing = 10;
    return row;
}

- (NSView *)makeBottomRow
{
    self.spinner = [NSProgressIndicator new];
    self.spinner.style = NSProgressIndicatorStyleSpinning;
    self.spinner.controlSize = NSControlSizeSmall;
    self.spinner.displayedWhenStopped = NO;
    NSImage *stop = [NSImage imageWithSystemSymbolName:@"stop.fill" accessibilityDescription:TSLocalized(@"TeXRootSearch.Stop", @"Stop")] ?: [NSImage new];
    self.stopButton = [NSButton buttonWithImage:stop target:self action:@selector(stop:)];
    self.stopButton.bezelStyle = NSBezelStyleAccessoryBarAction;
    self.stopButton.toolTip = TSLocalized(@"TeXRootSearch.Stop", @"Stop");
    self.statusField = [self smallLabel];
    self.statusField.lineBreakMode = NSLineBreakByTruncatingTail;
    self.statusField.selectable = YES;
    [self.statusField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.unreadableButton = [NSButton buttonWithTitle:@"" target:self action:@selector(showUnreadable:)];
    self.unreadableButton.bezelStyle = NSBezelStyleAccessoryBarAction;
    self.unreadableButton.controlSize = NSControlSizeSmall;
    self.backupBox = [NSButton checkboxWithTitle:TSLocalized(@"TeXRootSearch.SaveBackups", @"Save backups") target:self action:@selector(backupChanged:)];
    id saved = [NSUserDefaults.standardUserDefaults objectForKey:TSTeXRootSearchSavesBackupsKey];
    self.backupBox.state = (!saved || [NSUserDefaults.standardUserDefaults boolForKey:TSTeXRootSearchSavesBackupsKey]) ? NSControlStateValueOn : NSControlStateValueOff;
    self.replaceAllButton = [NSButton buttonWithTitle:TSLocalized(@"AdvancedFind.ReplaceAll", @"Replace All") target:self action:@selector(replaceAll:)];
    NSStackView *row = [NSStackView stackViewWithViews:@[self.spinner, self.stopButton, self.statusField, self.unreadableButton]];
    row.spacing = 8;
    [row addView:self.backupBox inGravity:NSStackViewGravityTrailing];
    [row addView:self.replaceAllButton inGravity:NSStackViewGravityTrailing];
    return row;
}

- (void)place:(NSView *)view in:(NSView *)holder
{
    for (NSView *old in [holder.subviews copy])
        [old removeFromSuperview];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [holder addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [view.leadingAnchor constraintEqualToAnchor:holder.leadingAnchor], [view.trailingAnchor constraintEqualToAnchor:holder.trailingAnchor],
        [view.topAnchor constraintEqualToAnchor:holder.topAnchor], [view.bottomAnchor constraintEqualToAnchor:holder.bottomAnchor],
    ]];
}

- (void)buildContent
{
    self.findFieldView = [self makeField];
    self.replaceFieldView = [self makeField];
    self.findBox = [self boxForField:self.findFieldView symbol:@"magnifyingglass" tag:0];
    self.replaceBox = [self boxForField:self.replaceFieldView symbol:@"pencil" tag:1];
    self.findFieldView.accessibilityLabel = TSLocalized(@"AdvancedFind.FindLabel", @"Find:");
    self.replaceFieldView.accessibilityLabel = TSLocalized(@"AdvancedFind.ReplaceLabel", @"Replace:");
    self.optionsRow = [self makeOptionsRow];
    self.setRow = [self makeSetRow];
    NSView *top = [self makeTopRow];
    NSView *explanation = [self makeExplanationRow];
    self.topStack = [NSStackView stackViewWithViews:@[top, explanation, self.findBox, self.replaceBox, self.optionsRow, self.setRow]];
    self.topStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.topStack.alignment = NSLayoutAttributeLeading;
    self.topStack.spacing = 8;
    self.topStack.edgeInsets = NSEdgeInsetsMake(12, 16, 10, 16);
    [self.topStack setCustomSpacing:4 afterView:top];
    [self.topStack setCustomSpacing:5 afterView:self.replaceBox];
    for (NSView *view in self.topStack.arrangedSubviews)
        [view.widthAnchor constraintEqualToAnchor:self.topStack.widthAnchor constant:-32].active = YES;

    // The tree as wide as the mockup's at first (the split view keeps where the user puts the divider afterwards).
    self.treeHolder = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 220, 360)];
    self.resultsHolder = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 680, 360)];
    self.splitView = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 900, 360)];
    self.splitView.vertical = YES;
    self.splitView.dividerStyle = NSSplitViewDividerStyleThin;
    self.splitView.autosaveName = @"TeXRootSearchSplit";
    [self.splitView addArrangedSubview:self.treeHolder];
    [self.splitView addArrangedSubview:self.resultsHolder];
    [self.splitView setHoldingPriority:NSLayoutPriorityDefaultHigh forSubviewAtIndex:0];
    [self.treeHolder.widthAnchor constraintGreaterThanOrEqualToConstant:150].active = YES;
    [self.resultsHolder.widthAnchor constraintGreaterThanOrEqualToConstant:360].active = YES;

    NSView *bottom = [self makeBottomRow];
    self.bottomStack = (NSStackView *)bottom;
    NSBox *line1 = [NSBox new], *line2 = [NSBox new];
    line1.boxType = line2.boxType = NSBoxSeparator;
    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 900, 580)];
    for (NSView *view in @[self.topStack, line1, self.splitView, line2, bottom]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [content addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
        [self.topStack.topAnchor constraintEqualToAnchor:content.topAnchor],
        [self.topStack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.topStack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [line1.topAnchor constraintEqualToAnchor:self.topStack.bottomAnchor],
        [line1.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [line1.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [self.splitView.topAnchor constraintEqualToAnchor:line1.bottomAnchor],
        [self.splitView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.splitView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [line2.topAnchor constraintEqualToAnchor:self.splitView.bottomAnchor],
        [line2.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [line2.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [bottom.topAnchor constraintEqualToAnchor:line2.bottomAnchor constant:6],
        [bottom.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [bottom.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [bottom.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-8],
        [bottom.heightAnchor constraintGreaterThanOrEqualToConstant:24],
        [self.splitView.heightAnchor constraintGreaterThanOrEqualToConstant:160],
    ]];
    self.window.contentView = content;
    self.window.initialFirstResponder = self.findFieldView;
    // Tab: mode, find, replacement (or the set), options, tree, list, the buttons below (spec §2.10).
    self.modeControl.nextKeyView = self.findFieldView;
    self.findFieldView.nextKeyView = self.replaceFieldView;
    self.replaceFieldView.nextKeyView = self.regexBox;
    self.regexBox.nextKeyView = self.ignoreCaseBox;
    self.ignoreCaseBox.nextKeyView = self.moreOptionsButton;
    self.setPopUp.nextKeyView = self.editSetButton;
    [self applyFieldStyle];
    [self showMode:TSTeXRootSearchModeFind];
}

- (void)applyFieldStyle
{
    TSAdvancedFindFieldStyle *style = [TSAdvancedFindFieldStyle styleForWindow:self.window];
    for (TSAdvancedFindFieldView *field in @[self.findFieldView, self.replaceFieldView]) {
        field.font = style.fieldFont;
        field.textColor = style.textColor ?: NSColor.textColor;
        field.insertionPointColor = style.insertionPointColor ?: NSColor.textInsertionPointColor;
        field.backgroundColor = style.backgroundColor ?: NSColor.textBackgroundColor;
    }
    self.findBox.fillColor = self.replaceBox.fillColor = style.backgroundColor;
    if (style.fieldAppearance)
        self.findBox.appearance = self.replaceBox.appearance = style.fieldAppearance;
    if (self.resultsList) {
        self.resultsList.font = [NSFont monospacedSystemFontOfSize:MIN(style.fieldFont.pointSize, 14) weight:NSFontWeightRegular];
        [self.resultsList reload];
    }
}

- (void)fieldStyleDidChange:(NSNotification *)notification
{
    [self applyFieldStyle];
}

#pragma mark Opening

- (void)openForRootURL:(NSURL *)rootURL environment:(TSTeXRootSearchEnvironment *)environment
                  mode:(TSTeXRootSearchMode)mode setName:(nullable NSString *)setName
{
    [self window];
    [self closePopover];
    self.model.delegate = nil;
    [self.model stop];
    TSTeXRootSearchModel *model = [[TSTeXRootSearchModel alloc] initWithRootURL:rootURL environment:environment];
    model.delegate = self;
    self.model = model;
    self.fileTree = [[TSTeXRootSearchFileTree alloc] initWithModel:model];
    self.resultsList = [[TSTeXRootSearchResultsList alloc] initWithModel:model];
    TSAdvancedFindFieldStyle *style = [TSAdvancedFindFieldStyle styleForWindow:self.window];
    self.resultsList.font = [NSFont monospacedSystemFontOfSize:MIN(style.fieldFont.pointSize, 14) weight:NSFontWeightRegular];
    __weak typeof(self) weakSelf = self;
    self.resultsList.showItemHandler = ^(TSTeXRootSearchFileResult *file, TSTeXRootSearchItem *item, BOOL front) {
        if (weakSelf.showItemHandler)
            weakSelf.showItemHandler(file, item, front);
    };
    [self place:self.fileTree.scrollView in:self.treeHolder];
    [self place:self.resultsList.scrollView in:self.resultsHolder];
    self.ignoreCaseBox.nextKeyView = self.moreOptionsButton;
    self.moreOptionsButton.nextKeyView = self.fileTree.outlineView;
    self.editSetButton.nextKeyView = self.fileTree.outlineView;
    self.fileTree.outlineView.nextKeyView = self.resultsList.tableView;
    self.resultsList.tableView.nextKeyView = self.replaceAllButton;
    self.shownResults = nil;
    self.showsAnyResults = NO;

    NSString *name = rootURL.lastPathComponent;
    self.rootLabel.stringValue = [NSString stringWithFormat:TSLocalized(@"TeXRootSearch.Root", @"Root: %@"), name];
    self.rootLabel.toolTip = rootURL.path;
    self.explanationLabel.stringValue = [NSString stringWithFormat:TSLocalized(@"TeXRootSearch.Explanation",
        @"Searches %@ and the TeX sources in its folder and subfolders that name it as TEX root."), name];

    TSAdvancedFindSettings *settings = self.findController.settings;
    [settings reloadFindStringFromPasteboard];
    [self loadStrings];
    [self loadOptions];
    [self reloadSetsChoosing:setName];
    TSRegexMultipleReplace *set = self.setName ? [self.library setNamed:(NSString *_Nonnull)self.setName error:NULL] : nil;
    [model setMode:mode findString:settings.findString replaceString:settings.replaceString options:settings.options
            syntax:settings.replacementSyntax multipleReplace:set];
    [self showMode:mode];
    [model collect];
    [self updateFromModel];
}

- (void)windowWillClose:(NSNotification *)notification
{
    // Closing forgets the files and the checks (spec §2.7.4); a search under way stops.
    [self closePopover];
    [self.model stop];
    self.model.delegate = nil;
    self.model = nil;
}

#pragma mark Modes

- (void)showMode:(TSTeXRootSearchMode)mode
{
    self.modeControl.selectedSegment = mode;
    BOOL multiple = mode == TSTeXRootSearchModeMultipleReplace;
    self.findBox.hidden = multiple;
    self.replaceBox.hidden = mode != TSTeXRootSearchModeReplace;
    self.optionsRow.hidden = multiple;
    self.setRow.hidden = !multiple;
    self.backupBox.hidden = self.replaceAllButton.hidden = mode == TSTeXRootSearchModeFind;
    self.modeControl.nextKeyView = multiple ? self.setPopUp : self.findFieldView;
    self.findFieldView.nextKeyView = mode == TSTeXRootSearchModeReplace ? self.replaceFieldView : self.regexBox;
}

- (void)modeChanged:(NSSegmentedControl *)sender
{
    TSTeXRootSearchMode mode = (TSTeXRootSearchMode)sender.selectedSegment;
    [self showMode:mode];
    if (mode == TSTeXRootSearchModeMultipleReplace && !self.model.multipleReplace && self.setName)
        self.model.multipleReplace = [self.library setNamed:(NSString *_Nonnull)self.setName error:NULL];
    self.model.mode = mode;
}

#pragma mark Strings and options

- (void)loadStrings
{
    TSAdvancedFindSettings *settings = self.findController.settings;
    if (![self.findFieldView.string isEqualToString:settings.findString])
        self.findFieldView.string = settings.findString;
    if (![self.replaceFieldView.string isEqualToString:settings.replaceString])
        self.replaceFieldView.string = settings.replaceString;
    [self.findBox textDidChange];
    [self.replaceBox textDidChange];
}

- (void)loadOptions
{
    TSRegexFindOptions options = self.findController.settings.options;
    self.regexBox.state = (options & TSRegexFindRegularExpression) ? NSControlStateValueOn : NSControlStateValueOff;
    self.ignoreCaseBox.state = (options & TSRegexFindIgnoreCase) ? NSControlStateValueOn : NSControlStateValueOff;
    self.optionsForm.usesRegularExpression = (options & TSRegexFindRegularExpression) != 0;
}

/// The panel (or a history menu) changed the shared strings or options.
- (void)settingsDidChange:(NSNotification *)notification
{
    [self loadStrings];
    [self loadOptions];
    TSAdvancedFindSettings *settings = self.findController.settings;
    self.model.findString = settings.findString;
    self.model.replaceString = settings.replaceString;
    self.model.options = settings.options;
    self.model.replacementSyntax = settings.replacementSyntax;
}

- (void)textDidChange:(NSNotification *)notification
{
    [self.findBox textDidChange];
    [self.replaceBox textDidChange];
    TSAdvancedFindSettings *settings = self.findController.settings;
    if (notification.object == self.findFieldView)
        settings.findString = self.findFieldView.string;
    else if (notification.object == self.replaceFieldView)
        settings.replaceString = self.replaceFieldView.string;
}

/// Return in a field: search now, without the pause; the strings go into the recent strings.
- (IBAction)advancedFindNext:(nullable id)sender
{
    [self.findController.settings noteFindString];
    if (self.model.mode == TSTeXRootSearchModeReplace)
        [self.findController.settings noteReplaceString];
    [self.model searchNow];
}

- (void)optionChanged:(NSButton *)sender
{
    TSAdvancedFindSettings *settings = self.findController.settings;
    TSRegexFindOptions options = settings.options;
    BOOL on = sender.state == NSControlStateValueOn;
    TSRegexFindOptions bit = sender == self.regexBox ? TSRegexFindRegularExpression : TSRegexFindIgnoreCase;
    settings.options = on ? options | bit : options & ~bit;
}

- (void)showHistory:(NSButton *)sender
{
    // The panel's menu: choosing a string sets the shared string, which comes back here.
    NSMenu *menu = [TSAdvancedFindPanelController.sharedPanelController historyMenuForField:sender.tag];
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight(sender.bounds) + 4) inView:sender];
}

- (void)showOptions:(NSButton *)sender
{
    TSAdvancedFindSettings *settings = self.findController.settings;
    TSAdvancedFindOptionsForm *form = [[TSAdvancedFindOptionsForm alloc] initWithStyle:TSAdvancedFindOptionsFormStylePanel
                                                                         textualOptions:settings.options
                                                               regularExpressionOptions:settings.options
                                                                      replacementSyntax:settings.replacementSyntax];
    form.usesRegularExpression = (settings.options & TSRegexFindRegularExpression) != 0;
    __weak typeof(self) weakSelf = self;
    form.changeHandler = ^(TSAdvancedFindOptionsForm *changed) {
        TSRegexFindOptions text = TSAdvancedFindOptionsForm.textualItemOptions;
        TSAdvancedFindSettings *current = weakSelf.findController.settings;
        current.options = (changed.regularExpressionOptions & ~text) | (changed.textualOptions & text);
        current.replacementSyntax = changed.replacementSyntax;
    };
    [form insertTitle:TSLocalized(@"AdvancedFind.OptionsTitle", @"Find Options") rows:@[]];
    self.optionsForm = form;
    [self showPopoverWithView:form.view relativeTo:sender];
}

#pragma mark Multiple replacement sets

- (void)reloadSetsChoosing:(nullable NSString *)name
{
    NSArray<NSString *> *names = self.library.setNames;
    NSString *chosen = name ?: self.setName;
    if (chosen && ![names containsObject:(NSString *_Nonnull)chosen])
        chosen = nil;
    chosen = chosen ?: names.firstObject;
    [self.setPopUp removeAllItems];
    [self.setPopUp addItemsWithTitles:names];
    if (chosen)
        [self.setPopUp selectItemWithTitle:(NSString *_Nonnull)chosen];
    self.setPopUp.enabled = names.count > 0;
    self.editSetButton.enabled = chosen != nil;
    self.setName = chosen;
    [self updateRuleCount];
}

- (void)updateRuleCount
{
    TSRegexMultipleReplace *set = self.setName ? [self.library setNamed:(NSString *_Nonnull)self.setName error:NULL] : nil;
    NSUInteger enabled = 0;
    for (TSRegexReplacementRule *rule in set.rules)
        if (rule.enabled)
            enabled++;
    self.ruleCountLabel.stringValue = set ? [NSString stringWithFormat:TSLocalized(@"TeXRootSearch.RuleCount", @"Rules: %lu"), (unsigned long)enabled] : @"";
}

- (void)setChosen:(NSPopUpButton *)sender
{
    self.setName = sender.titleOfSelectedItem;
    self.editSetButton.enabled = self.setName != nil;
    [self updateRuleCount];
    self.model.multipleReplace = self.setName ? [self.library setNamed:(NSString *_Nonnull)self.setName error:NULL] : nil;
}

/// A set was saved (edited in the Multiple Replace window), renamed or removed.
- (void)libraryDidChange:(NSNotification *)notification
{
    [self reloadSetsChoosing:self.setName];
    self.model.multipleReplace = self.setName ? [self.library setNamed:(NSString *_Nonnull)self.setName error:NULL] : nil;
}

- (void)editSet:(id)sender
{
    if (self.setName && self.editSetHandler)
        self.editSetHandler((NSString *_Nonnull)self.setName);
}

#pragma mark Popovers

- (void)closePopover
{
    [self.popover close];
    self.popover = nil;
}

- (void)showPopoverWithView:(NSView *)view relativeTo:(NSView *)anchor
{
    [self closePopover];
    NSViewController *controller = [NSViewController new];
    [view layoutSubtreeIfNeeded];
    controller.preferredContentSize = view.fittingSize;
    [view setFrameSize:view.fittingSize];
    controller.view = view;
    [self showPopoverWithController:controller relativeTo:anchor];
}

- (void)showPopoverWithController:(NSViewController *)controller relativeTo:(NSView *)anchor
{
    [self closePopover];
    self.popover = [NSPopover new];
    self.popover.behavior = NSPopoverBehaviorTransient;
    self.popover.contentViewController = controller;
    self.popover.contentSize = controller.preferredContentSize;
    [self.popover showRelativeToRect:anchor.bounds ofView:anchor preferredEdge:NSRectEdgeMaxY];
}

/// The rule of the files searched, and "Open Help" (spec §2.7.6).
- (NSViewController *)makeExplanationViewController
{
    NSString *rule = TSLocalized(@"TeXRootSearch.Rule", @"The root file, and the .tex files in its folder and below that name it with % !TEX root (or %!TEX root) in their first 20 lines.");
    if (self.mentionsSourceDoc)
        rule = [NSString stringWithFormat:TSLocalized(@"TeXRootSearch.RuleJoin", @"%1$@ %2$@"), rule,
                TSLocalized(@"TeXRootSearch.RuleSourceDoc", @"Also those that name it with %SourceDoc.")];
    NSTextField *text = [NSTextField wrappingLabelWithString:rule];
    text.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    text.preferredMaxLayoutWidth = 320;
    text.selectable = YES;
    NSButton *help = [NSButton buttonWithTitle:TSLocalized(@"TeXRootSearch.OpenHelp", @"Open Help") target:self action:@selector(openHelp:)];
    help.controlSize = NSControlSizeSmall;
    NSStackView *stack = [NSStackView stackViewWithViews:@[text, help]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;
    stack.edgeInsets = NSEdgeInsetsMake(12, 14, 12, 14);
    [text.widthAnchor constraintEqualToConstant:320].active = YES;
    NSViewController *controller = [NSViewController new];
    [stack layoutSubtreeIfNeeded];
    controller.preferredContentSize = stack.fittingSize;
    [stack setFrameSize:stack.fittingSize];
    controller.view = stack;
    return controller;
}

- (void)showExplanation:(NSButton *)sender
{
    [self showPopoverWithController:[self makeExplanationViewController] relativeTo:sender];
}

- (void)openHelp:(id)sender
{
    [self closePopover];
    if (self.openHelpHandler)
        self.openHelpHandler();
}

/// The files and folders that could not be read, with why (spec §2.2).
- (NSViewController *)makeUnreadableViewController
{
    NSMutableArray<NSView *> *rows = [NSMutableArray array];
    for (TSTeXRootUnreadableItem *item in self.model.project.unreadableItems) {
        NSString *why = item.reason == TSTeXRootUnreadableReasonFolder ? TSLocalized(@"TeXRootSearch.Unreadable.Folder", @"The folder could not be opened.")
                                                                       : TSLocalized(@"TeXRootSearch.Unreadable.File", @"The file could not be read.");
        if (item.error.localizedDescription.length)
            why = [why stringByAppendingFormat:@" %@", item.error.localizedDescription];
        NSTextField *path = [NSTextField labelWithString:item.relativePath.length ? item.relativePath : item.url.path];
        path.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightSemibold];
        path.lineBreakMode = NSLineBreakByTruncatingMiddle;
        path.toolTip = item.url.path;
        NSTextField *reason = [NSTextField wrappingLabelWithString:why];
        reason.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
        reason.textColor = NSColor.secondaryLabelColor;
        reason.preferredMaxLayoutWidth = 360;
        [path.widthAnchor constraintLessThanOrEqualToConstant:360].active = YES;
        [reason.widthAnchor constraintEqualToConstant:360].active = YES;
        [rows addObjectsFromArray:@[path, reason]];
    }
    NSStackView *stack = [NSStackView stackViewWithViews:rows];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 2;
    stack.edgeInsets = NSEdgeInsetsMake(10, 12, 10, 12);
    for (NSUInteger i = 1; i + 1 < rows.count; i += 2)
        [stack setCustomSpacing:8 afterView:rows[i]];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    NSView *document = [[NSView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [document addSubview:stack];
    [stack layoutSubtreeIfNeeded];
    NSSize size = stack.fittingSize;
    document.frame = NSMakeRect(0, 0, size.width, size.height);
    stack.frame = document.bounds;
    stack.translatesAutoresizingMaskIntoConstraints = YES;
    scroll.documentView = document;
    NSViewController *controller = [NSViewController new];
    controller.preferredContentSize = NSMakeSize(size.width, MIN(size.height, 320));
    scroll.frame = NSMakeRect(0, 0, size.width, MIN(size.height, 320));
    controller.view = scroll;
    return controller;
}

- (void)showUnreadable:(NSButton *)sender
{
    [self showPopoverWithController:[self makeUnreadableViewController] relativeTo:sender];
}

#pragma mark Actions

- (IBAction)collectAgain:(nullable id)sender
{
    [self.model collect];
}

- (IBAction)stop:(nullable id)sender
{
    [self.model stop];
}

/// Escape and ⌘. stop a long task (spec §2.9).
- (void)cancelOperation:(nullable id)sender
{
    if (self.model.activity != TSTeXRootSearchActivityIdle)
        [self.model stop];
}

- (IBAction)replaceAll:(nullable id)sender
{
    if (!self.model.canReplaceAll || !self.replaceAllHandler) {
        NSBeep();
        return;
    }
    self.replaceAllHandler(self);
}

- (void)backupChanged:(NSButton *)sender
{
    [NSUserDefaults.standardUserDefaults setBool:sender.state == NSControlStateValueOn forKey:TSTeXRootSearchSavesBackupsKey];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if (item.action == @selector(collectAgain:))
        return self.model != nil;
    if (item.action == @selector(stop:))
        return self.model.activity != TSTeXRootSearchActivityIdle;
    if (item.action == @selector(replaceAll:))
        return self.model.canReplaceAll;
    return YES;
}

#pragma mark Following the model

/// The model may change many times in one turn of the run loop (a file at a time while the first list comes in):
/// the window follows once, after them.
- (void)texRootSearchModelDidChange:(TSTeXRootSearchModel *)model
{
    if (model != self.model)
        return;
    // Replace All follows at once: it must never be pressable for a list that is not that of the conditions; nor is a
    // whole change of the list before shown.
    self.replaceAllButton.enabled = model.canReplaceAll && self.replaceAllHandler != nil;
    [self.resultsList modelDidChange];
    if (self.updatePending)
        return;
    self.updatePending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.updatePending = NO;
        [self updateFromModel];
    });
}

- (NSString *)statusText:(NSColor **)color
{
    TSTeXRootSearchModel *model = self.model;
    *color = NSColor.secondaryLabelColor;
    if (!model)
        return @"";
    if (model.activity == TSTeXRootSearchActivityCollecting)
        return [NSString stringWithFormat:TSLocalized(@"TeXRootSearch.Status.Collecting", @"%1$lu folders, %2$lu files / %3$@"),
                (unsigned long)model.collectedFolders, (unsigned long)model.collectedFiles, model.currentFolder.lastPathComponent ?: @""];
    if (model.eventMessage.length)
        return (NSString *_Nonnull)model.eventMessage;
    if (model.stopped)
        return TSLocalized(@"TeXRootSearch.Status.Stopped", @"Stopped");
    if (model.collectionFailure != TSTeXRootCollectionFailureNone && model.collectionFailure != TSTeXRootCollectionFailureCancelled) {
        *color = NSColor.systemRedColor;
        return TSLocalized(@"TeXRootSearch.Status.RootMissing", @"The root file cannot be found.");
    }
    if (model.queryError) {
        *color = NSColor.systemRedColor;
        return model.queryError.localizedDescription;
    }
    if (!model.project || model.activity == TSTeXRootSearchActivityWaiting || model.activity == TSTeXRootSearchActivityComputing)
        return self.showsAnyResults ? [self countText:model] : @"";
    BOOL hasQuery = model.mode == TSTeXRootSearchModeMultipleReplace ? model.multipleReplace != nil : model.findString.length > 0;
    if (!hasQuery)
        return @"";
    NSString *text = [self countText:model];
    if (model.reachedLimit) {
        *color = NSColor.systemOrangeColor;
        text = [text stringByAppendingFormat:@" — %@", TSLocalized(@"TeXRootSearch.Status.Limit", @"The limit was reached: not every match is listed.")];
    }
    return text;
}

- (NSString *)countText:(TSTeXRootSearchModel *)model
{
    if (model.numberOfItems == 0)
        return TSLocalized(@"AdvancedFind.NotFound", @"Not found");
    if (model.mode == TSTeXRootSearchModeFind)
        return [NSString stringWithFormat:TSLocalized(@"TeXRootSearch.Status.Found", @"Found: %3$lu · Files: %2$lu of %1$lu"),
                (unsigned long)model.numberOfIncludedFiles, (unsigned long)model.results.count, (unsigned long)model.numberOfItems];
    return [NSString stringWithFormat:TSLocalized(@"TeXRootSearch.Status.ToReplace", @"To replace: %1$lu · Files: %2$lu"),
            (unsigned long)model.numberOfIncludedItems, (unsigned long)model.numberOfFilesWithIncludedItems];
}

- (void)updateFromModel
{
    TSTeXRootSearchModel *model = self.model;
    TSTeXRootSearchActivity activity = model.activity;
    BOOL busy = activity == TSTeXRootSearchActivityCollecting || activity == TSTeXRootSearchActivityComputing;
    if (activity == TSTeXRootSearchActivityComputing)
        [self.spinner startAnimation:nil];
    else
        [self.spinner stopAnimation:nil];
    self.spinner.hidden = activity != TSTeXRootSearchActivityComputing;
    self.stopButton.hidden = !busy;
    if (model.mode != (TSTeXRootSearchMode)self.modeControl.selectedSegment)
        [self showMode:model.mode];
    // The results: rebuilt when other files or other items are listed, or the mode changed.
    NSArray *results = model.results;
    BOOL same = results.count == self.shownResults.count && model.mode == self.shownMode;
    for (NSUInteger i = 0; same && i < results.count; i++)
        same = results[i] == self.shownResults[i];
    if (!same) {
        self.shownResults = results;
        self.shownMode = model.mode;
        [self.resultsList reload];
    } else {
        // Same items: only the checks may have changed, in the rows on screen (the others are made when shown).
        NSTableView *list = self.resultsList.tableView;
        NSRange visible = [list rowsInRect:list.visibleRect];
        if (visible.length > 0)
            [list reloadDataForRowIndexes:[NSIndexSet indexSetWithIndexesInRange:visible]
                            columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, (NSUInteger)list.numberOfColumns)]];
    }
    if (activity == TSTeXRootSearchActivityIdle && model.project)
        self.showsAnyResults = YES;
    [self.fileTree reload];
    // An error of the find string is said in the field's description too, not only in red (spec §2.10).
    self.findFieldView.accessibilityHelp = model.queryError.localizedDescription;
    NSColor *color = nil;
    self.statusField.stringValue = [self statusText:&color];
    self.statusField.textColor = color;
    self.statusField.toolTip = self.statusField.stringValue.length ? self.statusField.stringValue : nil;
    NSUInteger unreadable = model.project.unreadableItems.count;
    self.unreadableButton.hidden = unreadable == 0;
    self.unreadableButton.title = [NSString stringWithFormat:TSLocalized(@"TeXRootSearch.UnreadableButton", @"Files not read: %lu"), (unsigned long)unreadable];
    self.replaceAllButton.enabled = model.canReplaceAll && self.replaceAllHandler != nil;
    self.refreshButton.enabled = model != nil;
    self.modeControl.enabled = model != nil;
}

@end

@implementation TSTeXRootSearchWindowController (Testing)
- (NSTextView *)findField { return self.findFieldView; }
- (NSTextView *)replaceField { return self.replaceFieldView; }
- (NSView *)findRow { return self.findBox; }
- (NSView *)replaceRow { return self.replaceBox; }
@end
