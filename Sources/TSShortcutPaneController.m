// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSShortcutInternal.h"
#import "TSSettingsSearchText.h"
#import <QuartzCore/QuartzCore.h>
@interface TSShortcutKeySearchView : NSView
@property (copy, nullable) BOOL (^handleEvent)(NSEvent *event);
@end
@implementation TSShortcutKeySearchView
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isAccessibilityElement { return YES; }
- (NSString *)accessibilityRole { return NSAccessibilityTextFieldRole; }
- (NSString *)accessibilityLabel { return NSLocalizedString(@"Search by Key", @""); }
- (void)keyDown:(NSEvent *)event { [self performKeyEquivalent:event]; }
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (self.handleEvent == nil) { return NO; }
    return self.handleEvent(event);
}
@end

@interface TSShortcutRecorder : NSView
@property (copy) void (^record)(NSEvent *);
@property (copy) dispatch_block_t accept;
@property (copy) dispatch_block_t cancel;
@end
@implementation TSShortcutRecorder
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isAccessibilityElement { return YES; }
- (NSString *)accessibilityRole { return NSAccessibilityTextFieldRole; }
- (NSString *)accessibilityLabel { return NSLocalizedString(@"Change Shortcut", @""); }
- (NSString *)accessibilityHelp { return NSLocalizedString(@"Press the new shortcut (Escape to cancel).", @""); }
- (void)keyDown:(NSEvent *)event { [self performKeyEquivalent:event]; }
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    NSString *key = event.charactersIgnoringModifiers;
    NSEventModifierFlags flags = event.modifierFlags & TSShortcutModifiers;
    if ([key isEqual:@"\r"] && !flags) { if (self.accept) self.accept(); return YES; }
    if ([key isEqual:@"\033"] && !flags) { if (self.cancel) self.cancel(); return YES; }
    if (([key isEqual:@"\t"] || [key isEqual:@"\031"]) && !(flags & ~NSEventModifierFlagShift)) {
        if ((flags & NSEventModifierFlagShift) || [key isEqual:@"\031"]) [self.window selectPreviousKeyView:self];
        else [self.window selectNextKeyView:self];
        return YES;
    }
    if (self.record) self.record(event);
    return YES;
}
@end
@interface TSShortcutCapturePanel : NSPanel
@property TSShortcutRecorder *recorder;
@end
@implementation TSShortcutCapturePanel
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    NSString *key = event.charactersIgnoringModifiers;
    NSEventModifierFlags flags = event.modifierFlags & TSShortcutModifiers;
    BOOL buttonNavigation = (([key isEqual:@"\t"] || [key isEqual:@"\031"]) && !(flags & ~NSEventModifierFlagShift)) ||
        (([key isEqual:@"\r"] || [key isEqual:@" "]) && !flags);
    if (self.firstResponder != self.recorder && buttonNavigation) return [super performKeyEquivalent:event];
    return [self.recorder performKeyEquivalent:event];
}
@end

typedef NS_ENUM(NSInteger, TSShortcutSearchMode) {
    TSShortcutSearchByFunction,
    TSShortcutSearchByKey
};

