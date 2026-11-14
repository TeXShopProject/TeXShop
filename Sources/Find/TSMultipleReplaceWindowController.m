// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSMultipleReplaceWindowController.h"
#import "TSAdvancedFindFieldScanners.h"
#import "TSAdvancedFindFieldStyle.h"
#import "TSSyntaxTeXScanner.h"
#import "TSAdvancedFindTextView.h"
#import "TSAdvancedFindController+MultipleReplace.h"
#import "TSAdvancedFindOptionsForm.h"
#import "TSAdvancedFindHighlights.h"

#define TSLocalized TSAdvancedFindLocalized

@interface TSMultipleReplaceWindowController () <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSUserInterfaceValidations>
@property (nonatomic, readwrite) TSMultipleReplaceRuleTable *ruleTable;
@property (nonatomic, readwrite, copy, nullable) NSString *selectedSetName;
@property (nonatomic, readwrite) NSTextField *statusField;
@property (nonatomic) NSTableView *setTable;
@property (nonatomic, copy) NSArray<NSString *> *setNames;
@property (nonatomic) NSButton *inSelectionBox;
@property (nonatomic, readwrite) NSButton *removeSetButton;
@property (nonatomic, readwrite) NSSegmentedControl *ruleButtons;
@property (nonatomic, readwrite) NSButton *optionsButton;
/// Highlight and Replace All.
@property (nonatomic, copy) NSArray<NSButton *> *actionButtons;
@property (nonatomic, strong, nullable) NSPopover *optionsPopover;
/// Kept while its view is shown: the check boxes target it.
@property (nonatomic, strong, nullable) TSAdvancedFindOptionsForm *optionsForm;
/// The theme of the rules' find and replacement cells, for the window's light or dark appearance.
@property (nonatomic, strong) TSAdvancedFindFieldStyle *fieldStyle;
@end

/// A rule's find or replacement text colored as the find panel's fields are, in the theme of `style`: a regular
/// expression rule as the engine reads it, another as the source reads TeX. A disabled rule stays gray.
static NSAttributedString *_Nullable TSMultipleReplaceColoredField(NSString *string, TSRegexReplacementRule *rule, TSMultipleReplaceRuleField field,
                                                                  TSRegexFindOptions options, TSRegexReplacementSyntax syntax,
                                                                  NSDictionary<NSAttributedStringKey, id> *attributes, TSAdvancedFindFieldStyle *style)
{
    if (!rule.enabled)
        return nil;
    id<TSSyntaxScanner> scanner;
    if (!rule.usesRegularExpression || !(options & TSRegexFindRegularExpression))
        scanner = [[TSSyntaxTeXScanner alloc] initWithOptions:style.texOptions];
    else if (field == TSMultipleReplaceRuleFieldFind)
        scanner = [[TSAdvancedFindPatternScanner alloc] initWithOptions:options];
    else {
        TSRegexFindPattern *pattern = rule.findString.length > 0 ? [[TSRegexFindPattern alloc] initWithFindString:rule.findString options:options error:NULL] : nil;
        scanner = [[TSAdvancedFindReplacementScanner alloc] initWithSyntax:syntax options:options pattern:pattern];
    }
    return TSAdvancedFindColoredString(string, scanner, style.fieldScheme, attributes);
}

static void *TSRuleAppearanceContext = &TSRuleAppearanceContext;

/// Wide enough at first for the names of the bundled samples in every language (“ajmacros → Caracteres Unicode”).
static const CGFloat TSSidebarWidth = 240;

@implementation TSMultipleReplaceWindowController

