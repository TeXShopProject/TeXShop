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
@property (strong) NSTabView *legacyTabs;
@property (strong) NSView *legacyContent;
@property BOOL synchronizingSelection;
@end
@implementation TSSettingsWindow
- (BOOL)performKeyEquivalent:(NSEvent *)event
{
    if (self.settingsController != nil && self.isKeyWindow && (event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagControl | NSEventModifierFlagOption)) == NSEventModifierFlagCommand) {
        NSString *key = event.charactersIgnoringModifiers;
        if ([key isEqualToString:@"["]) { [self.settingsController goBack:self]; return YES; }
        if ([key isEqualToString:@"]"]) { [self.settingsController goForward:self]; return YES; }
    }
    return [super performKeyEquivalent:event];
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
- (NSNibName)windowNibName { return @"SettingsWindow"; }
- (void)windowDidLoad
{
    [super windowDidLoad];
    NSWindow *window = self.window;
    if (window == nil) return;
    ((TSSettingsWindow *)window).settingsController = self;
    window.releasedWhenClosed = NO;
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
    [NSLayoutConstraint activateConstraints:@[
        [self.contentScroll.leadingAnchor constraintEqualToAnchor:content.view.leadingAnchor],
        [self.contentScroll.trailingAnchor constraintEqualToAnchor:content.view.trailingAnchor],
        [self.contentScroll.topAnchor constraintEqualToAnchor:content.view.safeAreaLayoutGuide.topAnchor],
        [self.contentScroll.bottomAnchor constraintEqualToAnchor:content.view.bottomAnchor]]];
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
- (void)hostLegacyContent:(NSView *)content tabView:(NSTabView *)tabs
{
    (void)self.window;
    self.legacyContent = content;
    self.legacyTabs = tabs;
    [content removeFromSuperview];
    content.translatesAutoresizingMaskIntoConstraints = YES;
    content.autoresizingMask = NSViewNotSizable;
    // Removing the tab strip must not resize the old fixed-layout panes.
    NSRect paneFrame = [tabs convertRect:tabs.contentRect toView:content];
    NSMutableArray<NSView *> *views = [NSMutableArray array];
    NSMutableArray<NSValue *> *frames = [NSMutableArray array];
    for (NSTabViewItem *item in tabs.tabViewItems) {
        NSMutableArray<NSView *> *pending = [NSMutableArray arrayWithArray:item.view.subviews ?: @[]];
        while (pending.count > 0) {
            NSView *view = pending.firstObject;
            if (view == nil) { break; }
            [pending removeObjectAtIndex:0];
            [views addObject:view]; [frames addObject:[NSValue valueWithRect:view.frame]];
            [pending addObjectsFromArray:view.subviews];
        }
    }
    tabs.tabViewType = NSNoTabsNoBorder;
    tabs.translatesAutoresizingMaskIntoConstraints = YES;
    tabs.autoresizingMask = NSViewNotSizable;
    tabs.frame = paneFrame;
    for (NSUInteger index = 0; index < views.count; index++) views[index].frame = frames[index].rectValue;
    self.contentScroll.documentView = [[TSSettingsContentView alloc] initWithContent:content];
    self.synchronizingSelection = YES;
    [self.categoryTable reloadData];
    self.synchronizingSelection = NO;
    // Set the initial size after hosting; restore the user frame only after all layout setup.
    NSWindow *window = self.window;
    if (window == nil) { return; }
    CGFloat chrome = NSHeight(window.contentView.bounds) - NSHeight(window.contentLayoutRect);
    NSSize wanted = NSMakeSize(MAX(960, NSWidth(content.frame) + 220), NSHeight(content.frame) + chrome);
    NSScreen *screen = window.screen ?: NSScreen.mainScreen;
    if (screen != nil) {
        wanted.width = MIN(wanted.width, NSWidth(screen.visibleFrame));
        wanted.height = MIN(wanted.height, NSHeight(screen.visibleFrame) - 28);
    }
    [window setContentSize:wanted];
    [window setFrameAutosaveName:@"SettingsSidebarWindow"];
    window.initialFirstResponder = self.categoryTable;
    [self.window recalculateKeyViewLoop];
}
- (NSView *)legacyViewForCategoryIdentifier:(NSString *)identifier
{
    TSSettingsCategory *category = [self.categoryList categoryForIdentifier:identifier];
    if (category == nil) { return nil; }
    NSUInteger index = category.legacyIndex;
    if (index >= (NSUInteger)self.legacyTabs.numberOfTabViewItems) return nil;
    return [self.legacyTabs tabViewItemAtIndex:index].view;
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
    if (index == NSNotFound || index >= (NSUInteger)self.legacyTabs.numberOfTabViewItems) return;
    TSSettingsCategory *category = [self.categoryList categoryForIdentifier:identifier];
    if (category == nil || category.legacyIndex >= (NSUInteger)self.legacyTabs.numberOfTabViewItems) { return; }
    NSUInteger legacyIndex = category.legacyIndex;
    // Input has already been validated. Avoid repeating the legacy delegate path.
    id<NSTabViewDelegate> delegate = self.legacyTabs.delegate;
    self.legacyTabs.delegate = nil;
    [self.legacyTabs selectTabViewItemAtIndex:legacyIndex];
    self.legacyTabs.delegate = delegate;
    [self synchronizeSidebarSelection];
    self.window.title = [self.legacyTabs tabViewItemAtIndex:legacyIndex].label;
    [self.legacyContent setAccessibilityLabel:self.window.title];
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
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.legacyTabs.numberOfTabViewItems; }
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
    if (row < 0 || row >= (NSInteger)self.categoryList.categories.count || row >= self.legacyTabs.numberOfTabViewItems) { return nil; }
    TSSettingsCategory *category = self.categoryList.categories[(NSUInteger)row];
    if (category.legacyIndex >= (NSUInteger)self.legacyTabs.numberOfTabViewItems) { return nil; }
    return [TSSettingsSidebarRow cellForCategory:category title:[self.legacyTabs tabViewItemAtIndex:category.legacyIndex].label];
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