@interface TSShortcutPaneController () <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
@property (strong) TSKeyboardShortcuts *shortcuts;
@property (readwrite) BOOL searchingByKey;
@property (strong) NSSegmentedControl *searchMode;
@property (strong) TSShortcutKeySearchView *keySearchView;
@property (strong) NSButton *macroButton;
@property (copy) NSString *textQuery;
@property (strong, nullable) NSEvent *searchEvent;
@property (copy) NSArray<TSShortcutMatch *> *searchMatches;
@property (copy) NSString *searchMessage;
@property (copy, nullable) NSString *functionQueryBeforeGlobalSearch;
@property (strong, nullable) TSShortcutStore *store;
@property (strong, nullable, readonly) NSWindow *window;
@property NSTextField *hint;
@property NSTableView *table;
@property (copy) NSArray<NSBox *> *inputGroups;
@property (copy) NSArray<NSButton *> *inputDisclosures;
@property BOOL compactInputs;
@property BOOL configuredInputs;
@property (nullable) NSView *highlightedCompletionRow;
@property NSSearchField *search;
@property NSArray<TSShortcutCommand *> *visibleCommands;
@property NSArray<NSButton *> *selectionButtons;
@property TSShortcutCapturePanel *capturePanel;
@property TSShortcutCommand *editingCommand;
@property NSTextField *captureDisplay;
@property NSTextField *captureError;
@property NSButton *applyButton;
@property NSString *capturedKey;
@property NSArray<NSDictionary *> *capturedBindings;
@property NSEventModifierFlags capturedModifiers;
@end
@implementation TSShortcutPaneController
@synthesize functionQueryBeforeGlobalSearch = _functionQueryBeforeGlobalSearch;
@synthesize settingsHeader = _settingsHeader;
@synthesize inputGroups = _inputGroups, inputDisclosures = _inputDisclosures, compactInputs = _compactInputs, configuredInputs = _configuredInputs, highlightedCompletionRow = _highlightedCompletionRow;
- (instancetype)initWithShortcuts:(TSKeyboardShortcuts *)shortcuts {
    self = [super initWithNibName:nil bundle:nil];
    if (self == nil) { return nil; }
    _shortcuts = shortcuts;
    _store = shortcuts.store;
    _textQuery = @""; _searchMatches = @[]; _searchMessage = @"";
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(shortcutsChanged:) name:TSMacroShortcutsChangedNotification object:shortcuts];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(completionTriggerChanged:) name:@"CommandCompletionCharNotification" object:nil];
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (NSWindow *)window { return self.viewIfLoaded.window; }
- (void)shortcutsChanged:(NSNotification *)notification { self.store = self.shortcuts.store; if (self.isViewLoaded) { [self reloadCommands]; } }
- (void)refreshMenuAndMacros { [self.shortcuts refreshMenuAndMacros]; }
- (NSButton *)button:(NSString *)title action:(SEL)action {
    return [NSButton buttonWithTitle:NSLocalizedString(title, @"") target:self action:action];
}
- (void)loadView {
    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0,0,700,570)];
    self.view = content;
    self.search = [NSSearchField new]; self.search.identifier = @"shortcut.function";
    self.search.accessibilityIdentifier = @"settings.user-data";
    self.search.placeholderString = NSLocalizedString(@"Search commands", @"");
    self.search.delegate = self;
    self.searchMode = [NSSegmentedControl segmentedControlWithLabels:@[NSLocalizedString(@"Search by Function", @""), NSLocalizedString(@"Search by Key", @"")]
        trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(changeSearchMode:)];
    self.searchMode.identifier = @"shortcut.mode";
    self.searchMode.selectedSegment = TSShortcutSearchByFunction;
    [self.searchMode setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.searchMode setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.keySearchView = [TSShortcutKeySearchView new];
    self.keySearchView.identifier = @"shortcut.key";
    self.keySearchView.hidden = YES;
    __weak TSShortcutPaneController *weakSelf = self;
    self.keySearchView.handleEvent = ^BOOL(NSEvent *event) {
        TSShortcutPaneController *strongSelf = weakSelf;
        if (strongSelf == nil) { return NO; }
        return [strongSelf handleKeySearchEvent:event];
    };
    NSTextField *hint = [NSTextField wrappingLabelWithString:NSLocalizedString(@"Select a command to change its shortcut. Changes take effect immediately. Macros and text input key bindings use their own editors.", @"")];
    hint.identifier = @"shortcut.hint";
    hint.textColor = NSColor.secondaryLabelColor; self.hint = hint;
    NSScrollView *scroll = [NSScrollView new];
    scroll.hasVerticalScroller = YES; scroll.hasHorizontalScroller = YES; scroll.borderType = NSBezelBorder;
    self.table = [NSTableView new];
    self.table.delegate = self; self.table.dataSource = self;
    self.table.rowHeight = 28; self.table.usesAlternatingRowBackgroundColors = YES;
    self.table.doubleAction = @selector(editShortcut:); self.table.target = self;
    NSTableColumn *command = [[NSTableColumn alloc] initWithIdentifier:@"command"];
    command.title = NSLocalizedString(@"Command", @""); command.width = 560; command.minWidth = 240;
    NSTableColumn *shortcut = [[NSTableColumn alloc] initWithIdentifier:@"shortcut"];
    shortcut.title = NSLocalizedString(@"Shortcut", @""); shortcut.width = 160; shortcut.minWidth = 100;
    [self.table addTableColumn:command]; [self.table addTableColumn:shortcut];
    scroll.documentView = self.table;
    self.table.headerView.identifier = @"shortcut.columns";
    NSButton *edit = [self button:@"Change…" action:@selector(editShortcut:)];
    NSButton *clear = [self button:@"Remove Shortcut" action:@selector(removeShortcut:)];
    NSButton *restore = [self button:@"Restore Default" action:@selector(restoreShortcut:)];
    NSButton *all = [self button:@"Restore All…" action:@selector(restoreAll:)];
    edit.identifier = @"shortcut.edit"; clear.identifier = @"shortcut.remove"; restore.identifier = @"shortcut.restore"; all.identifier = @"shortcut.restore-all";
    self.selectionButtons = @[edit, clear, restore];
    self.macroButton = [self button:@"Show in Macro Editor" action:@selector(showSelectedMacro:)];
    self.macroButton.identifier = @"shortcut.macro";
    self.macroButton.enabled = NO;
    NSStackView *primary = [NSStackView stackViewWithViews:@[edit,clear,restore]];
    primary.orientation = NSUserInterfaceLayoutOrientationHorizontal; primary.spacing = 8;
    NSStackView *secondary = [NSStackView stackViewWithViews:@[all,self.macroButton]];
    secondary.orientation = NSUserInterfaceLayoutOrientationHorizontal; secondary.spacing = 8;
    NSStackView *buttons = [NSStackView stackViewWithViews:@[primary,secondary]];
    buttons.orientation = NSUserInterfaceLayoutOrientationVertical; buttons.alignment = NSLayoutAttributeLeading; buttons.spacing = 8;
    for (NSView *view in @[self.searchMode,self.search,hint,scroll,buttons,self.keySearchView]) { view.translatesAutoresizingMaskIntoConstraints = NO; [content addSubview:view]; }
    NSView *header = self.settingsHeader;
    NSLayoutYAxisAnchor *searchTop = content.topAnchor;
    if (header != nil) {
        header.translatesAutoresizingMaskIntoConstraints = NO;
        [content addSubview:header];
        [NSLayoutConstraint activateConstraints:@[
            [header.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
            [header.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
            [header.topAnchor constraintEqualToAnchor:content.topAnchor]]];
        [self configureInputDisclosures];
        searchTop = header.bottomAnchor;
    }
    [NSLayoutConstraint activateConstraints:@[
        [self.searchMode.topAnchor constraintEqualToAnchor:searchTop constant:8],
        [self.searchMode.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [self.searchMode.centerYAnchor constraintEqualToAnchor:self.search.centerYAnchor],
        [self.search.widthAnchor constraintGreaterThanOrEqualToConstant:160],
        [self.keySearchView.leadingAnchor constraintEqualToAnchor:self.search.leadingAnchor],
        [self.keySearchView.trailingAnchor constraintEqualToAnchor:self.search.trailingAnchor],
        [self.keySearchView.topAnchor constraintEqualToAnchor:self.search.topAnchor],
        [self.keySearchView.bottomAnchor constraintEqualToAnchor:self.search.bottomAnchor],
        [self.search.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [self.search.trailingAnchor constraintEqualToAnchor:self.searchMode.leadingAnchor constant:-8],
        [hint.topAnchor constraintEqualToAnchor:self.search.bottomAnchor constant:12],
        [hint.leadingAnchor constraintEqualToAnchor:self.search.leadingAnchor], [hint.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [scroll.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:8],
        [scroll.leadingAnchor constraintEqualToAnchor:self.search.leadingAnchor], [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [buttons.topAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:8],
        [buttons.leadingAnchor constraintEqualToAnchor:self.search.leadingAnchor],
        [buttons.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-20],
        [buttons.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20]
    ]];
    [self reloadCommands];
}
- (void)configureInputDisclosures {
    NSView *candidate = self.settingsHeader.subviews.firstObject;
    if (![candidate isKindOfClass:NSStackView.class]) return;
    NSStackView *stack = (NSStackView *)candidate;
    stack.spacing = 8;
    // A compact header leaves room for the independently scrolling result list.
    for (NSLayoutConstraint *constraint in self.settingsHeader.constraints) {
        if (constraint.firstAttribute == NSLayoutAttributeTop) constraint.constant = 4;
        if (constraint.firstAttribute == NSLayoutAttributeBottom) constraint.constant = -4;
    }
    NSMutableArray<NSBox *> *groups = [NSMutableArray array];
    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
    for (NSView *view in [stack.arrangedSubviews copy]) {
        if (![view isKindOfClass:NSBox.class]) continue;
        NSBox *group = (NSBox *)view;
        for (NSLayoutConstraint *constraint in group.contentView.constraints) {
            if (constraint.firstAttribute == NSLayoutAttributeTop) constraint.constant = 4;
            if (constraint.firstAttribute == NSLayoutAttributeBottom) constraint.constant = -4;
        }
        NSButton *button = [NSButton buttonWithTitle:@"" target:self action:@selector(toggleInputGroup:)];
        [button setButtonType:NSButtonTypeOnOff]; button.bezelStyle = NSBezelStyleDisclosure;
        button.tag = (NSInteger)groups.count; button.state = NSControlStateValueOn;
        button.accessibilityValue = NSLocalizedString(@"Expanded", @"");
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.accessibilityLabel = group.accessibilityLabel;
        [button.widthAnchor constraintEqualToConstant:18].active = YES;
        [button.heightAnchor constraintEqualToConstant:18].active = YES;
        NSTextField *caption = [NSTextField wrappingLabelWithString:group.accessibilityLabel ?: @""];
        caption.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
        caption.identifier = [@"heading." stringByAppendingString:group.identifier ?: @""];
        NSStackView *disclosureRow = [NSStackView stackViewWithViews:@[button, caption]];
        disclosureRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        disclosureRow.alignment = NSLayoutAttributeCenterY;
        disclosureRow.spacing = 8;
        disclosureRow.translatesAutoresizingMaskIntoConstraints = NO;
        NSUInteger index = [stack.arrangedSubviews indexOfObject:group];
        [stack insertArrangedSubview:disclosureRow atIndex:index];
        [disclosureRow.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        NSView *body = group.contentView.subviews.firstObject;
        if ([body isKindOfClass:NSStackView.class]) {
            NSView *heading = ((NSStackView *)body).arrangedSubviews.firstObject;
            if ([heading.identifier hasPrefix:@"heading."]) [heading removeFromSuperview];
        }
        [groups addObject:group]; [buttons addObject:button];
    }
    self.inputGroups = groups; self.inputDisclosures = buttons;
}
- (void)setInputGroup:(NSUInteger)index expanded:(BOOL)expanded {
    if (index >= self.inputGroups.count) return;
    self.inputGroups[index].hidden = !expanded;
    self.inputDisclosures[index].state = expanded ? NSControlStateValueOn : NSControlStateValueOff;
    self.inputDisclosures[index].accessibilityValue = NSLocalizedString(expanded ? @"Expanded" : @"Collapsed", @"");
}
- (void)toggleInputGroup:(NSButton *)sender {
    BOOL expanded = sender.state == NSControlStateValueOn;
    if (self.compactInputs && expanded) for (NSUInteger index = 0; index < self.inputGroups.count; index++) [self setInputGroup:index expanded:NO];
    [self setInputGroup:(NSUInteger)sender.tag expanded:expanded];
}
- (void)viewDidLayout {
    [super viewDidLayout];
    BOOL compact = NSHeight(self.view.bounds) < 700;
    if (!self.configuredInputs || compact != self.compactInputs) {
        self.configuredInputs = YES; self.compactInputs = compact;
        for (NSUInteger index = 0; index < self.inputGroups.count; index++) [self setInputGroup:index expanded:!compact];
        if (self.highlightedCompletionRow != nil) [self revealCompletionGroup];
    }
}
- (void)revealCompletionGroup {
    for (NSUInteger index = 0; index < self.inputGroups.count; index++) {
        BOOL completion = [self.inputGroups[index].identifier isEqualToString:@"group.completion"];
        if (completion || self.compactInputs) [self setInputGroup:index expanded:completion];
    }
    [self.view layoutSubtreeIfNeeded];
}
- (void)reloadTable { [self.table reloadData]; }
- (void)reloadFunctionCommands {
    self.hint.stringValue = NSLocalizedString(@"Select a command to change its shortcut. Changes take effect immediately. Macros and text input key bindings use their own editors.", @"");
    if (self.store.unavailableCommands.count)
        self.hint.stringValue = [self.hint.stringValue stringByAppendingFormat:@"\n%@: %@", NSLocalizedString(@"Shortcut Unavailable", @""), [self.store.unavailableCommands componentsJoinedByString:@", "]];
    NSString *query = self.search.stringValue ?: @"";
    NSArray<NSString *> *tokens = TSSettingsQueryTokens(query);
    NSMutableArray *visible = [NSMutableArray array];
    for (TSShortcutCommand *command in self.store.commands) {
        if (command.item.hidden && !command.item.allowsKeyEquivalentWhenHidden) continue;
        if (!tokens.count || TSSettingsTextMatches(command.path, tokens)) [visible addObject:command];
    }
    self.visibleCommands = visible;
    [self reloadTable];
    for (NSButton *button in self.selectionButtons) button.enabled = [self selectedCommand] != nil;
}
- (void)controlTextDidChange:(NSNotification *)notification { if (!self.searchingByKey) { [self reloadCommands]; } }
- (void)reloadCommands {
    if (self.searchingByKey) { [self updateKeyResults]; }
    else { [self reloadFunctionCommands]; self.macroButton.enabled = NO; }
}
- (void)changeSearchMode:(NSSegmentedControl *)sender {
    if (sender.selectedSegment == TSShortcutSearchByFunction) { [self stopKeySearch]; return; }
    if (self.searchingByKey) { [self stopKeySearch]; return; }
    self.textQuery = self.search.stringValue;
    self.searchingByKey = YES;
    self.search.editable = NO;
    self.searchEvent = nil;
    self.keySearchView.hidden = NO;
    self.search.stringValue = @"";
    self.search.placeholderString = NSLocalizedString(@"Press a key", @"");
    [self updateKeyResults];
    NSWindow *window = self.window;
    if (window != nil) { [window makeFirstResponder:self.keySearchView]; }
}
- (void)stopKeySearch {
    [self clearCompletionHighlight];
    if (!self.searchingByKey) { return; }
    self.searchingByKey = NO;
    self.searchMode.selectedSegment = TSShortcutSearchByFunction;
    self.searchEvent = nil; self.searchMatches = @[];
    self.keySearchView.hidden = YES;
    self.search.editable = YES;
    self.search.stringValue = self.textQuery;
    self.search.placeholderString = NSLocalizedString(@"Search commands", @"");
    [self reloadCommands];
}
- (BOOL)handleKeySearchEvent:(NSEvent *)event {
    if (!self.searchingByKey) { return NO; }
    if (event.type != NSEventTypeKeyDown) { return YES; }
    NSEventModifierFlags flags = event.modifierFlags & TSShortcutModifiers;
    if (flags == 0 && [event.charactersIgnoringModifiers isEqualToString:@"\033"]) {
        [self stopKeySearch];
        NSWindow *window = self.window;
        if (window != nil && window.isKeyWindow) { [window makeFirstResponder:self.search]; }
        return YES;
    }
    self.searchEvent = event;
    [self updateKeyResults];
    return YES;
}
- (NSView *)completionRowInView:(NSView *)view {
    if ([view.identifier isEqualToString:@"row.settings.completion-trigger-label"]) return view;
    for (NSView *child in view.subviews) { NSView *found = [self completionRowInView:child]; if (found != nil) return found; }
    return nil;
}
- (void)clearCompletionHighlight {
    self.highlightedCompletionRow.layer.borderWidth = 0;
    self.highlightedCompletionRow = nil;
}
- (void)completionTriggerChanged:(NSNotification *)notification {
    if (self.searchingByKey) [self updateKeyResults];
}
- (void)updateKeyResults {
    [self clearCompletionHighlight];
    BOOL reservedCompletion = NO;
    TSShortcutStore *store = self.store;
    NSEvent *event = self.searchEvent;
    self.searchMatches = @[];
    self.searchMessage = NSLocalizedString(@"Press a key", @"");
    if (store != nil && event != nil) {
        NSDictionary *binding = TSRecordedBinding(event, [event charactersByApplyingModifiers:0]);
        NSString *key = binding[@"key"];
        NSEventModifierFlags flags = [binding[@"modifiers"] unsignedIntegerValue];
        self.search.stringValue = [TSShortcutStore displayKey:key modifiers:flags];
        NSArray<TSShortcutMacro *> *macros = self.shortcuts.macroProvider != nil ? self.shortcuts.macroProvider() : @[];
        self.searchMatches = [TSShortcutSearch matchesEvent:event store:store macros:macros];
        reservedCompletion = flags == 0 && [key isEqualToString:@"\t"] && ![[store.defaults stringForKey:@"CommandCompletionChar"] isEqualToString:@"ESCAPE"];
        if (reservedCompletion) {
            self.searchMatches = @[];
            self.searchMessage = NSLocalizedString(@"This key is reserved for command completion.", @"");
        } else if (key.length == 0 || ![TSShortcutStore isAllowedKey:key modifiers:flags]) {
            self.searchMessage = self.searchMatches.count > 0
                ? NSLocalizedString(@"Existing assignments are shown. This key cannot be assigned to a new shortcut.", @"")
                : NSLocalizedString(@"This key cannot be used as a shortcut. Use Command or Control with a key, or F1–F20.", @"");
        } else {
            self.searchMessage = self.searchMatches.count == 0 ? NSLocalizedString(@"No command uses this key.", @"") : NSLocalizedString(@"Assignment priority is shown; whether a command can run depends on the document.", @"");
        }
    }
    self.hint.stringValue = [self.searchMessage stringByAppendingFormat:@"\n%@", NSLocalizedString(@"Keys used by the system cannot be detected. Press Escape to stop recording.", @"")];
    NSString *value = self.search.stringValue.length ? [self.search.stringValue stringByAppendingFormat:@". %@", self.searchMessage] : self.searchMessage;
    if (self.searchEvent != nil) value = [value stringByAppendingFormat:@". %@", [NSString localizedStringWithFormat:NSLocalizedString(@"Matches: %lu", @"Number of key search results"), (unsigned long)self.searchMatches.count]];
    self.keySearchView.accessibilityValue = value;
    self.keySearchView.accessibilityHelp = self.hint.stringValue;
    NSAccessibilityPostNotification(self.keySearchView, NSAccessibilityValueChangedNotification);
    if (self.window.isKeyWindow) {
        NSAccessibilityPostNotificationWithUserInfo(self.keySearchView, NSAccessibilityAnnouncementRequestedNotification,
            @{NSAccessibilityAnnouncementKey:value, NSAccessibilityPriorityKey:@(NSAccessibilityPriorityMedium)});
    }
    [self reloadTable];
    NSInteger first = self.searchMatches.count > 0 ? (self.searchMatches[0].macro != nil ? 1 : 0) : -1;
    if (first >= 0) { [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)first] byExtendingSelection:NO]; [self.table scrollRowToVisible:first]; }
    [self updateSelectionButtons];
    if (reservedCompletion && self.settingsHeader != nil) {
        [self revealCompletionGroup];
        NSView *row = [self completionRowInView:self.settingsHeader];
        if (row == nil) return;
        row.wantsLayer = YES; row.layer.cornerRadius = 4;
        row.layer.borderColor = NSColor.controlAccentColor.CGColor; row.layer.borderWidth = 2;
        self.highlightedCompletionRow = row;
        [row scrollRectToVisible:NSInsetRect(row.bounds, -4, -4)];
        NSAccessibilityPostNotification(row, NSAccessibilityLayoutChangedNotification);
    }
}
- (NSInteger)macroHeaderRow {
    if (!self.searchingByKey) { return -1; }
    for (NSUInteger index = 0; index < self.searchMatches.count; index++) { if (self.searchMatches[index].macro != nil) { return (NSInteger)index; } }
    return -1;
}
- (TSShortcutMatch *)matchAtRow:(NSInteger)row {
    if (!self.searchingByKey || row < 0) { return nil; }
    NSInteger header = [self macroHeaderRow];
    if (row == header) { return nil; }
    if (header >= 0 && row > header) { row--; }
    return row < (NSInteger)self.searchMatches.count ? self.searchMatches[(NSUInteger)row] : nil;
}
- (void)showSelectedMacro:(id)sender {
    TSShortcutMacro *macro = [self matchAtRow:self.table.selectedRow].macro;
    if (macro == nil || self.shortcuts.showMacro == nil) { return; }
    [self stopKeySearch];
    self.shortcuts.showMacro(macro);
}
- (void)updateSelectionButtons {
    for (NSButton *button in self.selectionButtons) { button.enabled = [self selectedCommand] != nil; }
    self.macroButton.enabled = [self matchAtRow:self.table.selectedRow].macro != nil;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.searchingByKey ? (NSInteger)self.searchMatches.count + ([self macroHeaderRow] >= 0 ? 1 : 0) : (NSInteger)self.visibleCommands.count;
}
- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row { return self.searchingByKey && row == [self macroHeaderRow]; }
- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row { return ![self tableView:tableView isGroupRow:row]; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (self.searchingByKey) {
        if (row == [self macroHeaderRow]) { return [NSTextField labelWithString:[column.identifier isEqualToString:@"command"] ? NSLocalizedString(@"Macros", @"") : @""]; }
        TSShortcutMatch *match = [self matchAtRow:row];
        if (match == nil) { return nil; }
        NSString *key = match.macro != nil ? match.macro.key : match.menuItem.keyEquivalent;
        NSEventModifierFlags flags = match.macro != nil ? match.macro.modifiers : match.menuItem.keyEquivalentModifierMask;
        NSString *status = match.winner ? NSLocalizedString(@"Assigned", @"") : NSLocalizedString(@"Inactive for this key", @"");
        if (!match.winner) {
            for (TSShortcutMatch *owner in self.searchMatches) {
                if (!owner.winner) continue;
                NSString *ownerKey = owner.macro ? owner.macro.key : owner.menuItem.keyEquivalent;
                NSEventModifierFlags ownerFlags = owner.macro ? owner.macro.modifiers : owner.menuItem.keyEquivalentModifierMask;
                status = [NSString stringWithFormat:NSLocalizedString(@"This shortcut is inactive because it conflicts with “%@” (%@).", @""),
                    owner.path, [TSShortcutStore displayKey:ownerKey modifiers:ownerFlags]];
                break;
            }
        }
        NSString *text = [column.identifier isEqualToString:@"command"] ? [match.path stringByAppendingFormat:@" — %@", status] : [TSShortcutStore displayKey:key modifiers:flags];
        NSTextField *label = [NSTextField labelWithString:text]; label.lineBreakMode = NSLineBreakByTruncatingMiddle; label.toolTip = text;
        return label;
    }
    if (row < 0 || row >= (NSInteger)self.visibleCommands.count) { return nil; }
    TSShortcutCommand *command = self.visibleCommands[(NSUInteger)row];
    BOOL isCommand = [column.identifier isEqualToString:@"command"];
    NSTextField *label = [NSTextField labelWithString:isCommand ? command.path : [TSShortcutStore displayKey:command.item.keyEquivalent modifiers:command.item.keyEquivalentModifierMask]];
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    label.toolTip = command.path;
    return label;
}
- (TSShortcutCommand *)selectedCommand {
    NSInteger row = self.table.selectedRow;
    if (self.searchingByKey) { return [self matchAtRow:row].command; }
    return row >= 0 && row < (NSInteger)self.visibleCommands.count ? self.visibleCommands[row] : nil;
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification { [self updateSelectionButtons]; }
- (void)showError:(NSString *)error {
    NSWindow *parent = self.capturePanel ?: self.window;
    if (error == nil || parent == nil || parent.attachedSheet != nil) { return; }
    NSAlert *alert = [NSAlert new]; alert.messageText = NSLocalizedString(@"Shortcut Unavailable", @""); alert.informativeText = error;
    [alert beginSheetModalForWindow:parent completionHandler:nil];
}
- (void)confirmMacrosUsingKey:(NSString *)key modifiers:(NSEventModifierFlags)flags completion:(void (^)(BOOL))completion {
    NSArray *macros = [self.store macrosUsingKey:key modifiers:flags];
    if (!macros.count) { completion(YES); return; }
    NSWindow *parent = self.capturePanel ?: self.window;
    if (parent == nil || parent.attachedSheet != nil) { completion(NO); return; }
    NSAlert *alert = [NSAlert new];
    alert.messageText = NSLocalizedString(@"Assign a shortcut used by macros?", @"");
    alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"The following macros use this shortcut. Assigning it to the menu command will make their shortcuts inactive. Their files will not be changed.\n\n%@", @""), [macros componentsJoinedByString:@"\n"]];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
    [alert addButtonWithTitle:NSLocalizedString(@"Assign", @"")];
    __weak typeof(self) weakSelf = self;
    [alert beginSheetModalForWindow:parent completionHandler:^(NSModalResponse response) {
        TSShortcutPaneController *strongSelf = weakSelf;
        if (strongSelf == nil) { return; }
        BOOL unchanged = [[strongSelf.store macrosUsingKey:key modifiers:flags] isEqualToArray:macros];
        completion(response == NSAlertSecondButtonReturn && unchanged);
    }];
}
- (void)removeShortcut:(id)sender {
    TSShortcutCommand *command = self.selectedCommand; if (!command) return;
    [self showError:[self.store setKey:@"" modifiers:0 forCommand:command]];
    [self refreshMenuAndMacros];
}
- (void)restoreShortcut:(id)sender {
    TSShortcutCommand *command = self.selectedCommand; if (!command) return;
    NSString *error = [self.store conflictForRestoringCommand:command];
    if (error) { [self showError:[NSString stringWithFormat:NSLocalizedString(@"This shortcut is already used by “%@”.", @""), error]]; return; }
    __weak typeof(self) weakSelf = self;
    [self confirmMacrosUsingKey:command.defaultKey modifiers:command.defaultModifiers completion:^(BOOL accepted) {
        TSShortcutPaneController *strongSelf = weakSelf;
        if (strongSelf == nil || !accepted) { return; }
        [strongSelf showError:[strongSelf.store restoreCommand:command]];
        [strongSelf refreshMenuAndMacros];
    }];
}
- (void)restoreAll:(id)sender {
    NSWindow *parent = self.window;
    if (parent == nil || parent.attachedSheet != nil) { return; }
    NSAlert *alert = [NSAlert new]; alert.messageText = NSLocalizedString(@"Restore all keyboard shortcuts?", @"");
    alert.informativeText = NSLocalizedString(@"Custom menu shortcuts will be removed. Existing KeyEquivalents.plist settings will be preserved.", @"");
    NSArray *macros = [self.store macrosAffectedByRestoringAll];
    if (macros.count) alert.informativeText = [alert.informativeText stringByAppendingFormat:@"\n\n%@\n%@",
        NSLocalizedString(@"These macro shortcuts will become inactive:", @""), [macros componentsJoinedByString:@"\n"]];
    [alert addButtonWithTitle:NSLocalizedString(@"Restore All", @"")]; [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
    __weak typeof(self) weakSelf = self;
    [alert beginSheetModalForWindow:parent completionHandler:^(NSModalResponse response) {
        TSShortcutPaneController *strongSelf = weakSelf;
        if (strongSelf == nil || response != NSAlertFirstButtonReturn) { return; }
        [strongSelf.store restoreAll]; [strongSelf refreshMenuAndMacros];
    }];
}
- (void)editShortcut:(id)sender {
    NSWindow *parent = self.window;
    TSShortcutCommand *command = self.selectedCommand;
    if (command == nil || parent == nil || parent.attachedSheet != nil) { return; }
    [self stopKeySearch];
    self.editingCommand = command; self.capturedKey = nil; self.capturedBindings = nil;
    TSShortcutCapturePanel *panel = [[TSShortcutCapturePanel alloc] initWithContentRect:NSMakeRect(0,0,640,240) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    self.capturePanel = panel;
    panel.title = NSLocalizedString(@"Change Shortcut", @"");
    TSShortcutRecorder *recorder = [[TSShortcutRecorder alloc] initWithFrame:panel.contentView.bounds];
    recorder.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    panel.contentView = recorder; panel.recorder = recorder;
    NSTextField *title = [NSTextField labelWithString:command.path]; title.frame = NSMakeRect(20,195,600,25); title.lineBreakMode = NSLineBreakByTruncatingMiddle; title.toolTip = command.path;
    self.captureDisplay = [NSTextField labelWithString:NSLocalizedString(@"Press the new shortcut (Escape to cancel).", @"")];
    self.captureDisplay.frame = NSMakeRect(20,145,600,40); self.captureDisplay.font = [NSFont systemFontOfSize:18]; self.captureDisplay.alignment = NSTextAlignmentCenter;
    self.captureError = [NSTextField wrappingLabelWithString:@""]; self.captureError.frame = NSMakeRect(20,65,600,70); self.captureError.textColor = NSColor.secondaryLabelColor;
    self.applyButton = [self button:@"Apply" action:@selector(applyCapturedShortcut:)]; self.applyButton.enabled = NO;
    NSButton *cancel = [self button:@"Cancel" action:@selector(cancelCapture:)];
    self.applyButton.keyEquivalent = @"\r"; cancel.keyEquivalent = @"\033";
    recorder.nextKeyView = self.applyButton; self.applyButton.nextKeyView = cancel; cancel.nextKeyView = recorder;
    [self.applyButton sizeToFit]; [cancel sizeToFit];
    self.applyButton.frame = NSMakeRect(620-NSWidth(self.applyButton.frame),18,NSWidth(self.applyButton.frame),32);
    cancel.frame = NSMakeRect(NSMinX(self.applyButton.frame)-NSWidth(cancel.frame)-12,18,NSWidth(cancel.frame),32);
    for (NSView *view in @[title,self.captureDisplay,self.captureError,self.applyButton,cancel]) [recorder addSubview:view];
    __weak typeof(self) weakSelf = self;
    recorder.record = ^(NSEvent *event) { TSShortcutPaneController *strongSelf = weakSelf; if (strongSelf != nil) { [strongSelf recordShortcutEvent:event]; } };
    recorder.accept = ^{ TSShortcutPaneController *strongSelf = weakSelf; if (strongSelf != nil) { [strongSelf applyCapturedShortcut:nil]; } };
    recorder.cancel = ^{ TSShortcutPaneController *strongSelf = weakSelf; if (strongSelf != nil) { [strongSelf cancelCapture:nil]; } };
    [parent beginSheet:panel completionHandler:^(NSModalResponse result) {
        panel.recorder.record = nil; panel.recorder.accept = nil; panel.recorder.cancel = nil;
        TSShortcutPaneController *strongSelf = weakSelf;
        if (strongSelf == nil) { return; }
        strongSelf.capturePanel = nil; strongSelf.editingCommand = nil;
        [strongSelf reloadCommands];
    }];
    [panel makeFirstResponder:recorder];
    panel.initialFirstResponder = recorder;
}
- (void)recordShortcutEvent:(NSEvent *)event {
    NSString *key = TSShortcutCharacterForEvent(event);
    NSEventModifierFlags flags = event.modifierFlags & TSShortcutModifiers;
    self.captureError.stringValue = @"";
    self.applyButton.enabled = [TSShortcutStore isAllowedKey:key modifiers:flags] && key.length > 0;
    if (!self.applyButton.enabled) {
        self.capturedKey = nil; self.capturedBindings = nil;
        self.captureDisplay.stringValue = NSLocalizedString(@"Press the new shortcut (Escape to cancel).", @"");
        self.captureError.stringValue = NSLocalizedString(@"Use Command or Control with a key, or a function key (F1–F20).", @"");
    } else {
        self.capturedBindings = TSEventBindings(event, [event charactersByApplyingModifiers:0]);
        NSDictionary *binding = self.capturedBindings.firstObject;
        self.capturedKey = binding[@"key"] ?: @""; self.capturedModifiers = [binding[@"modifiers"] unsignedIntegerValue];
        self.captureDisplay.stringValue = [TSShortcutStore displayKey:self.capturedKey modifiers:self.capturedModifiers];
    }
    self.capturePanel.recorder.accessibilityValue = self.captureDisplay.stringValue;
}
- (void)cancelCapture:(id)sender {
    NSWindow *parent = self.window;
    TSShortcutCapturePanel *panel = self.capturePanel;
    if (parent != nil && panel != nil && panel.attachedSheet == nil) { [parent endSheet:panel returnCode:NSModalResponseCancel]; }
}
- (NSString *)conflictForCapturedShortcut {
    NSArray *bindings = self.capturedBindings ?: @[TSBinding(self.capturedKey, self.capturedModifiers)];
    NSMutableOrderedSet *conflicts = [NSMutableOrderedSet orderedSet];
    for (NSDictionary *binding in bindings) {
        NSString *path = [self.store conflictForKey:binding[@"key"] ?: @"" modifiers:[binding[@"modifiers"] unsignedIntegerValue]
            except:self.editingCommand.item restoring:nil];
        if (path) [conflicts addObject:path];
    }
    if (!conflicts.count) return nil;
    if (conflicts.count == 1)
        return [NSString stringWithFormat:NSLocalizedString(@"This shortcut is already used by “%@”.", @""), conflicts.firstObject];
    return [NSString stringWithFormat:NSLocalizedString(@"This shortcut is already used by:\n%@", @""),
        [conflicts.array componentsJoinedByString:@"\n"]];
}
- (void)applyCapturedShortcut:(id)sender {
    NSString *key = self.capturedKey;
    TSShortcutCommand *command = self.editingCommand;
    NSEventModifierFlags flags = self.capturedModifiers;
    if (key == nil || command == nil || !self.applyButton.enabled) { return; }
    NSString *conflict = [self conflictForCapturedShortcut];
    if (conflict != nil) { self.captureError.stringValue = conflict; return; }
    __weak typeof(self) weakSelf = self;
    [self confirmMacrosUsingKey:key modifiers:flags completion:^(BOOL accepted) {
        TSShortcutPaneController *strongSelf = weakSelf;
        if (strongSelf == nil || !accepted || strongSelf.editingCommand != command ||
            ![strongSelf.capturedKey isEqualToString:key] || strongSelf.capturedModifiers != flags) { return; }
        NSString *error = [strongSelf conflictForCapturedShortcut];
        if (error == nil) { error = [strongSelf.store setKey:key modifiers:flags forCommand:command]; }
        [strongSelf refreshMenuAndMacros];
        TSShortcutCapturePanel *panel = strongSelf.capturePanel;
        if (error != nil) {
            strongSelf.captureError.stringValue = error;
            if (panel != nil) { [panel makeFirstResponder:panel.recorder]; }
            return;
        }
        NSWindow *parent = strongSelf.window;
        if (parent != nil && panel != nil) { [parent endSheet:panel returnCode:NSModalResponseOK]; }
    }];
}
- (void)applySettingsQuery:(NSString *)query targets:(NSArray<NSString *> *)targets filterCommands:(BOOL)filter
{
    [self stopKeySearch];
    if (!self.isViewLoaded) return;
    if (filter) {
        if (self.functionQueryBeforeGlobalSearch == nil) self.functionQueryBeforeGlobalSearch = self.search.stringValue;
        self.search.stringValue = query; [self reloadFunctionCommands];
    } else {
        NSString *previous = self.functionQueryBeforeGlobalSearch;
        if (previous != nil) { self.search.stringValue = previous; self.functionQueryBeforeGlobalSearch = nil; [self reloadFunctionCommands]; }
    }
    // Prefer the most specific matching control, even if another group contains
    // an individual word from the query. The caller orders targets by relevance.
    BOOL revealed = NO;
    for (NSString *target in targets) {
        for (NSUInteger index = 0; index < self.inputGroups.count; index++) {
            NSBox *group = self.inputGroups[index];
            NSMutableArray<NSView *> *queue = [NSMutableArray arrayWithObject:group];
            BOOL found = [target isEqualToString:[@"heading." stringByAppendingString:group.identifier ?: @""]];
            while (queue.count) {
                NSView *view = queue.lastObject; [queue removeLastObject];
                NSString *identifier = view.identifier;
                if (identifier != nil && [target isEqualToString:identifier]) found = YES;
                [queue addObjectsFromArray:view.subviews];
            }
            if (found) {
                for (NSUInteger other = 0; other < self.inputGroups.count; other++) [self setInputGroup:other expanded:other == index];
                revealed = YES; break;
            }
        }
        if (revealed) break;
    }
    [self.view layoutSubtreeIfNeeded];
}
@end