- (instancetype)initWithFindController:(TSAdvancedFindController *)findController library:(TSMultipleReplaceLibrary *)library
{
    // The sidebar runs up to the top, under the title bar, as in CotEditor and the macOS apps with a sidebar.
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 980, 440)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                          | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskFullSizeContentView
                                                  backing:NSBackingStoreBuffered defer:YES];
    panel.title = TSLocalized(@"MultipleReplace.Title", @"Multiple Replace");
    panel.hidesOnDeactivate = YES;
    panel.becomesKeyOnlyIfNeeded = NO;
    panel.contentMinSize = NSMakeSize(680, 300);
    if (!(self = [super initWithWindow:panel]))
        return nil;
    _findController = findController;
    _library = library;
    // After every event, as menu items are: the target may have changed (another window) or become read-only.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidUpdate:) name:NSApplicationDidUpdateNotification object:nil];
    // A long action starts or ends: Highlight and Replace All are gray meanwhile.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidUpdate:) name:TSAdvancedFindTaskDidChangeNotification object:findController];
    _setNames = @[];
    _ruleTable = [TSMultipleReplaceRuleTable new];
    __weak typeof(self) weakSelf = self;
    _ruleTable.setChangedHandler = ^(TSRegexMultipleReplace *set) { [weakSelf saveSet:set]; };
    _ruleTable.fieldStyler = ^NSAttributedString *_Nullable(NSString *string, TSRegexReplacementRule *rule, TSMultipleReplaceRuleField field,
                                                            TSRegexFindOptions options, NSDictionary<NSAttributedStringKey, id> *attributes) {
        return TSMultipleReplaceColoredField(string, rule, field, options, weakSelf.ruleTable.set.replacementSyntax, attributes, weakSelf.fieldStyle);
    };
    _fieldStyle = [TSAdvancedFindFieldStyle styleForWindow:panel];
    // The cells follow the theme and the light or dark appearance of the application or of the window.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(fieldStyleDidChange:) name:TSAdvancedFindFieldStyleDidChangeNotification object:nil];
    [NSApp addObserver:self forKeyPath:@"effectiveAppearance" options:0 context:TSRuleAppearanceContext];
    [panel addObserver:self forKeyPath:@"effectiveAppearance" options:0 context:TSRuleAppearanceContext];
    [self buildContent];
    // The minus button of the rules follows the selection.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(ruleSelectionChanged:) name:NSTableViewSelectionDidChangeNotification
                                             object:_ruleTable.tableView];
    [self reloadSets];
    return self;
}

#pragma mark Building

- (NSScrollView *)scroll:(NSView *)document
{
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
    scroll.documentView = document;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    return scroll;
}

/// A button of the sidebar's bottom bar: a symbol without a border.
- (NSButton *)barButton:(NSString *)symbol tipKey:(NSString *)key english:(NSString *)english action:(SEL)action
{
    NSString *tip = TSLocalized(key, english);
    NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tip] ?: [NSImage new];
    NSButton *button = [NSButton buttonWithImage:image target:self action:action];
    button.bordered = NO;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.toolTip = tip;
    [button.widthAnchor constraintEqualToConstant:24].active = YES;
    [button.heightAnchor constraintEqualToConstant:22].active = YES;
    return button;
}

- (NSButton *)button:(NSString *)key english:(NSString *)english action:(SEL)action
{
    return [NSButton buttonWithTitle:TSLocalized(key, english) target:self action:action];
}

- (NSView *)stackOf:(NSArray<NSView *> *)views spacing:(CGFloat)spacing
{
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.spacing = spacing;
    stack.alignment = NSLayoutAttributeCenterY;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    return stack;
}

