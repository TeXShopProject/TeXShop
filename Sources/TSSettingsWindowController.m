// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsWindowController.h"
#import "TSSettingsCategoryList.h"
#import "TSSettingsStateStore.h"
#import "TSSettingsSidebarRow.h"
#import "TSSettingsContentView.h"
static NSToolbarItemIdentifier const TSSettingsDivider = @"settings.divider";
static NSToolbarItemIdentifier const TSSettingsNavigation = @"settings.navigation";

@interface TSSettingsWindowController () <NSTableViewDataSource, NSTableViewDelegate, NSToolbarDelegate>
@property (strong) TSSettingsCategoryList *categoryList;
@property (strong) TSSettingsStateStore *stateStore;
@property (strong, readwrite) TSSettingsNavigationHistory *history;
@property (copy, readwrite) NSArray<TSSettingsCategoryID> *categoryIdentifiers;
@property (strong, readwrite) NSTableView *categoryTable;
@property (strong, readwrite) NSSegmentedControl *navigationControl;
@property (strong) NSSplitViewController *splitController;
@property (strong) NSScrollView *contentScroll;
@property (copy) NSDictionary<TSSettingsCategoryID, NSViewController *> *panes;
@property (strong) NSLayoutConstraint *contentBottom;
@property BOOL synchronizingSelection;
@property (strong, nullable) NSViewController<TSSettingsKeyboardPane> *keyboardPane;
@property (strong, nullable) NSScrollView *keyboardScroll;
- (BOOL)handleKeySearchEvent:(NSEvent *)event;
@end
@implementation TSSettingsWindow
- (void)sendEvent:(NSEvent *)event
{
    // Keep recording consistent after clicking a result row. Capture ordinary
    // characters and arrows before the table performs type selection/navigation.
    if (event.type == NSEventTypeKeyDown && self.isKeyWindow && self.attachedSheet == nil &&
        [self.settingsController handleKeySearchEvent:event]) return;
    [super sendEvent:event];
}
- (BOOL)performKeyEquivalent:(NSEvent *)event
{
    TSSettingsWindowController *controller = self.settingsController;
    if (controller != nil && self.isKeyWindow && self.attachedSheet == nil) {
        if ([controller handleKeySearchEvent:event]) { return YES; }
        NSEventModifierFlags flags = event.modifierFlags;
        if ((flags & NSEventModifierFlagCommand) && !(flags & NSEventModifierFlagControl)) {
            NSString *key = (flags & NSEventModifierFlagOption) ? [event charactersByApplyingModifiers:flags & (NSEventModifierFlagOption | NSEventModifierFlagShift)] : event.charactersIgnoringModifiers;
            if ([key isEqualToString:@"["]) { [controller goBack:self]; return YES; }
            if ([key isEqualToString:@"]"]) { [controller goForward:self]; return YES; }
        }
    }
    return [super performKeyEquivalent:event];
}
- (void)keyDown:(NSEvent *)event
{
    TSSettingsWindowController *controller = self.settingsController;
    if (self.isKeyWindow && controller != nil && [controller handleKeySearchEvent:event]) { return; }
    [super keyDown:event];
}
@end
@implementation TSSettingsWindowController
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
{
    self = [super initWithWindow:nil];
    if (self == nil) return nil;
    _stateStore = [[TSSettingsStateStore alloc] initWithDefaults:defaults];
    _categoryList = [TSSettingsCategoryList standardList];
    self.shouldCascadeWindows = NO;
    _history = [TSSettingsNavigationHistory new];
    _categoryIdentifiers = _categoryList.identifiers;
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)windowResignedKey:(NSNotification *)notification { if (self.keyboardPane != nil) { [self.keyboardPane stopKeySearch]; } }
- (BOOL)handleKeySearchEvent:(NSEvent *)event {
    if (![self.history.currentIdentifier isEqualToString:TSSettingsCategoryKeyboard] || self.keyboardPane == nil) { return NO; }
    return [self.keyboardPane handleKeySearchEvent:event];
}
- (NSNibName)windowNibName { return @"SettingsWindow"; }
- (void)windowDidLoad
{
    [super windowDidLoad];
    NSWindow *window = self.window;
    if (window == nil) return;
    ((TSSettingsWindow *)window).settingsController = self;
    window.releasedWhenClosed = NO;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowResignedKey:) name:NSWindowDidResignKeyNotification object:window];
    window.toolbarStyle = NSWindowToolbarStyleUnified;
    window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleAutomatic;
    window.contentMinSize = NSMakeSize(660, 440);
    self.splitController = [NSSplitViewController new];
    NSViewController *sidebar = [NSViewController new];
    sidebar.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 220, 600)];
    NSScrollView *listScroll = [NSScrollView new];
    listScroll.translatesAutoresizingMaskIntoConstraints = NO;
    listScroll.drawsBackground = NO;
    listScroll.hasVerticalScroller = YES;
    self.categoryTable = [[NSTableView alloc] initWithFrame:sidebar.view.bounds];
    self.categoryTable.style = NSTableViewStyleSourceList;
    self.categoryTable.headerView = nil;
    self.categoryTable.rowHeight = 50;
    self.categoryTable.allowsEmptySelection = NO;
    self.categoryTable.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
    self.categoryTable.dataSource = self;
    self.categoryTable.delegate = self;
    [self.categoryTable setAccessibilityLabel:NSLocalizedString(@"Settings Categories", @"")];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"category"];
    column.width = 210;
    [self.categoryTable addTableColumn:column];
    listScroll.documentView = self.categoryTable;
    [sidebar.view addSubview:listScroll];
    [NSLayoutConstraint activateConstraints:@[
        [listScroll.leadingAnchor constraintEqualToAnchor:sidebar.view.leadingAnchor],
        [listScroll.trailingAnchor constraintEqualToAnchor:sidebar.view.trailingAnchor],
        [listScroll.topAnchor constraintEqualToAnchor:sidebar.view.safeAreaLayoutGuide.topAnchor],
        [listScroll.bottomAnchor constraintEqualToAnchor:sidebar.view.bottomAnchor]]];
    NSSplitViewItem *sidebarItem = [NSSplitViewItem sidebarWithViewController:sidebar];
    sidebarItem.minimumThickness = 190;
    sidebarItem.maximumThickness = 330;
    sidebarItem.canCollapse = NO;
    [self.splitController addSplitViewItem:sidebarItem];
    NSViewController *content = [NSViewController new];
    content.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 700, 600)];
    self.contentScroll = [NSScrollView new];
    self.contentScroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentScroll.hasHorizontalScroller = YES;
    self.contentScroll.hasVerticalScroller = YES;
    self.contentScroll.autohidesScrollers = YES;
    self.contentScroll.drawsBackground = NO;
    [content.view addSubview:self.contentScroll];
    self.contentBottom = [self.contentScroll.bottomAnchor constraintEqualToAnchor:content.view.bottomAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [self.contentScroll.leadingAnchor constraintEqualToAnchor:content.view.leadingAnchor],
        [self.contentScroll.trailingAnchor constraintEqualToAnchor:content.view.trailingAnchor],
        [self.contentScroll.topAnchor constraintEqualToAnchor:content.view.safeAreaLayoutGuide.topAnchor],
        self.contentBottom]];
    [self.splitController addSplitViewItem:[NSSplitViewItem splitViewItemWithViewController:content]];
    window.contentViewController = self.splitController;
    NSImage *backImage = [NSImage imageWithSystemSymbolName:@"chevron.left" accessibilityDescription:NSLocalizedString(@"Back", @"")];
    NSImage *forwardImage = [NSImage imageWithSystemSymbolName:@"chevron.right" accessibilityDescription:NSLocalizedString(@"Forward", @"")];
    if (backImage == nil || forwardImage == nil) { return; }
    self.navigationControl = [NSSegmentedControl segmentedControlWithImages:@[backImage, forwardImage]
        trackingMode:NSSegmentSwitchTrackingMomentary target:self action:@selector(navigate:)];
    [self.navigationControl setToolTip:NSLocalizedString(@"Back (⌘[)", @"") forSegment:0];
    [self.navigationControl setToolTip:NSLocalizedString(@"Forward (⌘])", @"") forSegment:1];
    [self.navigationControl setAccessibilityLabel:NSLocalizedString(@"Navigation History", @"")];
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"SettingsSidebarToolbar"];
    toolbar.delegate = self;
    toolbar.allowsUserCustomization = NO;
    window.toolbar = toolbar;
}
- (void)hostPaneControllers:(NSDictionary<TSSettingsCategoryID, NSViewController *> *)panes footer:(NSView *)footer
{
    (void)self.window;
    self.panes = panes;
    NSView *parent = self.contentScroll.superview;
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [parent addSubview:footer];
    self.contentBottom.active = NO;
    [NSLayoutConstraint activateConstraints:@[
        [footer.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor],
        [footer.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor],
        [footer.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor],
        [self.contentScroll.bottomAnchor constraintEqualToAnchor:footer.topAnchor]]];
    self.synchronizingSelection = YES;
    [self.categoryTable reloadData];
    self.synchronizingSelection = NO;
    NSWindow *window = self.window;
    NSSize wanted = NSMakeSize(960, 700);
    NSScreen *screen = window.screen ?: NSScreen.mainScreen;
    if (screen != nil) {
        wanted.width = MIN(wanted.width, NSWidth(screen.visibleFrame));
        wanted.height = MIN(wanted.height, NSHeight(screen.visibleFrame) - 28);
    }
    [window setContentSize:wanted];
    [window setFrameAutosaveName:@"SettingsSidebarWindow"];
    window.initialFirstResponder = self.categoryTable;
    [window recalculateKeyViewLoop];
}
- (NSView *)viewForCategoryIdentifier:(NSString *)identifier
{
    return self.panes[identifier].view;
}
- (void)displayPane:(NSView *)pane
{
    TSSettingsContentView *document = [[TSSettingsContentView alloc] initWithContent:pane];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentScroll.documentView = document;
    NSLayoutConstraint *width = [document.widthAnchor constraintEqualToAnchor:self.contentScroll.contentView.widthAnchor];
    width.priority = NSLayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        width, [document.widthAnchor constraintGreaterThanOrEqualToConstant:620],
        [pane.leadingAnchor constraintEqualToAnchor:document.leadingAnchor],
        [pane.trailingAnchor constraintEqualToAnchor:document.trailingAnchor],
        [pane.topAnchor constraintEqualToAnchor:document.topAnchor],
        [pane.bottomAnchor constraintEqualToAnchor:document.bottomAnchor]]];
}
- (void)beginSession
{
    TSSettingsCategoryID identifier = [self.stateStore selectedCategoryInIdentifiers:self.categoryIdentifiers];
    [self.history resetWithIdentifier:identifier];
    [self displayCurrentCategory];
    [self.window makeFirstResponder:self.categoryTable];
}
- (void)endSession
{
    if (self.keyboardPane != nil) { [self.keyboardPane stopKeySearch]; }
    [self.history resetWithIdentifier:self.history.currentIdentifier ?: TSSettingsCategorySource];
    [self updateNavigation];
}
- (BOOL)selectCategoryIdentifier:(NSString *)identifier
{
    if (![self.categoryIdentifiers containsObject:identifier]) return NO;
    if ([identifier isEqual:self.history.currentIdentifier]) return YES;
    if (self.window.attachedSheet != nil || ![self mayChangeCategory]) return NO;
    [self.history visitIdentifier:identifier];
    [self displayCurrentCategory];
    return YES;
}
- (void)goBack:(id)sender
{
    if (self.history.backIdentifier == nil || self.window.attachedSheet != nil || ![self mayChangeCategory]) return;
    [self.history goBack]; [self displayCurrentCategory];
}
- (void)goForward:(id)sender
{
    if (self.history.forwardIdentifier == nil || self.window.attachedSheet != nil || ![self mayChangeCategory]) return;
    [self.history goForward]; [self displayCurrentCategory];
}
- (void)navigate:(NSSegmentedControl *)sender
{
    if (sender.selectedSegment == 0) [self goBack:sender]; else [self goForward:sender];
}
- (void)displayCurrentCategory
{
    TSSettingsCategoryID identifier = self.history.currentIdentifier;
    if (identifier == nil) { return; }
    NSUInteger index = [self.categoryIdentifiers indexOfObject:identifier];
    if (index == NSNotFound) { return; }
    TSSettingsCategory *category = [self.categoryList categoryForIdentifier:identifier];
    if (category == nil) { return; }
    if (self.keyboardPane != nil) { [self.keyboardPane stopKeySearch]; }
    BOOL keyboard = [identifier isEqualToString:TSSettingsCategoryKeyboard];
    if (keyboard && self.keyboardPane == nil && self.keyboardPaneProvider != nil) {
        self.keyboardPane = self.keyboardPaneProvider();
        NSView *parent = self.contentScroll.superview;
        NSViewController<TSSettingsKeyboardPane> *controller = self.keyboardPane;
        NSView *pane = controller != nil ? controller.view : nil;
        if (parent != nil && pane != nil) {
            NSScrollView *scroll = [NSScrollView new];
            scroll.translatesAutoresizingMaskIntoConstraints = NO;
            scroll.hasVerticalScroller = NO; scroll.hasHorizontalScroller = YES;
            scroll.autohidesScrollers = YES;
            self.keyboardScroll = scroll;
            TSSettingsContentView *document = [[TSSettingsContentView alloc] initWithContent:pane];
            document.translatesAutoresizingMaskIntoConstraints = NO;
            pane.translatesAutoresizingMaskIntoConstraints = NO;
            scroll.documentView = document;
            [parent addSubview:scroll];
            NSLayoutConstraint *width = [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor];
            NSLayoutConstraint *height = [document.heightAnchor constraintEqualToAnchor:scroll.contentView.heightAnchor];
            width.priority = NSLayoutPriorityDefaultHigh;
            [NSLayoutConstraint activateConstraints:@[
                [scroll.leadingAnchor constraintEqualToAnchor:self.contentScroll.leadingAnchor],
                [scroll.trailingAnchor constraintEqualToAnchor:self.contentScroll.trailingAnchor],
                [scroll.topAnchor constraintEqualToAnchor:self.contentScroll.topAnchor],
                [scroll.bottomAnchor constraintEqualToAnchor:self.contentScroll.bottomAnchor],
                [document.widthAnchor constraintGreaterThanOrEqualToConstant:700],
                width, height,
                [pane.leadingAnchor constraintEqualToAnchor:document.leadingAnchor],
                [pane.trailingAnchor constraintEqualToAnchor:document.trailingAnchor],
                [pane.topAnchor constraintEqualToAnchor:document.topAnchor],
                [pane.bottomAnchor constraintEqualToAnchor:document.bottomAnchor]]];
        }
    }
    self.contentScroll.hidden = keyboard;
    if (self.keyboardScroll != nil) { self.keyboardScroll.hidden = !keyboard; }
    if (keyboard) {
        self.window.title = NSLocalizedString(@"Keyboard", @"");
    } else {
        NSViewController *pane = self.panes[identifier];
        if (pane == nil) { return; }
        [self displayPane:pane.view];
        self.window.title = pane.title ?: @"";
    }
    [self synchronizeSidebarSelection];
    [self.contentScroll.documentView setAccessibilityLabel:self.window.title];
    [self.stateStore saveSelectedCategory:identifier];
    [self.contentScroll.contentView scrollToPoint:NSZeroPoint];
    [self.contentScroll reflectScrolledClipView:self.contentScroll.contentView];
    [self.window recalculateKeyViewLoop];
    [self updateNavigation];
}
- (void)synchronizeSidebarSelection
{
    TSSettingsCategoryID identifier = self.history.currentIdentifier;
    if (identifier == nil) { return; }
    NSUInteger index = [self.categoryIdentifiers indexOfObject:identifier];
    if (index == NSNotFound) { return; }
    self.synchronizingSelection = YES;
    [self.categoryTable selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
    self.synchronizingSelection = NO;
}
- (void)updateNavigation
{
    [self.navigationControl setEnabled:self.history.backIdentifier != nil forSegment:0];
    [self.navigationControl setEnabled:self.history.forwardIdentifier != nil forSegment:1];
}
- (BOOL)mayChangeCategory
{
    id<TSSettingsWindowDelegate> delegate = self.settingsDelegate;
    if (delegate == nil) { return NO; }
    BOOL sidebarHadFocus = self.window.firstResponder == self.categoryTable;
    BOOL allowed = [delegate settingsMayChangeCategory];
    // Committing fields clears the first responder. Preserve keyboard navigation
    // only after successful validation; an invalid field keeps its focus.
    if (allowed && sidebarHadFocus) { [self.window makeFirstResponder:self.categoryTable]; }
    return allowed;
}
- (void)changeFont:(id)sender
{
    id<TSSettingsWindowDelegate> delegate = self.settingsDelegate;
    if (delegate == nil || sender == nil) { return; }
    [delegate settingsChangeFont:(NSFontManager *)sender];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.categoryList.categories.count; }
- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
    return row >= 0 && row < (NSInteger)self.categoryIdentifiers.count;
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    if (self.synchronizingSelection || self.history.currentIdentifier == nil) { return; }
    NSInteger row = self.categoryTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.categoryIdentifiers.count) { return; }
    if (![self selectCategoryIdentifier:self.categoryIdentifiers[(NSUInteger)row]]) { [self synchronizeSidebarSelection]; }
}
- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    if (row < 0 || row >= (NSInteger)self.categoryList.categories.count) { return 50; }
    return self.categoryList.categories[(NSUInteger)row].startsGroup ? 62 : 50;
}
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    if (row < 0 || row >= (NSInteger)self.categoryList.categories.count) { return nil; }
    TSSettingsCategory *category = self.categoryList.categories[(NSUInteger)row];
    if ([category.identifier isEqualToString:TSSettingsCategoryKeyboard]) { return [TSSettingsSidebarRow cellForCategory:category title:NSLocalizedString(@"Keyboard", @"")]; }
    NSViewController *pane = self.panes[category.identifier];
    if (pane == nil) { return nil; }
    return [TSSettingsSidebarRow cellForCategory:category title:pane.title ?: @""];
}
- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar { return @[TSSettingsDivider,TSSettingsNavigation]; }
- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar { return @[TSSettingsDivider,TSSettingsNavigation]; }
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier willBeInsertedIntoToolbar:(BOOL)flag
{
    if ([identifier isEqualToString:TSSettingsDivider])
        return [NSTrackingSeparatorToolbarItem trackingSeparatorToolbarItemWithIdentifier:identifier splitView:self.splitController.splitView dividerIndex:0];
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.view = self.navigationControl;
    item.navigational = YES;
    item.label = NSLocalizedString(@"Navigation History", @"");
    return item;
}
@end
