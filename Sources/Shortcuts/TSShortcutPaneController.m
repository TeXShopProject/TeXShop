// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSShortcutInternal.h"
#import "TSPreferenceKey.h"
#import "TSPrefPaneLayout.h"
#import "TSSettingsSearchText.h"
#import "TSShortcutKeyRecorder.h"
#import <QuartzCore/QuartzCore.h>
// Lies over the search field, so it also handles the field's cancel button.
@interface TSShortcutKeySearchView : NSView
@property (copy, nullable) BOOL (^handleEvent)(NSEvent *event);
@property (copy, nullable) dispatch_block_t clearKey;
@property (weak, nullable) NSSearchField *searchField;
@property BOOL pressingCancelButton;
@end
@implementation TSShortcutKeySearchView
- (BOOL)acceptsFirstResponder { return YES; }
// The search field shows its cancel button only while it shows a key.
- (BOOL)showsCancelButton { return self.clearKey != nil && self.searchField.stringValue.length > 0; }
- (BOOL)cancelButtonContainsEvent:(NSEvent *)event {
    NSSearchField *field = self.searchField;
    if (field == nil || !self.showsCancelButton) { return NO; }
    NSRect button = [field convertRect:[(NSSearchFieldCell *)field.cell cancelButtonRectForBounds:field.bounds] toView:self];
    return NSMouseInRect([self convertPoint:event.locationInWindow fromView:nil], button, self.isFlipped);
}
- (void)mouseDown:(NSEvent *)event {
    self.pressingCancelButton = [self cancelButtonContainsEvent:event];
    if (!self.pressingCancelButton) { [super mouseDown:event]; }
}
- (void)mouseUp:(NSEvent *)event {
    BOOL clear = self.pressingCancelButton && [self cancelButtonContainsEvent:event];
    self.pressingCancelButton = NO;
    if (clear) { self.clearKey(); } else { [super mouseUp:event]; }
}
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(accessibilityPerformCancel)) { return self.showsCancelButton; }
    return [super isAccessibilitySelectorAllowed:selector];
}
- (BOOL)accessibilityPerformCancel {
    if (!self.showsCancelButton) { return NO; }
    self.clearKey();
    return YES;
}
- (BOOL)isAccessibilityElement { return YES; }
- (NSString *)accessibilityRole { return NSAccessibilityTextFieldRole; }
- (NSString *)accessibilityLabel { return NSLocalizedString(@"Search by Key", @""); }
- (void)keyDown:(NSEvent *)event { [self performKeyEquivalent:event]; }
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (self.handleEvent == nil) { return NO; }
    return self.handleEvent(event);
}
@end

// The menu shortcut list. As in Xcode's key bindings, a click on the shortcut of
// the selected row, a double click, or Return records a new shortcut in the row.
@interface TSShortcutTableView : NSTableView
@property (copy, nullable) void (^beginRecording)(NSInteger row);
@property NSInteger rowSelectedAtMouseDown;
@end
@implementation TSShortcutTableView
- (void)mouseDown:(NSEvent *)event {
    self.rowSelectedAtMouseDown = self.selectedRow;
    [super mouseDown:event];
}
- (void)keyDown:(NSEvent *)event {
    NSString *key = event.charactersIgnoringModifiers;
    if (!(event.modifierFlags & TSShortcutModifiers) && ([key isEqual:@"\r"] || [key isEqual:@"\003"]) && self.selectedRow >= 0 && self.beginRecording) {
        self.beginRecording(self.selectedRow);
        return;
    }
    [super keyDown:event];
}
@end

typedef NS_ENUM(NSInteger, TSShortcutSearchMode) {
    TSShortcutSearchByFunction,
    TSShortcutSearchByKey
};

// One row of the function list: a command Settings can list, or a menu item AppKit keeps.
@interface TSShortcutFunctionRow : NSObject
@property (strong, nullable) TSShortcutCommand *command;
@property (strong, nullable) NSMenuItem *item;
@property (copy) NSString *path;
@end
@implementation TSShortcutFunctionRow
@end