/// The sets, the whole height of the sidebar, and under them ＋ − and the menu with three dots, without borders.
- (NSViewController *)makeSidebar
{
    self.setTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, TSSidebarWidth, 300)];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    column.title = TSLocalized(@"MultipleReplace.Sets", @"Sets");
    // The names take the width of the list, not a new column's 100 points.
    column.resizingMask = NSTableColumnAutoresizingMask;
    column.width = NSWidth(self.setTable.frame);
    [self.setTable addTableColumn:column];
    self.setTable.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
    self.setTable.headerView = nil;
    self.setTable.style = NSTableViewStyleSourceList;
    self.setTable.dataSource = self;
    self.setTable.delegate = self;
    NSScrollView *scroll = [self scroll:self.setTable];
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = NO;
    scroll.automaticallyAdjustsContentInsets = NO; // it starts below the title bar

    NSPopUpButton *action = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
    action.bordered = NO;
    action.toolTip = TSLocalized(@"MultipleReplace.SetActions", @"Actions for Sets");
    NSMenuItem *icon = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
    icon.image = [NSImage imageWithSystemSymbolName:@"ellipsis.circle" accessibilityDescription:action.toolTip];
    [action.menu addItem:icon];
    [action.menu addItemWithTitle:TSLocalized(@"MultipleReplace.Duplicate", @"Duplicate") action:@selector(duplicateSet:) keyEquivalent:@""].target = self;
    [action.menu addItemWithTitle:TSLocalized(@"MultipleReplace.Import", @"Import…") action:@selector(importSet:) keyEquivalent:@""].target = self;
    [action.menu addItemWithTitle:TSLocalized(@"MultipleReplace.Export", @"Export…") action:@selector(exportSet:) keyEquivalent:@""].target = self;
    [action.menu addItem:NSMenuItem.separatorItem];
    [action.menu addItemWithTitle:TSLocalized(@"MultipleReplace.ShowInFinder", @"Show in Finder") action:@selector(showInFinder:) keyEquivalent:@""].target = self;
    self.removeSetButton = [self barButton:@"minus" tipKey:@"MultipleReplace.RemoveSet" english:@"Move the Set to the Trash" action:@selector(removeSet:)];
    NSView *left = [self stackOf:@[[self barButton:@"plus" tipKey:@"MultipleReplace.AddSet" english:@"New Set" action:@selector(addSet:)], self.removeSetButton] spacing:4];
    action.translatesAutoresizingMaskIntoConstraints = NO;
    [action.heightAnchor constraintEqualToConstant:22].active = YES;

    NSBox *line = [NSBox new];
    line.boxType = NSBoxSeparator;
    line.translatesAutoresizingMaskIntoConstraints = NO;

    // A sidebar flush with the window's edges, as CotEditor's (AppKit's own sidebar floats as glass in macOS 26).
    NSVisualEffectView *view = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, 200, 400)];
    view.material = NSVisualEffectMaterialSidebar;
    view.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    for (NSView *child in @[scroll, line, left, action])
        [view addSubview:child];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:line.topAnchor],
        [line.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [line.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [line.bottomAnchor constraintEqualToAnchor:left.topAnchor constant:-6],
        [left.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:12],
        [left.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-8],
        [action.centerYAnchor constraintEqualToAnchor:left.centerYAnchor],
        [action.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-12],
        [view.widthAnchor constraintGreaterThanOrEqualToConstant:160],
    ]];
    NSViewController *controller = [NSViewController new];
    controller.view = view;
    return controller;
}