@interface TSShortcutPaneController () <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
@property (strong) TSKeyboardShortcuts *shortcuts;
@property BOOL runningAfterLayoutKeys;
// Keyboard layout changes seen, so that a restore or recording that waited for the keys of a
// layout is dropped when the layout changed meanwhile, even back to the same one.
@property NSUInteger layoutChanges;
@property (copy) NSString *lastLayout;
@property (readwrite) BOOL searchingByKey;
@property (strong) NSSegmentedControl *searchMode;
@property (strong) TSShortcutKeySearchView *keySearchView;
@property (weak) NSView *commandsView;
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
@property (nullable) NSView *highlightedCompletionRow;
@property NSSearchField *search;
@property NSArray<TSShortcutCommand *> *visibleCommands;
// The function list, in menu order. A command Settings lists, and a menu item with a shortcut and no command.
@property NSArray<TSShortcutFunctionRow *> *functionRows;
@property NSArray<NSButton *> *selectionButtons;
@property (nullable) TSShortcutCommand *editingCommand;
@property TSShortcutKeyRecorder *recorder;
@property NSView *recordingCell;
@property NSImageView *recordingWarning;
@property (copy, nullable) NSString *recordingError;
@property BOOL endingRecording;
@property BOOL confirmingRecording;
@property NSStackView *status;
@property NSTextField *statusText;
// Shown with "Cannot Be Changed": a link into Keyboard Shortcuts, and where to go next.
@property NSTextField *systemSettingsLink;
@property NSTextField *systemSettingsGuide;
@property (nullable) NSString *capturedKey;
@property (copy) NSArray<TSShortcutBinding *> *capturedBindings;
@property NSEventModifierFlags capturedModifiers;
@end
@implementation TSShortcutPaneController
@synthesize functionQueryBeforeGlobalSearch = _functionQueryBeforeGlobalSearch;
@synthesize settingsHeader = _settingsHeader;
@synthesize highlightedCompletionRow = _highlightedCompletionRow;
- (instancetype)initWithShortcuts:(TSKeyboardShortcuts *)shortcuts {
    self = [super initWithNibName:nil bundle:nil];
    if (self == nil) { return nil; }
    _shortcuts = shortcuts;
    _store = shortcuts.store;
    _textQuery = @""; _searchMatches = @[]; _searchMessage = @"";
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(shortcutsChanged:) name:TSMacroShortcutsChangedNotification object:shortcuts];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(completionTriggerChanged:) name:TSCompletionChangedNotification object:nil];
    _lastLayout = [TSKeyboardLayoutID() copy];
    for (NSNotificationName name in @[NSTextInputContextKeyboardSelectionDidChangeNotification, NSApplicationDidBecomeActiveNotification])
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardLayoutMayHaveChanged:) name:name object:nil];
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
    self.keySearchView.searchField = self.search;
    self.keySearchView.clearKey = ^{ [weakSelf clearKeySearch]; };
    NSTextField *hint = [NSTextField wrappingLabelWithString:@""];
    hint.identifier = @"shortcut.hint";
    hint.textColor = NSColor.secondaryLabelColor; self.hint = hint;
    NSScrollView *scroll = [NSScrollView new];
    scroll.hasVerticalScroller = YES; scroll.hasHorizontalScroller = YES; scroll.borderType = NSNoBorder; scroll.drawsBackground = NO; scroll.automaticallyAdjustsContentInsets = NO;
    TSShortcutTableView *table = [TSShortcutTableView new];
    self.table = table;
    self.table.delegate = self; self.table.dataSource = self;
    self.table.rowHeight = 22; self.table.style = NSTableViewStyleInset; self.table.usesAlternatingRowBackgroundColors = YES;
    self.table.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
    self.table.doubleAction = @selector(editShortcut:); self.table.action = @selector(tableClicked:); self.table.target = self;
    __weak TSShortcutPaneController *weakPane = self;
    table.beginRecording = ^(NSInteger row) { [weakPane beginRecordingAtRow:row]; };
    NSTableColumn *command = [[NSTableColumn alloc] initWithIdentifier:@"command"];
    command.title = NSLocalizedString(@"Command", @""); command.width = 300; command.minWidth = 200;
    NSTableColumn *shortcut = [[NSTableColumn alloc] initWithIdentifier:@"shortcut"];
    shortcut.title = NSLocalizedString(@"Shortcut", @""); shortcut.width = 150; shortcut.minWidth = 130;
    [self.table addTableColumn:command]; [self.table addTableColumn:shortcut];
    scroll.documentView = self.table;
    // The command list shows at least six commands and takes, with the key
    // binding list, the height a taller window leaves.
    CGFloat minimum = 6 * (self.table.rowHeight + self.table.intercellSpacing.height) + 28;
    [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:minimum].active = YES;
    NSLayoutConstraint *compactList = [scroll.heightAnchor constraintEqualToConstant:minimum];
    compactList.priority = 1; compactList.active = YES;
    [scroll setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
    self.table.headerView.identifier = @"shortcut.columns";
    NSButton *restore = [self button:@"Restore Default" action:@selector(restoreShortcut:)];
    NSButton *all = [self button:@"Restore All…" action:@selector(restoreAll:)];
    restore.identifier = @"shortcut.restore"; all.identifier = @"shortcut.restore-all";
    self.selectionButtons = @[restore];
    self.macroButton = [self button:@"Show in Macro Editor" action:@selector(showSelectedMacro:)];
    self.macroButton.identifier = @"shortcut.macro";
    self.macroButton.enabled = NO;
    NSView *spacer = [NSView new];
    [spacer setContentHuggingPriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *buttons = [NSStackView stackViewWithViews:@[restore,self.macroButton,spacer,all]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal; buttons.spacing = 8;
    for (NSButton *button in @[restore,self.macroButton,all]) {
        button.controlSize = NSControlSizeSmall; button.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    }
    [self makeRecorder];
    // Under the list, as in Xcode: the selected command's default shortcut, or why a recorded key was refused.
    self.status = [self warningWithText:@" "];
    self.status.identifier = @"shortcut.status";
    self.statusText = (NSTextField *)self.status.arrangedSubviews[1];
    self.statusText.identifier = @"shortcut.status-text"; self.statusText.alignment = NSTextAlignmentCenter;
    self.status.arrangedSubviews[0].hidden = YES;
    self.systemSettingsLink = [self systemSettingsLinkField];
    self.systemSettingsGuide = [self systemSettingsGuideField];
    // Hidden rows leave this column the height of the status line alone.
    NSStackView *statusColumn = [NSStackView stackViewWithViews:@[self.status, self.systemSettingsLink, self.systemSettingsGuide]];
    statusColumn.orientation = NSUserInterfaceLayoutOrientationVertical;
    statusColumn.alignment = NSLayoutAttributeCenterX;
    statusColumn.spacing = 2;
    statusColumn.identifier = @"shortcut.status-column";
    for (NSView *view in @[self.searchMode,self.search,hint,scroll,statusColumn,buttons,self.keySearchView]) { view.translatesAutoresizingMaskIntoConstraints = NO; [content addSubview:view]; }
    content.identifier = @"shortcut.commands"; self.commandsView = content;
    hint.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    [NSLayoutConstraint activateConstraints:@[
        [self.search.topAnchor constraintEqualToAnchor:content.topAnchor constant:10],
        [self.searchMode.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],
        [self.searchMode.centerYAnchor constraintEqualToAnchor:self.search.centerYAnchor],
        [self.search.widthAnchor constraintGreaterThanOrEqualToConstant:120],
        [self.keySearchView.leadingAnchor constraintEqualToAnchor:self.search.leadingAnchor],
        [self.keySearchView.trailingAnchor constraintEqualToAnchor:self.search.trailingAnchor],
        [self.keySearchView.topAnchor constraintEqualToAnchor:self.search.topAnchor],
        [self.keySearchView.bottomAnchor constraintEqualToAnchor:self.search.bottomAnchor],
        [self.search.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:12],
        [self.search.trailingAnchor constraintEqualToAnchor:self.searchMode.leadingAnchor constant:-8],
        [hint.topAnchor constraintEqualToAnchor:self.search.bottomAnchor constant:6],
        [hint.leadingAnchor constraintEqualToAnchor:self.search.leadingAnchor], [hint.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],
        [scroll.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:4],
        [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:4], [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-4],
        [statusColumn.topAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:4],
        [statusColumn.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
        [statusColumn.leadingAnchor constraintGreaterThanOrEqualToAnchor:content.leadingAnchor constant:12],
        [statusColumn.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-12],
        [buttons.topAnchor constraintEqualToAnchor:statusColumn.bottomAnchor constant:6],
        [buttons.leadingAnchor constraintEqualToAnchor:self.search.leadingAnchor],
        [buttons.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],
        [buttons.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-10]
    ]];
    NSView *settingsHeader = self.settingsHeader;
    if (settingsHeader != nil) {
        NSView *group = [self viewWithIdentifier:@"group.shortcuts" inView:settingsHeader];
        NSStackView *rows = (NSStackView *)((TSSettingsGroupView *)group).contentView.subviews.firstObject;
        if (rows == nil) [NSException raise:NSInternalInconsistencyException format:@"Missing shortcuts catalog group"];
        content.translatesAutoresizingMaskIntoConstraints = NO;
        [rows addArrangedSubview:content]; [content.widthAnchor constraintEqualToAnchor:rows.widthAnchor].active = YES;
        // Rebuild this card after adding its real content, so its fill starts below the heading.
        for (NSView *view in group.subviews.copy) if ([view.identifier isEqual:@"card.background"]) [view removeFromSuperview];
        [TSPrefPaneLayout decorateGroupsInView:group];
        // The two lists share the extra height equally.
        NSView *bindings = [self viewWithIdentifier:@"keybindings.list" inView:settingsHeader];
        if (bindings != nil) {
            NSLayoutConstraint *share = [scroll.heightAnchor constraintEqualToAnchor:bindings.heightAnchor];
            share.priority = 150; share.active = YES;
        }
        self.view = settingsHeader;
    }
    [self reloadCommands];
}
- (NSView *)viewWithIdentifier:(NSString *)identifier inView:(NSView *)view {
    if ([view.identifier isEqual:identifier]) return view;
    for (NSView *child in view.subviews) { NSView *found = [self viewWithIdentifier:identifier inView:child]; if (found) return found; }
    return nil;
}
- (void)reloadTable {
    // A pending macro confirmation keeps its command; the reply checks it again.
    if (self.editingCommand != nil && !self.confirmingRecording) { [self endRecording]; }
    [self.table reloadData];
    [self updateStatus];
}
// The function list in menu order. Commands Settings lists stay as they are. A menu item AppKit inserts, such as
// Minimize All, has a shortcut and no command: key search already shows it as unchangeable, and so does this list.
- (void)reloadFunctionCommands {
    self.hint.stringValue = @"";
    if (self.store.unavailableCommands.count)
        self.hint.stringValue = [self.hint.stringValue stringByAppendingFormat:@"\n%@: %@", NSLocalizedString(@"Shortcut Unavailable", @""), [self.store.unavailableCommands componentsJoinedByString:@", "]];
    NSString *query = self.search.stringValue ?: @"";
    NSArray<NSString *> *tokens = TSSettingsQueryTokens(query);
    NSMapTable<NSMenuItem *, TSShortcutCommand *> *byItem = [NSMapTable strongToStrongObjectsMapTable];
    for (TSShortcutCommand *command in self.store.commands) [byItem setObject:command forKey:command.item];
    NSMutableArray<TSShortcutCommand *> *visible = [NSMutableArray array];
    NSMutableArray<TSShortcutFunctionRow *> *rows = [NSMutableArray array];
    TSVisitMenu(self.store.menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (item.submenu != nil || item.action == TSMacroAction()) return;
        if (item.hidden) { if (!item.allowsKeyEquivalentWhenHidden) return; }
        TSShortcutCommand *command = [byItem objectForKey:item];
        // An item with no command and no shortcut is not a row of this list.
        if (command == nil && item.keyEquivalent.length == 0) return;
        NSString *name = command != nil ? command.path : path;
        if (tokens.count && !TSSettingsTextMatches(name, tokens)) return;
        TSShortcutFunctionRow *row = [TSShortcutFunctionRow new];
        row.command = command; row.item = item; row.path = name;
        [rows addObject:row];
        if (command != nil) [visible addObject:command];
    });
    self.visibleCommands = visible;
    self.functionRows = rows;
    [self reloadTable];
    for (NSButton *button in self.selectionButtons) button.enabled = [self selectedCommand] != nil && ![self selectedCommand].managedBySystem;
    [self updateStatus];
}
- (TSShortcutFunctionRow *)functionRowAtIndex:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.functionRows.count) return nil;
    return self.functionRows[(NSUInteger)row];
}
// Gray rows of the function list have no shortcut Settings can restore. Key search says so on the row.
- (BOOL)selectedFunctionRowCannotChange {
    if (self.searchingByKey && self.searchEvent != nil) return NO;
    TSShortcutFunctionRow *row = [self functionRowAtIndex:self.table.selectedRow];
    return row != nil && (row.command == nil || row.command.managedBySystem);
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
    [self reloadFunctionCommands];
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
// Key search lasts while the focus stays in the menu shortcut controls; the
// selection buttons there act on the selected match.
- (void)windowFirstResponderChanged:(NSResponder *)responder {
    if (!self.searchingByKey) { return; }
    NSView *view = [responder isKindOfClass:NSView.class] ? (NSView *)responder : nil;
    if ([view isKindOfClass:NSText.class] && ((NSText *)view).fieldEditor && [((NSText *)view).delegate isKindOfClass:NSView.class])
        view = (NSView *)((NSText *)view).delegate;
    NSView *commands = self.commandsView;
    if (view == nil || commands == nil || [view isDescendantOf:commands]) { return; }
    [self stopKeySearch];
}
// Forgets the searched key and waits for the next one, as on entering key search.
- (void)clearKeySearch {
    if (!self.searchingByKey) { return; }
    self.searchEvent = nil;
    self.search.stringValue = @"";
    [self.table deselectAll:nil];
    [self reloadFunctionCommands];
    [self updateKeyResults];
    NSWindow *window = self.window;
    if (window != nil) { [window makeFirstResponder:self.keySearchView]; }
}
- (BOOL)handleKeySearchEvent:(NSEvent *)event {
    if (self.editingCommand != nil && self.window.firstResponder == self.recorder) { return [self handleRecordingEvent:event]; }
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
// The rows of Settings › Keyboard › Command Completion that the trigger key shows.
static NSString * const TSCompletionTriggerRowID = @"row.catalog.keyboard.1.0";
static NSString * const TSCompletionMarkKeysRowID = @"row.catalog.keyboard.1.3";
- (NSView *)rowWithIdentifier:(NSString *)identifier inView:(NSView *)view {
    if ([view.identifier isEqualToString:identifier]) return view;
    for (NSView *child in view.subviews) { NSView *found = [self rowWithIdentifier:identifier inView:child]; if (found != nil) return found; }
    return nil;
}
- (NSView *)completionRowInView:(NSView *)view {
    return [self rowWithIdentifier:TSCompletionTriggerRowID inView:view];
}
- (void)clearCompletionHighlight {
    self.highlightedCompletionRow.layer.backgroundColor = nil;
    self.highlightedCompletionRow = nil;
}
- (void)completionTriggerChanged:(NSNotification *)notification {
    if (self.searchingByKey) [self updateKeyResults];
}
- (void)updateKeyResults {
    [self clearCompletionHighlight];
    BOOL reservedCompletion = NO;
    NSString *completionRow = TSCompletionTriggerRowID;
    TSShortcutStore *store = self.store;
    NSEvent *event = self.searchEvent;
    self.searchMatches = @[];
    self.searchMessage = NSLocalizedString(@"Press a key", @"");
    if (store != nil && event != nil) {
        TSShortcutBinding *binding = TSRecordedBinding(event, [event charactersByApplyingModifiers:0]);
        NSString *key = binding[@"key"];
        NSEventModifierFlags flags = binding.modifiers;
        // With the Globe key, as the list shows Enter Full Screen's 🌐︎F.
        self.search.stringValue = [TSShortcutStore displayKey:key modifiers:flags | TSEventGlobeModifier(event)];
        NSArray<TSShortcutMacro *> *macros = self.shortcuts.macroProvider != nil ? self.shortcuts.macroProvider() : @[];
        self.searchMatches = [TSShortcutSearch matchesEvent:event store:store macros:macros];
        // The trigger key with Shift (the previous candidate), Option or Control (the next or
        // previous mark) belongs to command completion too; plain Escape ends the search.
        BOOL escapeTrigger = [[store.defaults stringForKey:TSCommandCompletionCharacterKey] isEqualToString:@"ESCAPE"];
        BOOL triggerKey = escapeTrigger ? [key isEqualToString:@"\033"] : ([key isEqualToString:@"\t"] || [key isEqualToString:@"\031"]);
        NSEventModifierFlags completionFlags = flags & (NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagCommand);
        reservedCompletion = triggerKey && (completionFlags == 0 || completionFlags == NSEventModifierFlagShift ||
                                            completionFlags == NSEventModifierFlagOption || completionFlags == NSEventModifierFlagControl);
        completionRow = (completionFlags == NSEventModifierFlagOption || completionFlags == NSEventModifierFlagControl)
            ? TSCompletionMarkKeysRowID : TSCompletionTriggerRowID;
        if (reservedCompletion) {
            self.searchMatches = @[];
            self.searchMessage = NSLocalizedString(@"This key is reserved for command completion.", @"");
        } else if (key.length == 0 || ![TSShortcutStore isAllowedKey:key modifiers:flags]) {
            self.searchMessage = self.searchMatches.count > 0
                ? NSLocalizedString(@"This key cannot be assigned to a new shortcut.", @"")
                : NSLocalizedString(@"This key cannot be used as a shortcut. Use Command or Control with a key, or F1–F20.", @"");
        } else {
            self.searchMessage = self.searchMatches.count == 0 ? NSLocalizedString(@"No command uses this key.", @"") : @"";
        }
    }
    self.hint.stringValue = self.searchMessage;
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
        NSView *row = [self rowWithIdentifier:completionRow inView:self.settingsHeader];
        if (row == nil) return;
        row.wantsLayer = YES; row.layer.cornerRadius = 4;
        row.layer.backgroundColor = [NSColor.controlAccentColor colorWithAlphaComponent:0.12].CGColor;
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
    for (NSButton *button in self.selectionButtons) { button.enabled = [self selectedCommand] != nil && ![self selectedCommand].managedBySystem; }
    self.macroButton.enabled = [self matchAtRow:self.table.selectedRow].macro != nil;
    [self updateStatus];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.searchingByKey && self.searchEvent != nil ? (NSInteger)self.searchMatches.count + ([self macroHeaderRow] >= 0 ? 1 : 0) : (NSInteger)self.functionRows.count;
}
- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row { return self.searchingByKey && row == [self macroHeaderRow]; }
- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row { return ![self tableView:tableView isGroupRow:row]; }
// Why a key-search match does not run for the searched key; nil for the match that runs.
- (NSString *)inactiveReasonForMatch:(TSShortcutMatch *)match {
    if (match == nil || match.winner) { return nil; }
    if (match.macro && ![TSShortcutStore isAllowedKey:match.macro.key modifiers:match.macro.modifiers])
        return [TSShortcutStore reasonForMacroConflict:@{@"refused":@YES}];
    for (TSShortcutMatch *owner in self.searchMatches) {
        if (!owner.winner) continue;
        TSShortcutBinding *ownerBinding = [self shownBindingForMatch:owner];
        NSString *ownerKey = ownerBinding.key;
        NSEventModifierFlags ownerFlags = ownerBinding.modifiers;
        TSShortcutCommand *ownerCommand = owner.command;
        return [NSString stringWithFormat:NSLocalizedString(@"This shortcut is inactive because it conflicts with “%@” (%@).", @""),
            owner.path, ownerCommand != nil ? [self.store displayKeyForCommand:ownerCommand] : [TSShortcutStore displayKey:ownerKey modifiers:ownerFlags]];
    }
    return NSLocalizedString(@"Inactive for this key", @"");
}
// Ordinary rows draw their text 2pt inside the cell; the warning row lines up with them.
static const CGFloat TSShortcutWarningIndent = 2, TSShortcutWarningGap = 2, TSShortcutWarningBottom = 4;
// The same warning line the settings window shows elsewhere: yellow triangle, small label-colored text.
- (NSStackView *)warningWithText:(NSString *)text { return TSShortcutWarningLine(text); }
- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    NSString *reason = self.searchingByKey && self.searchEvent != nil ? [self inactiveReasonForMatch:[self matchAtRow:row]] : nil;
    if (reason == nil) { return tableView.rowHeight; }
    NSStackView *warning = [self warningWithText:reason];
    NSTextField *note = (NSTextField *)warning.arrangedSubviews[1];
    NSTextField *path = [NSTextField labelWithString:@" "];
    // The command cell is as wide as its column; the note's frame adds its own alignment insets.
    NSEdgeInsets insets = note.alignmentRectInsets;
    CGFloat width = tableView.tableColumns.firstObject.width - TSShortcutWarningIndent
        - warning.arrangedSubviews[0].intrinsicContentSize.width - warning.spacing + insets.left + insets.right;
    CGFloat height = [note.cell cellSizeForBounds:NSMakeRect(0, 0, MAX(width, 1), CGFLOAT_MAX)].height;
    return ceil(path.intrinsicContentSize.height + TSShortcutWarningGap + height + TSShortcutWarningBottom + tableView.intercellSpacing.height);
}
- (void)tableViewColumnDidResize:(NSNotification *)notification {
    if (!self.searchingByKey || self.searchEvent == nil || self.table.numberOfRows == 0) { return; }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0;
        [self.table noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, (NSUInteger)self.table.numberOfRows)]];
    }];
}
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (self.searchingByKey && self.searchEvent != nil) {
        // Group rows span the table and arrive without a column.
        if (row == [self macroHeaderRow]) { return [NSTextField labelWithString:column == nil || [column.identifier isEqualToString:@"command"] ? NSLocalizedString(@"Macros", @"") : @""]; }
        TSShortcutMatch *match = [self matchAtRow:row];
        if (match == nil) { return nil; }
        TSShortcutBinding *shown = [self shownBindingForMatch:match];
        NSString *key = shown.key;
        NSEventModifierFlags flags = shown.modifiers;
        NSString *reason = [self inactiveReasonForMatch:match];
        BOOL isCommand = [column.identifier isEqualToString:@"command"];
        if (!isCommand && match.command != nil && match.command == self.editingCommand) { return self.recordingCell; }
        TSShortcutCommand *matchCommand = match.command;
        // The row that runs. A command or macro Settings can edit says Assigned. A command macOS
        // keeps, and a menu item with no command, says it cannot be changed.
        BOOL unchangeable = match.macro == nil && (match.command == nil || match.command.managedBySystem);
        NSString *status = unchangeable ? NSLocalizedString(@"Cannot Be Changed", @"") : NSLocalizedString(@"Assigned", @"");
        NSString *text = !isCommand ? (matchCommand != nil ? [self.store displayKeyForCommand:matchCommand] : [TSShortcutStore displayKey:key modifiers:flags])
            : reason == nil ? [match.path stringByAppendingFormat:@" — %@", status] : match.path;
        NSTextField *label = isCommand || match.command == nil || match.command.managedBySystem ? [NSTextField labelWithString:text] : [self shortcutLabel:text]; label.lineBreakMode = NSLineBreakByTruncatingMiddle; label.toolTip = text;
        if (unchangeable) label.textColor = NSColor.disabledControlTextColor;
        if (!isCommand || reason == nil) { return label; }
        NSView *cell = [NSView new]; cell.identifier = @"shortcut.inactive-command";
        NSStackView *warning = [self warningWithText:reason];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [label setContentCompressionResistancePriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [cell addSubview:label]; [cell addSubview:warning];
        [NSLayoutConstraint activateConstraints:@[
            [label.topAnchor constraintEqualToAnchor:cell.topAnchor],
            [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:TSShortcutWarningIndent],
            [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor],
            [warning.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:TSShortcutWarningGap],
            [warning.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:TSShortcutWarningIndent],
            [warning.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor]]];
        return cell;
    }
    TSShortcutFunctionRow *functionRow = [self functionRowAtIndex:row];
    if (functionRow == nil) { return nil; }
    TSShortcutCommand *command = functionRow.command;
    BOOL isCommand = [column.identifier isEqualToString:@"command"];
    // A menu item with no command is dimmed, like a command whose shortcut macOS keeps, and is not recorded.
    if (command == nil) {
        TSShortcutBinding *shown = functionRow.item != nil ? TSShownBinding(functionRow.item) : TSBinding(@"", 0);
        NSString *fixedText = isCommand ? functionRow.path : [TSShortcutStore displayKey:shown.key modifiers:shown.modifiers];
        NSTextField *fixed = [NSTextField labelWithString:fixedText];
        fixed.textColor = NSColor.disabledControlTextColor;
        fixed.lineBreakMode = NSLineBreakByTruncatingMiddle;
        fixed.toolTip = functionRow.path;
        return fixed;
    }
    if (!isCommand && command == self.editingCommand) { return self.recordingCell; }
    NSString *text = isCommand ? command.path : [self.store displayKeyForCommand:command];
    // A command whose shortcut macOS keeps is dimmed and not recorded, as alternates are in Xcode.
    NSTextField *label = isCommand || command.managedBySystem ? [NSTextField labelWithString:text] : [self shortcutLabel:text];
    if (command.managedBySystem) label.textColor = NSColor.disabledControlTextColor;
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    label.toolTip = command.path;
    return label;
}
// The key a search match shows: a command's as the store knows it, a macro's as the keyboard
// layout shows the key its file names, another item's as AppKit shows it.
- (TSShortcutBinding *)shownBindingForMatch:(TSShortcutMatch *)match {
    TSShortcutMacro *macro = match.macro;
    if (macro != nil) return [self.store shownBindingForGivenKey:macro.key modifiers:macro.modifiers];
    TSShortcutCommand *command = match.command;
    NSMenuItem *item = match.menuItem;
    if (command != nil) return [self.store shownBindingForCommand:command];
    return item != nil ? TSShownBinding(item) : TSBinding(@"", 0);
}
- (TSShortcutCommand *)selectedCommand {
    NSInteger row = self.table.selectedRow;
    if (self.searchingByKey && self.searchEvent != nil) { return [self matchAtRow:row].command; }
    return [self functionRowAtIndex:row].command;
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification { [self updateSelectionButtons]; }
- (void)showError:(NSString *)error {
    NSWindow *parent = self.window;
    if (error == nil || parent == nil || parent.attachedSheet != nil) { return; }
    NSAlert *alert = [NSAlert new]; alert.messageText = NSLocalizedString(@"Shortcut Unavailable", @""); alert.informativeText = error;
    [alert beginSheetModalForWindow:parent completionHandler:nil];
}
- (void)confirmMacrosUsingKey:(NSString *)key modifiers:(NSEventModifierFlags)flags completion:(void (^)(BOOL))completion {
    [self confirmMacrosUsingBindings:@[TSBinding(key, flags)] completion:completion];
}
- (NSArray<NSString *> *)macrosUsingBindings:(NSArray<TSShortcutBinding *> *)bindings {
    NSMutableOrderedSet *macros = [NSMutableOrderedSet orderedSet];
    TSShortcutStore *store = self.store;
    for (TSShortcutBinding *binding in bindings) [macros addObjectsFromArray:[store macrosUsingKey:binding.key modifiers:binding.modifiers] ?: @[]];
    return macros.array;
}
- (void)confirmMacrosUsingBindings:(NSArray<TSShortcutBinding *> *)bindings completion:(void (^)(BOOL))completion {
    NSArray *macros = [self macrosUsingBindings:bindings];
    if (!macros.count) { completion(YES); return; }
    NSWindow *parent = self.window;
    if (parent == nil || parent.attachedSheet != nil) { completion(NO); return; }
    NSAlert *alert = [NSAlert new];
    alert.messageText = NSLocalizedString(@"Assign a shortcut used by macros?", @"");
    alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"The following macros use this shortcut. Assigning it to the menu command will make their shortcuts inactive.\n\n%@", @""), [macros componentsJoinedByString:@"\n"]];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
    [alert addButtonWithTitle:NSLocalizedString(@"Assign", @"")];
    __weak typeof(self) weakSelf = self;
    [alert beginSheetModalForWindow:parent completionHandler:^(NSModalResponse response) {
        TSShortcutPaneController *strongSelf = weakSelf;
        if (strongSelf == nil) { return; }
        BOOL unchanged = [[strongSelf macrosUsingBindings:bindings] isEqualToArray:macros];
        completion(response == NSAlertSecondButtonReturn && unchanged);
    }];
}
- (void)removeShortcut:(id)sender {
    TSShortcutCommand *command = self.editingCommand ?: self.selectedCommand; if (!command || command.managedBySystem) return;
    [self endRecording];
    [self showError:[self.store setKey:@"" modifiers:0 forCommand:command]];
    [self refreshMenuAndMacros];
}
// A key is restored or recorded with the keys the current keyboard layout shows. Right after
// the layout changes they are worked out first, in the next pass of the run loop; when the
// layout changes again meanwhile, the restore or recording is dropped.
- (void)keyboardLayoutMayHaveChanged:(NSNotification *)notification {
    NSString *layout = TSKeyboardLayoutID();
    if ([layout isEqual:self.lastLayout]) return;
    self.lastLayout = layout; self.layoutChanges++;
}
- (BOOL)deferUntilLayoutKeys:(void (^)(void))action {
    if (self.runningAfterLayoutKeys || [self.store knowsKeysOfCurrentLayout]) return NO;
    [self keyboardLayoutMayHaveChanged:nil];
    NSUInteger changes = self.layoutChanges;
    __weak typeof(self) weakSelf = self;
    [self.store learnLayoutKeysThen:^(BOOL learned) {
        TSShortcutPaneController *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        [strongSelf keyboardLayoutMayHaveChanged:nil];
        if (strongSelf.layoutChanges != changes) return;
        strongSelf.runningAfterLayoutKeys = YES;
        action();
        strongSelf.runningAfterLayoutKeys = NO;
    }];
    return YES;
}
- (void)restoreShortcut:(id)sender {
    // The command selected when Restore was chosen; a different selection by then drops it.
    TSShortcutCommand *chosen = self.selectedCommand;
    __weak typeof(self) deferringSelf = self;
    if ([self deferUntilLayoutKeys:^{ if (deferringSelf.selectedCommand == chosen) [deferringSelf restoreShortcut:sender]; }]) return;
    [self endRecording];
    TSShortcutCommand *command = self.selectedCommand; if (!command || command.managedBySystem) return;
    // A yielding default disables no macro and is refused by no command: it gives way.
    if ([self.store commandYieldsDefault:command]) {
        [self showError:[self.store restoreCommand:command]];
        [self refreshMenuAndMacros];
        return;
    }
    NSString *error = [self.store conflictForRestoringCommand:command];
    if (error) { [self showError:[NSString stringWithFormat:NSLocalizedString(@"This shortcut is already used by “%@”.", @""), error]]; return; }
    __weak typeof(self) weakSelf = self;
    // The default as given and as this keyboard layout shows it.
    [self keyboardLayoutMayHaveChanged:nil];
    NSUInteger changes = self.layoutChanges;
    [self confirmMacrosUsingBindings:[self.store defaultBindingsForCommand:command].allObjects completion:^(BOOL accepted) {
        TSShortcutPaneController *strongSelf = weakSelf;
        if (strongSelf == nil || !accepted) { return; }
        // The default named in the question is the one of the layout then.
        [strongSelf keyboardLayoutMayHaveChanged:nil];
        if (strongSelf.layoutChanges != changes) { return; }
        [strongSelf showError:[strongSelf.store restoreCommand:command]];
        [strongSelf refreshMenuAndMacros];
    }];
}
- (void)restoreAll:(id)sender {
    __weak typeof(self) deferringSelf = self;
    if ([self deferUntilLayoutKeys:^{ [deferringSelf restoreAll:sender]; }]) return;
    [self endRecording];
    NSWindow *parent = self.window;
    if (parent == nil || parent.attachedSheet != nil) { return; }
    NSAlert *alert = [NSAlert new]; alert.messageText = NSLocalizedString(@"Restore all keyboard shortcuts?", @"");
    alert.informativeText = NSLocalizedString(@"Custom menu shortcuts will be removed.", @"");
    NSArray *macros = [self.store macrosAffectedByRestoringAll];
    if (macros.count) alert.informativeText = [alert.informativeText stringByAppendingFormat:@"\n\n%@\n%@",
        NSLocalizedString(@"These macro shortcuts will become inactive:", @""), [macros componentsJoinedByString:@"\n"]];
    [alert addButtonWithTitle:NSLocalizedString(@"Restore All", @"")].hasDestructiveAction = YES; [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
    __weak typeof(self) weakSelf = self;
    [alert beginSheetModalForWindow:parent completionHandler:^(NSModalResponse response) {
        TSShortcutPaneController *strongSelf = weakSelf;
        if (strongSelf == nil || response != NSAlertFirstButtonReturn) { return; }
        [strongSelf finishRestoringAllNaming:macros];
    }];
}
// The layout may change while the question is open: when restoring now makes a macro inactive
// that the question did not name, it is asked again.
- (void)finishRestoringAllNaming:(NSArray<NSString *> *)named {
    __weak typeof(self) deferringSelf = self;
    if ([self deferUntilLayoutKeys:^{ [deferringSelf finishRestoringAllNaming:named]; }]) return;
    TSShortcutStore *store = self.store;
    if (![[NSSet setWithArray:[store macrosAffectedByRestoringAll] ?: @[]] isSubsetOfSet:[NSSet setWithArray:named]]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [deferringSelf restoreAll:nil]; });
        return;
    }
    [self.store restoreAll]; [self refreshMenuAndMacros];
}
- (NSTextField *)shortcutLabel:(NSString *)text {
    TSShortcutKeyLabel *label = [TSShortcutKeyLabel labelWithString:text];
    __weak TSShortcutPaneController *weakSelf = self;
    label.press = ^(NSTextField *pressed) {
        TSShortcutPaneController *strongSelf = weakSelf;
        if (strongSelf != nil) { [strongSelf beginRecordingAtRow:[strongSelf.table rowForView:pressed]]; }
    };
    return label;
}
- (void)makeRecorder {
    TSShortcutRecordingCell *cell = [TSShortcutRecordingCell new];
    self.recorder = cell.recorder; self.recordingWarning = cell.warning;
    self.recorder.removeButton.target = self; self.recorder.removeButton.action = @selector(removeShortcut:);
    __weak TSShortcutPaneController *weakSelf = self;
    // A click elsewhere ends the recording and keeps the shortcut; the focus goes where it was going.
    self.recorder.resigned = ^{ [weakSelf finishRecordingFocusingList:NO]; };
    self.recordingCell = cell;
}
- (TSShortcutCommand *)commandAtRow:(NSInteger)row {
    if (self.searchingByKey && self.searchEvent != nil) { return [self matchAtRow:row].command; }
    return [self functionRowAtIndex:row].command;
}
- (NSInteger)rowForCommand:(TSShortcutCommand *)command {
    if (command == nil) { return -1; }
    for (NSInteger row = 0; row < self.table.numberOfRows; row++) { if ([self commandAtRow:row] == command) { return row; } }
    return -1;
}
- (void)reloadShortcutCellAtRow:(NSInteger)row {
    NSInteger column = [self.table columnWithIdentifier:@"shortcut"];
    if (row < 0 || row >= self.table.numberOfRows || column < 0) { return; }
    [self.table reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] columnIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)column]];
}
// The double action, and Return in the list.
- (void)editShortcut:(id)sender {
    NSInteger row = sender == self.table ? self.table.clickedRow : self.table.selectedRow;
    [self beginRecordingAtRow:row];
}
// A single click on the shortcut of the row that was already selected.
- (void)tableClicked:(id)sender {
    TSShortcutTableView *table = (TSShortcutTableView *)self.table;
    NSInteger row = table.clickedRow;
    if (row < 0 || row != table.rowSelectedAtMouseDown || table.clickedColumn != [table columnWithIdentifier:@"shortcut"]) { return; }
    [self beginRecordingAtRow:row];
}
- (void)beginRecordingAtRow:(NSInteger)row {
    TSShortcutCommand *command = [self commandAtRow:row];
    NSWindow *window = self.window;
    if (command == nil || command.managedBySystem || window == nil || window.attachedSheet != nil) { return; }
    if (self.editingCommand != command) {
        [self endRecording];
        // A row whose recording ended by a click elsewhere may still hold the field.
        NSInteger stale = [self.table rowForView:self.recordingCell];
        if (stale >= 0 && stale != row) { [self reloadShortcutCellAtRow:stale]; }
        if (self.table.selectedRow != row) { [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO]; }
        self.editingCommand = command; self.capturedKey = nil; self.capturedBindings = nil; self.capturedModifiers = 0; self.recordingError = nil;
        [self updateRecorder];
        [self reloadShortcutCellAtRow:row];
        [self.table scrollRowToVisible:row];
    }
    // The field is in the row before it takes the keys.
    NSInteger column = [self.table columnWithIdentifier:@"shortcut"];
    if (self.recorder.window != window && column >= 0) { [self.table viewAtColumn:column row:row makeIfNecessary:YES]; }
    if (self.recorder.window != window) { [self endRecording]; return; }
    [window makeFirstResponder:self.recorder];
    [self updateStatus];
}
// Ends recording and keeps the shortcut as it is now; the list takes the focus the recorder had.
- (void)endRecording { [self finishRecordingFocusingList:YES]; }
- (void)finishRecordingFocusingList:(BOOL)focusList {
    TSShortcutCommand *command = self.editingCommand;
    if (command == nil || self.endingRecording) { return; }
    self.endingRecording = YES;
    NSWindow *window = self.window;
    self.editingCommand = nil; self.capturedKey = nil; self.capturedBindings = nil; self.capturedModifiers = 0; self.recordingError = nil;
    if (focusList) {
        if (window != nil && window.firstResponder == self.recorder) { [window makeFirstResponder:self.table]; }
        [self reloadShortcutCellAtRow:[self rowForCommand:command]];
        [self.recordingCell removeFromSuperview];
    } else {
        // The recorder is resigning: the row shows its shortcut again once the focus has moved.
        __weak TSShortcutPaneController *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            TSShortcutPaneController *strongSelf = weakSelf;
            if (strongSelf == nil || strongSelf.editingCommand == command) { return; }
            [strongSelf reloadShortcutCellAtRow:[strongSelf rowForCommand:command]];
            if (strongSelf.editingCommand == nil) { [strongSelf.recordingCell removeFromSuperview]; }
        });
    }
    self.endingRecording = NO;
    [self updateStatus];
}
- (BOOL)isRecording { return self.editingCommand != nil; }
// Escape and Return end recording, Tab moves on, Delete removes the shortcut; any other key may become it.
- (BOOL)handleRecordingEvent:(NSEvent *)event {
    if (event.type != NSEventTypeKeyDown) return YES;
    NSString *key = event.charactersIgnoringModifiers;
    unichar c = key.length == 1 ? [key characterAtIndex:0] : 0;
    NSEventModifierFlags flags = event.modifierFlags & TSShortcutModifiers;
    if (!flags && (c == 27 || c == '\r' || c == 3)) { [self endRecording]; return YES; }
    if ((c == '\t' || c == 25) && !(flags & ~NSEventModifierFlagShift)) {
        NSWindow *window = self.window;
        [self endRecording];
        if (c == 25 || (flags & NSEventModifierFlagShift)) { [window selectPreviousKeyView:nil]; } else { [window selectNextKeyView:nil]; }
        return YES;
    }
    if (!flags && (c == 127 || c == 8 || c == NSDeleteFunctionKey)) { [self removeShortcut:nil]; return YES; }
    [self recordShortcutEvent:event];
    return YES;
}
- (void)updateRecorder {
    TSShortcutCommand *command = self.editingCommand;
    if (command == nil) { return; }
    // An empty field, as in Xcode, for a command without a shortcut (the list shows a dash).
    TSShortcutBinding *shown = [self.store shownBindingForCommand:command];
    NSString *current = shown.key.length ? [TSShortcutStore displayKey:shown.key modifiers:shown.modifiers] : @"";
    NSString *captured = self.capturedKey;
    self.recorder.shortcut = captured != nil ? [TSShortcutStore displayKey:captured modifiers:self.capturedModifiers] : current;
    self.recorder.removeButton.hidden = command.item.keyEquivalent.length == 0;
    self.recordingWarning.hidden = self.recordingError == nil;
}
// Keyboard Shortcuts opens from this anchor. App Shortcuts is a section inside that window and has no anchor:
// x-apple.systempreferences:...?applications stays on the Keyboard page. An unknown anchor does the same,
// so the guide names the sidebar item and the Keyboard Shortcuts button.
- (NSURL *)systemShortcutSettingsURL {
    return [NSURL URLWithString:@"x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts"];
}
- (NSTextField *)systemSettingsLinkField {
    NSFont *font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    NSString *title = NSLocalizedString(@"[Change in System Settings…]", @"");
    NSTextField *link = [NSTextField labelWithString:title];
    link.identifier = @"shortcut.system-settings";
    link.font = font;
    link.alignment = NSTextAlignmentCenter;
    link.selectable = YES;
    link.editable = NO;
    link.allowsEditingTextAttributes = YES;
    link.drawsBackground = NO;
    link.bordered = NO;
    link.hidden = YES;
    NSMutableAttributedString *styled = [link.attributedStringValue mutableCopy];
    NSRange whole = NSMakeRange(0, styled.length);
    [styled addAttribute:NSFontAttributeName value:font range:whole];
    // A foreground color would replace the link color. NSWorkspace opens this URL with no permission prompt.
    [styled removeAttribute:NSForegroundColorAttributeName range:whole];
    [styled addAttribute:NSLinkAttributeName value:[self systemShortcutSettingsURL] range:whole];
    [styled addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:whole];
    link.attributedStringValue = styled;
    return link;
}
- (NSTextField *)systemSettingsGuideField {
    NSTextField *guide = [NSTextField wrappingLabelWithString:NSLocalizedString(@"Choose “App Shortcuts” in the sidebar. If you are still on the Keyboard page, open “Keyboard Shortcuts…” first.", @"")];
    guide.identifier = @"shortcut.system-settings-guide";
    guide.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    guide.textColor = NSColor.secondaryLabelColor;
    guide.alignment = NSTextAlignmentCenter;
    guide.preferredMaxLayoutWidth = 640;
    guide.hidden = YES;
    [guide setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return guide;
}
- (void)viewDidLayout {
    [super viewDidLayout];
    if (self.systemSettingsGuide == nil || self.commandsView == nil) { return; }
    CGFloat width = NSWidth(self.commandsView.bounds) - 24;
    if (width > 80 && fabs(self.systemSettingsGuide.preferredMaxLayoutWidth - width) > 0.5)
        self.systemSettingsGuide.preferredMaxLayoutWidth = width;
}
// The line under the list: why a recorded key was refused, that a gray row of the function list cannot
// be changed, or otherwise the selected command's default.
- (void)updateStatus {
    if (self.statusText == nil) { return; }
    NSString *error = self.editingCommand != nil ? self.recordingError : nil;
    TSShortcutCommand *command = self.editingCommand ?: [self selectedCommand];
    NSString *text = error;
    if (text == nil && self.editingCommand == nil && [self selectedFunctionRowCannotChange])
        text = NSLocalizedString(@"Cannot Be Changed", @"");
    if (text == nil && command != nil) {
        TSShortcutBinding *shownDefault = [self.store shownDefaultForCommand:command];
        text = shownDefault.key.length == 0 ? NSLocalizedString(@"Default shortcut: None", @"")
            : [NSString stringWithFormat:NSLocalizedString(@"Default shortcut: %@", @""), [self.store displayDefaultKeyForCommand:command]];
    }
    // A blank line keeps the list and the buttons where they are.
    self.statusText.stringValue = text.length ? text : @" ";
    self.status.arrangedSubviews[0].hidden = error == nil;
    BOOL showSystemSettings = self.systemSettingsLink != nil && error == nil && self.editingCommand == nil && [self selectedFunctionRowCannotChange];
    self.systemSettingsLink.hidden = !showSystemSettings;
    self.systemSettingsGuide.hidden = !showSystemSettings;
}
- (void)showRecordingError:(NSString *)error {
    self.recordingError = error;
    [self updateRecorder];
    [self updateStatus];
    NSWindow *window = self.window;
    if (window.isKeyWindow) {
        NSAccessibilityPostNotificationWithUserInfo(self.recorder, NSAccessibilityAnnouncementRequestedNotification,
            @{NSAccessibilityAnnouncementKey: error, NSAccessibilityPriorityKey: @(NSAccessibilityPriorityHigh)});
    }
}
// Reads a key press as a shortcut; NO, with the reason under the list, for a key that cannot be one.
- (BOOL)captureShortcutEvent:(NSEvent *)event {
    NSString *key = TSShortcutCharacterForEvent(event);
    NSEventModifierFlags flags = event.modifierFlags & TSShortcutModifiers;
    NSString *globe = TSGlobeRecordingRefusal(event);
    if (globe != nil) {
        self.capturedKey = nil; self.capturedBindings = nil; self.capturedModifiers = 0;
        [self showRecordingError:globe];
        return NO;
    }
    if (key.length == 0 || ![TSShortcutStore isAllowedKey:key modifiers:flags]) {
        self.capturedKey = nil; self.capturedBindings = nil; self.capturedModifiers = 0;
        [self showRecordingError:NSLocalizedString(@"This key cannot be used as a shortcut. Use Command or Control with a key, or F1–F20.", @"")];
        return NO;
    }
    self.capturedBindings = TSEventBindings(event, [event charactersByApplyingModifiers:0]);
    TSShortcutBinding *binding = self.capturedBindings.firstObject;
    self.capturedKey = binding.key; self.capturedModifiers = binding.modifiers;
    self.recordingError = nil;
    [self updateRecorder];
    return YES;
}
// A key pressed while recording becomes the shortcut at once when it can.
- (void)recordShortcutEvent:(NSEvent *)event {
    if ([self captureShortcutEvent:event]) { [self applyCapturedShortcut:nil]; }
}
- (NSString *)conflictForCapturedShortcut {
    NSArray<TSShortcutBinding *> *bindings = self.capturedBindings ?: @[TSBinding(self.capturedKey, self.capturedModifiers)];
    NSMutableOrderedSet *conflicts = [NSMutableOrderedSet orderedSet];
    for (TSShortcutBinding *binding in bindings) {
        NSString *path = [self.store conflictForKey:binding.key modifiers:binding.modifiers
            except:self.editingCommand.item restoring:nil];
        if (path) [conflicts addObject:path];
    }
    if (!conflicts.count) return nil;
    if (conflicts.count == 1)
        return [NSString stringWithFormat:NSLocalizedString(@"This shortcut is already used by “%@”.", @""), conflicts.firstObject];
    return [NSString stringWithFormat:NSLocalizedString(@"This shortcut is already used by:\n%@", @""),
        [conflicts.array componentsJoinedByString:@"\n"]];
}
// A key in use by another command is refused and recording goes on; a key that
// macros use is assigned after the confirmation.
- (void)applyCapturedShortcut:(id)sender {
    // The key recorded for the command being edited; another command or key by then drops it.
    TSShortcutCommand *recording = self.editingCommand;
    NSString *recordedKey = self.capturedKey;
    NSEventModifierFlags recordedFlags = self.capturedModifiers;
    __weak typeof(self) deferringSelf = self;
    if ([self deferUntilLayoutKeys:^{
        TSShortcutPaneController *pane = deferringSelf;
        if (pane.editingCommand == recording && [pane.capturedKey isEqual:recordedKey] && pane.capturedModifiers == recordedFlags) [pane applyCapturedShortcut:sender];
    }]) return;
    NSString *key = self.capturedKey;
    TSShortcutCommand *command = self.editingCommand;
    NSEventModifierFlags flags = self.capturedModifiers;
    if (key == nil || command == nil) { return; }
    NSString *conflict = [self conflictForCapturedShortcut];
    if (conflict != nil) { [self showRecordingError:conflict]; return; }
    self.recordingError = nil; [self updateRecorder]; [self updateStatus];
    // The yielding default of Edit › Complete Label or Citation Key is refused while a macro
    // has it, rather than taken from the macro after a confirmation.
    if ([self.store commandYieldsDefault:command] && [key isEqualToString:command.defaultKey] && flags == command.defaultModifiers) {
        NSString *error = [self.store setKey:key modifiers:flags forCommand:command];
        if (error == nil) { [self endRecording]; [self refreshMenuAndMacros]; return; }
        [self showRecordingError:error];
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.confirmingRecording = YES;
    // A key is recorded with the keys of the layout it was typed on: when the layout changes
    // while the question is open, nothing is recorded.
    [self keyboardLayoutMayHaveChanged:nil];
    NSUInteger changes = self.layoutChanges;
    [self confirmMacrosUsingKey:key modifiers:flags completion:^(BOOL accepted) {
        TSShortcutPaneController *strongSelf = weakSelf;
        if (strongSelf == nil) { return; }
        strongSelf.confirmingRecording = NO;
        if (strongSelf.editingCommand != command || ![strongSelf.capturedKey isEqualToString:key] || strongSelf.capturedModifiers != flags) { return; }
        [strongSelf keyboardLayoutMayHaveChanged:nil];
        if (!accepted || strongSelf.layoutChanges != changes) { [strongSelf endRecording]; return; }
        NSString *error = [strongSelf conflictForCapturedShortcut];
        if (error != nil) { [strongSelf showRecordingError:error]; return; }
        error = [strongSelf.store setKey:key modifiers:flags forCommand:command];
        if (error == nil) { [strongSelf endRecording]; }
        [strongSelf refreshMenuAndMacros];
        if (error == nil) { return; }
        if (strongSelf.editingCommand == command) { [strongSelf showRecordingError:error]; } else { [strongSelf showError:error]; }
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
    [self.view layoutSubtreeIfNeeded];
}
@end