/// The rules in order with ＋|− and the set's options under them; the actions at the bottom right.
- (NSViewController *)makeRuleArea
{
    NSTextField *heading = [NSTextField labelWithString:TSLocalized(@"MultipleReplace.RulesHeading", @"Apply the rules from the top down:")];
    heading.translatesAutoresizingMaskIntoConstraints = NO;
    NSScrollView *scroll = [self scroll:self.ruleTable.tableView];

    NSImage *plus = [NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:TSLocalized(@"MultipleReplace.AddRule", @"Add a Rule")] ?: [NSImage new];
    NSImage *minus = [NSImage imageWithSystemSymbolName:@"minus" accessibilityDescription:TSLocalized(@"MultipleReplace.RemoveRule", @"Remove the Selected Rules")] ?: [NSImage new];
    self.ruleButtons = [NSSegmentedControl segmentedControlWithImages:@[plus, minus] trackingMode:NSSegmentSwitchTrackingMomentary
                                                               target:self action:@selector(ruleButtonClicked:)];
    self.ruleButtons.segmentStyle = NSSegmentStyleSeparated;
    [self.ruleButtons setToolTip:TSLocalized(@"MultipleReplace.AddRule", @"Add a Rule") forSegment:0];
    [self.ruleButtons setToolTip:TSLocalized(@"MultipleReplace.RemoveRule", @"Remove the Selected Rules") forSegment:1];
    for (NSInteger segment = 0; segment < 2; segment++)
        [self.ruleButtons setWidth:28 forSegment:segment];

    // The options of the whole set (the popover's title names it).
    NSString *optionsTip = TSLocalized(@"MultipleReplace.SetOptions", @"Options for This Set");
    NSImage *ellipsis = [NSImage imageWithSystemSymbolName:@"ellipsis.circle" accessibilityDescription:optionsTip] ?: [NSImage new];
    self.optionsButton = [NSButton buttonWithImage:ellipsis target:self action:@selector(showOptions:)];
    self.optionsButton.toolTip = optionsTip;
    [self.optionsButton setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

    // A message wraps rather than being cut: in some languages a rule's problem is two or three lines long.
    self.statusField = [NSTextField wrappingLabelWithString:@""];
    self.statusField.selectable = NO;
    self.statusField.textColor = NSColor.secondaryLabelColor;
    self.statusField.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    [self.statusField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.statusField setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.statusField setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    for (NSView *child in @[self.ruleButtons, self.statusField, self.optionsButton])
        child.translatesAutoresizingMaskIntoConstraints = NO;

    self.inSelectionBox = [NSButton checkboxWithTitle:TSLocalized(@"AdvancedFind.InSelection", @"In selection") target:self action:@selector(inSelectionChanged:)];
    NSButton *highlight = [self button:@"AdvancedFind.HighlightAll" english:@"Highlight All" action:@selector(highlight:)];
    NSButton *replace = [self button:@"AdvancedFind.ReplaceAll" english:@"Replace All" action:@selector(replaceAll:)];
    replace.keyEquivalent = @"\r";
    self.actionButtons = @[highlight, replace];
    NSView *actions = [self stackOf:@[self.inSelectionBox, highlight, replace] spacing:12];

    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 640, 400)];
    for (NSView *child in @[heading, scroll, self.ruleButtons, self.statusField, self.optionsButton, actions])
        [view addSubview:child];
    NSLayoutGuide *safe = view.safeAreaLayoutGuide;
    // A message of one line is on the line of the buttons; a longer one starts there and goes down.
    NSLayoutConstraint *centered = [self.statusField.centerYAnchor constraintEqualToAnchor:self.ruleButtons.centerYAnchor];
    centered.priority = NSLayoutPriorityDefaultHigh;
    NSLayoutConstraint *close = [actions.topAnchor constraintEqualToAnchor:self.ruleButtons.bottomAnchor constant:16];
    close.priority = NSLayoutPriorityDefaultLow;
    [NSLayoutConstraint activateConstraints:@[centered, close]];
    [NSLayoutConstraint activateConstraints:@[
        [heading.topAnchor constraintEqualToAnchor:safe.topAnchor constant:6],
        [heading.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20],
        [heading.trailingAnchor constraintLessThanOrEqualToAnchor:view.trailingAnchor constant:-20],
        [scroll.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:8],
        [scroll.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20],
        [scroll.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-20],
        [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:100],
        // ＋|− on the left, ⋯ on the right, the message between them (wrapped, it may take more lines)
        [self.ruleButtons.topAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:8],
        [self.ruleButtons.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor],
        [self.optionsButton.centerYAnchor constraintEqualToAnchor:self.ruleButtons.centerYAnchor],
        [self.optionsButton.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor],
        [self.statusField.leadingAnchor constraintEqualToAnchor:self.ruleButtons.trailingAnchor constant:12],
        [self.statusField.trailingAnchor constraintEqualToAnchor:self.optionsButton.leadingAnchor constant:-12],
        [self.statusField.topAnchor constraintGreaterThanOrEqualToAnchor:scroll.bottomAnchor constant:8],
        // The actions at the right of the bottom row
        [actions.topAnchor constraintGreaterThanOrEqualToAnchor:self.ruleButtons.bottomAnchor constant:16],
        [actions.topAnchor constraintGreaterThanOrEqualToAnchor:self.statusField.bottomAnchor constant:12],
        [actions.leadingAnchor constraintGreaterThanOrEqualToAnchor:scroll.leadingAnchor],
        [actions.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor],
        [actions.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-20],
    ]];
    NSViewController *controller = [NSViewController new];
    controller.view = view;
    return controller;
}

- (void)buildContent
{
    NSSplitViewController *split = [NSSplitViewController new];
    NSSplitViewItem *sidebar = [NSSplitViewItem splitViewItemWithViewController:[self makeSidebar]];
    sidebar.canCollapse = NO;
    sidebar.holdingPriority = NSLayoutPriorityDefaultLow + 10; // a wider window widens the rules
    sidebar.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
    sidebar.minimumThickness = 160;
    sidebar.maximumThickness = 320;
    [split addSplitViewItem:sidebar];
    NSSplitViewItem *rules = [NSSplitViewItem splitViewItemWithViewController:[self makeRuleArea]];
    rules.minimumThickness = 480;
    rules.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
    [split addSplitViewItem:rules];
    split.splitView.autosaveName = @"TSMultipleReplaceSplit";
    NSRect frame = self.window.frame;
    self.window.contentViewController = split;
    [self.window setFrame:frame display:NO];
    [split.splitView setPosition:TSSidebarWidth ofDividerAtIndex:0];
}

#pragma mark Sets

- (void)reloadSets
{
    NSString *selected = self.selectedSetName;
    self.setNames = self.library.setNames;
    [self.setTable reloadData];
    NSUInteger index = selected ? [self.setNames indexOfObject:selected] : NSNotFound;
    if (index == NSNotFound && self.setNames.count > 0)
        index = 0;
    if (index != NSNotFound)
        [self selectSetNamed:self.setNames[index]];
    else
        [self showSetNamed:nil];
}

- (void)selectSetNamed:(NSString *)name
{
    NSUInteger index = [self.setNames indexOfObject:name];
    if (index == NSNotFound)
        return;
    [self.setTable selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
    [self showSetNamed:name];
}

- (void)showSetNamed:(nullable NSString *)name
{
    NSString *shown = self.selectedSetName;
    if (name && shown && [shown isEqualToString:(NSString *_Nonnull)name] && self.ruleTable.set)
        return;
    NSError *error = nil;
    TSRegexMultipleReplace *set = name ? [self.library setNamed:(NSString *_Nonnull)name error:&error] : nil;
    self.selectedSetName = set ? name : nil;
    self.ruleTable.set = set;
    [self showStatus:error ? error.localizedDescription : @"" error:error != nil];
    [self updateSetButtons];
}

- (void)saveSet:(TSRegexMultipleReplace *)set
{
    NSString *name = self.selectedSetName;
    NSError *error = nil;
    if (name && ![self.library saveSet:set named:name error:&error])
        [self showStatus:error.localizedDescription error:YES];
    else
        [self showProblems];
}

- (void)showStatus:(NSString *)message error:(BOOL)error
{
    self.statusField.stringValue = message;
    self.statusField.textColor = error ? NSColor.systemRedColor : NSColor.secondaryLabelColor;
}

- (void)showProblems
{
    NSDictionary<NSNumber *, NSError *> *problems = self.ruleTable.set ? TSMultipleReplaceProblems((TSRegexMultipleReplace *_Nonnull)self.ruleTable.set) : @{};
    if (problems.count == 0) {
        [self showStatus:@"" error:NO];
        return;
    }
    NSNumber *first = [problems.allKeys sortedArrayUsingSelector:@selector(compare:)].firstObject;
    NSString *format = TSLocalized(@"MultipleReplace.Problem", @"Rule %lu is skipped: %@");
    [self showStatus:[NSString stringWithFormat:format, first.unsignedLongValue + 1, problems[first].localizedDescription] error:YES];
}

- (IBAction)addSet:(nullable id)sender
{
    NSString *name = [self.library availableNameForName:TSLocalized(@"MultipleReplace.Untitled", @"Untitled")];
    TSRegexReplacementRule *rule = [[TSRegexReplacementRule alloc] initWithFindString:@"" replaceString:@"" usesRegularExpression:NO ignoresCase:NO enabled:YES note:nil];
    TSRegexMultipleReplace *set = [[TSRegexMultipleReplace alloc] initWithRules:@[rule] textualOptions:TSRegexMultipleReplace.defaultTextualOptions
                                                       regularExpressionOptions:TSRegexMultipleReplace.defaultRegularExpressionOptions
                                                              replacementSyntax:TSRegexReplacementSyntaxICU];
    NSError *error = nil;
    if (![self.library saveSet:set named:name error:&error]) {
        [self showStatus:error.localizedDescription error:YES];
        return;
    }
    self.selectedSetName = nil;
    self.setNames = self.library.setNames;
    [self.setTable reloadData];
    [self selectSetNamed:name];
    NSInteger row = (NSInteger)[self.setNames indexOfObject:name];
    if (self.window.isVisible && row >= 0) { // the name is edited at once
        NSView *field = [self.setTable viewAtColumn:0 row:row makeIfNecessary:YES].subviews.firstObject;
        if ([field isKindOfClass:[NSTextField class]])
            [(NSTextField *)field selectText:nil];
    }
}

- (IBAction)duplicateSet:(nullable id)sender
{
    NSString *name = self.selectedSetName;
    TSRegexMultipleReplace *set = self.ruleTable.set;
    if (!name || !set)
        return;
    NSString *copyName = [self.library availableNameForName:[NSString stringWithFormat:TSLocalized(@"MultipleReplace.CopyName", @"%@ copy"), name]];
    NSError *error = nil;
    if (![self.library saveSet:set named:copyName error:&error])
        [self showStatus:error.localizedDescription error:YES];
    self.setNames = self.library.setNames;
    [self.setTable reloadData];
    [self selectSetNamed:copyName];
}

/// The set chosen in the list, even one that cannot be read.
- (nullable NSString *)listedSetName
{
    NSInteger row = self.setTable.selectedRow;
    return row >= 0 && (NSUInteger)row < self.setNames.count ? self.setNames[(NSUInteger)row] : nil;
}

- (IBAction)removeSet:(nullable id)sender
{
    NSString *name = self.listedSetName;
    if (!name)
        return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = [NSString stringWithFormat:TSLocalized(@"MultipleReplace.RemoveQuestion", @"Move “%@” to the Trash?"), name];
    [alert addButtonWithTitle:TSLocalized(@"MultipleReplace.MoveToTrash", @"Move to Trash")];
    [alert addButtonWithTitle:TSLocalized(@"AdvancedFind.Cancel", @"Cancel")];
    NSWindow *window = self.window;
    if (!window)
        return;
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn)
            return;
        NSError *error = nil;
        if (![self.library removeSetNamed:name error:&error])
            [self showStatus:error.localizedDescription error:YES];
        self.selectedSetName = nil;
        [self reloadSets];
    }];
}

- (void)importSet:(id)sender
{
    NSOpenPanel *open = [NSOpenPanel openPanel];
    open.allowsMultipleSelection = YES;
    NSWindow *window = self.window;
    if (!window)
        return;
    [open beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK)
            return;
        NSString *last = nil;
        for (NSURL *url in open.URLs) {
            NSError *error = nil;
            NSString *name = [self.library importFileAtURL:url error:&error];
            if (name)
                last = name;
            else
                [self showStatus:error.localizedDescription error:YES];
        }
        self.setNames = self.library.setNames;
        [self.setTable reloadData];
        if (last)
            [self selectSetNamed:last];
    }];
}

- (void)exportSet:(id)sender
{
    NSString *name = self.selectedSetName;
    NSWindow *window = self.window;
    if (!name || !window)
        return;
    NSSavePanel *save = [NSSavePanel savePanel];
    save.nameFieldStringValue = [name stringByAppendingPathExtension:TSMultipleReplaceLibrary.fileExtension] ?: name;
    [save beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        NSError *error = nil;
        if (response == NSModalResponseOK && save.URL && ![self.library exportSetNamed:name toURL:(NSURL *_Nonnull)save.URL error:&error])
            [self showStatus:error.localizedDescription error:YES];
    }];
}

- (void)showInFinder:(id)sender
{
    [NSFileManager.defaultManager createDirectoryAtURL:self.library.directory withIntermediateDirectories:YES attributes:nil error:NULL];
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[self.library.directory]];
}

#pragma mark Set list

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)self.setNames.count;
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)column row:(NSInteger)row
{
    NSTextField *field = [NSTextField textFieldWithString:self.setNames[(NSUInteger)row]];
    field.bordered = NO;
    field.drawsBackground = NO;
    field.editable = YES;
    field.delegate = self;
    field.lineBreakMode = NSLineBreakByTruncatingTail;
    field.allowsExpansionToolTips = YES;
    NSTableCellView *cell = [TSMultipleReplaceRuleTable cellWithControl:field];
    cell.textField = nil; // plain text, as the list's rows: the source list would restyle its own text field
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    NSInteger row = self.setTable.selectedRow;
    [self showSetNamed:row >= 0 ? self.setNames[(NSUInteger)row] : nil];
}

/// Renaming in the list renames the file.
- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    NSTextField *field = notification.object;
    NSInteger row = [self.setTable rowForView:field];
    if (row < 0)
        return;
    NSString *old = self.setNames[(NSUInteger)row], *new = field.stringValue;
    NSError *error = nil;
    if (![self.library renameSetNamed:old to:new error:&error]) {
        field.stringValue = old;
        [self showStatus:error.localizedDescription error:YES];
        return;
    }
    self.selectedSetName = new;
    self.setNames = self.library.setNames;
    [self.setTable reloadData];
    [self selectSetNamed:new];
}

#pragma mark Rules and running

- (void)addRule:(id)sender { [self.ruleTable addRule]; }
- (void)removeRules:(id)sender { [self.ruleTable removeSelectedRules]; }
- (void)ruleButtonClicked:(NSSegmentedControl *)sender
{
    if (sender.selectedSegment == 0)
        [self addRule:sender];
    else if (sender.selectedSegment == 1)
        [self removeRules:sender];
}
- (void)ruleSelectionChanged:(NSNotification *)notification { [self updateSetButtons]; }

/// The buttons that need a set (the options, ＋ of the rules), a selected rule (− of the rules) or a set chosen in
/// the list (− of the sets): gray otherwise, never a button that does nothing.
- (void)updateSetButtons
{
    BOOL set = self.ruleTable.set != nil;
    self.optionsButton.enabled = set;
    [self.ruleButtons setEnabled:set forSegment:0];
    [self.ruleButtons setEnabled:set && self.ruleTable.tableView.selectedRowIndexes.count > 0 forSegment:1];
    self.removeSetButton.enabled = self.listedSetName != nil;
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
{
    if (item.action == @selector(duplicateSet:) || item.action == @selector(exportSet:))
        return self.ruleTable.set != nil;
    if (item.action == @selector(removeSet:))
        return self.listedSetName != nil;
    return YES;
}

- (void)inSelectionChanged:(NSButton *)sender { self.inSelection = sender.state == NSControlStateValueOn; }

- (void)setInSelection:(BOOL)inSelection
{
    _inSelection = inSelection;
    self.inSelectionBox.state = inSelection ? NSControlStateValueOn : NSControlStateValueOff;
}

- (NSView *)makeOptionsView
{
    TSRegexMultipleReplace *set = self.ruleTable.set;
    TSAdvancedFindOptionsForm *form = [[TSAdvancedFindOptionsForm alloc] initWithStyle:TSAdvancedFindOptionsFormStyleSet
        textualOptions:set ? set.textualOptions : TSRegexMultipleReplace.defaultTextualOptions
        regularExpressionOptions:set ? set.regularExpressionOptions : TSRegexMultipleReplace.defaultRegularExpressionOptions
        replacementSyntax:set ? set.replacementSyntax : TSRegexReplacementSyntaxICU];
    // Titled with the set's name: the options belong to the whole set, not to a rule.
    NSString *name = self.selectedSetName ?: @"";
    [form insertTitle:[NSString stringWithFormat:TSLocalized(@"MultipleReplace.SetOptionsTitle", @"Options for “%@”"), name] rows:@[]];
    NSTextField *title = (NSTextField *)form.view.arrangedSubviews.firstObject;
    title.lineBreakMode = NSLineBreakByTruncatingMiddle; // a long name does not widen the popover
    [title setContentCompressionResistancePriority:NSLayoutPriorityFittingSizeCompression - 1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    title.toolTip = name;
    __weak typeof(self) weakSelf = self;
    form.changeHandler = ^(TSAdvancedFindOptionsForm *changed) {
        TSRegexMultipleReplace *current = weakSelf.ruleTable.set;
        if (!current)
            return;
        TSRegexMultipleReplace *updated = [[TSRegexMultipleReplace alloc] initWithRules:current.rules textualOptions:changed.textualOptions
                                                               regularExpressionOptions:changed.regularExpressionOptions replacementSyntax:changed.replacementSyntax];
        weakSelf.ruleTable.set = updated;
        [weakSelf saveSet:updated];
    };
    self.optionsForm = form;
    return form.view;
}

- (void)showOptions:(NSButton *)sender
{
    if (!self.ruleTable.set)
        return;
    NSViewController *controller = [NSViewController new];
    NSView *view = [self makeOptionsView];
    [view layoutSubtreeIfNeeded];
    controller.preferredContentSize = view.fittingSize; // otherwise the popover squeezes the rows
    [view setFrameSize:view.fittingSize];
    controller.view = view;
    self.optionsPopover = [NSPopover new];
    self.optionsPopover.behavior = NSPopoverBehaviorTransient;
    self.optionsPopover.contentViewController = controller;
    self.optionsPopover.contentSize = controller.preferredContentSize;
    [self.optionsPopover showRelativeToRect:sender.bounds ofView:sender preferredEdge:NSRectEdgeMaxY];
}

- (nullable NSTextView *)target:(nullable NSTextView *)textView
{
    return textView ?: TSAdvancedFindController.targetTextView;
}

- (BOOL)replaceAllInTextView:(nullable NSTextView *)textView
{
    NSTextView *target = [self target:textView];
    TSRegexMultipleReplace *set = self.ruleTable.set;
    if (!target || !set) {
        self.findController.beepHandler();
        return NO;
    }
    __weak typeof(self) weakSelf = self;
    return [self.findController applyMultipleReplace:set inTextView:target inSelection:self.inSelection completion:^(TSRegexMultipleReplaceResult *_Nullable result) {
        [weakSelf showResult:result];
    }];
}

/// The status line after a multiple replacement; nothing when it was cancelled (the find panel's status says so) or
/// the text changed meanwhile.
- (void)showResult:(nullable TSRegexMultipleReplaceResult *)result
{
    if (!result)
        return;
    {
        NSString *message = [NSString stringWithFormat:TSLocalized(@"AdvancedFind.Replaced", @"%lu replaced"), (unsigned long)result.totalCount];
        if (result.errors.count > 0) {
            NSMutableArray<NSString *> *numbers = [NSMutableArray array];
            for (NSNumber *index in [result.errors.allKeys sortedArrayUsingSelector:@selector(compare:)])
                [numbers addObject:@(index.unsignedIntegerValue + 1).stringValue];
            NSString *format = TSLocalized(@"MultipleReplace.SkippedRules", @"(rule %@ skipped; see ⚠︎)");
            message = [message stringByAppendingFormat:@" %@", [NSString stringWithFormat:format, [numbers componentsJoinedByString:@", "]]];
        }
        [self showStatus:message error:NO];
    }
}

- (BOOL)highlightInTextView:(nullable NSTextView *)textView
{
    NSTextView *target = [self target:textView];
    TSRegexMultipleReplace *set = self.ruleTable.set;
    if (!target || !set) {
        self.findController.beepHandler();
        return NO;
    }
    NSUInteger count = [self.findController highlightMultipleReplace:set inTextView:target inSelection:self.inSelection];
    [self showStatus:[NSString stringWithFormat:TSLocalized(@"AdvancedFind.Found", @"%lu found"), (unsigned long)count] error:NO];
    return count > 0;
}

- (void)replaceAll:(id)sender { [self replaceAllInTextView:nil]; }

- (void)applicationDidUpdate:(NSNotification *)notification
{
    if (self.window.isVisible || TSAdvancedFindController.testTargetTextView)
        [self updateButtons];
}

/// Highlight and Replace All, as the panel's buttons: Replace All is gray in a read-only text view. With no target
/// they stay as they are and beep.
- (void)updateButtons
{
    [self updateSetButtons];
    NSTextView *target = [self target:nil];
    TSAdvancedFindController *controller = self.findController;
    static const TSAdvancedFindAction actions[] = {TSAdvancedFindActionHighlight, TSAdvancedFindActionReplaceAll};
    NSArray<NSButton *> *buttons = self.actionButtons;
    for (NSUInteger index = 0; index < buttons.count && index < sizeof(actions) / sizeof(actions[0]); index++) {
        BOOL enabled = target ? [controller validateAction:actions[index] forTextView:target] : controller.runningTask == nil;
        if (buttons[index].enabled != enabled)
            buttons[index].enabled = enabled;
    }
}

#pragma mark Theme

- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(nullable void *)context
{
    if (context == TSRuleAppearanceContext)
        [self fieldStyleDidChange:nil];
    else
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)fieldStyleDidChange:(nullable NSNotification *)notification
{
    self.fieldStyle = [TSAdvancedFindFieldStyle styleForWindow:self.window];
    [self.ruleTable reloadFieldCells];
}

- (void)dealloc
{
    [NSApp removeObserver:self forKeyPath:@"effectiveAppearance" context:TSRuleAppearanceContext];
    [self.window removeObserver:self forKeyPath:@"effectiveAppearance" context:TSRuleAppearanceContext];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (void)highlight:(id)sender { [self highlightInTextView:nil]; }

@end
