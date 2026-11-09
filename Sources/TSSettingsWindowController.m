// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsWindowController.h"
#import "TSSettingsCategoryList.h"
#import "TSSettingsStateStore.h"
#import "TSSettingsSidebarRow.h"
#import "TSSettingsContentView.h"
static NSToolbarItemIdentifier const TSSettingsDivider = @"settings.divider";
static NSToolbarItemIdentifier const TSSettingsNavigation = @"settings.navigation";

@interface TSSettingsSearchHighlight : NSView
@end
@implementation TSSettingsSearchHighlight
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (BOOL)isAccessibilityElement { return NO; }
- (void)drawRect:(NSRect)dirtyRect {
    [NSColor.controlAccentColor setStroke];
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 1) xRadius:5 yRadius:5];
    path.lineWidth = 2; [path stroke];
}
@end
static void TSCollectSearchTargets(NSView *view, NSSet<NSString *> *targets, NSMutableArray<NSView *> *matches) {
    NSString *identifier = view.identifier;
    if (identifier != nil && [targets containsObject:identifier]) { [matches addObject:view]; return; }
    for (NSView *child in view.subviews) TSCollectSearchTargets(child, targets, matches);
}

@interface TSSettingsWindowController () <NSTableViewDataSource, NSTableViewDelegate, NSToolbarDelegate, NSSearchFieldDelegate>
@property (strong) TSSettingsCategoryList *categoryList;
@property (strong) NSSearchField *settingsSearchField;
@property (strong, nullable) TSSettingsSearch *categoryTextIndex;
@property (strong) NSTextField *searchStatus;
@property (strong) NSLayoutConstraint *emptySearchStatusHeight;
@property (copy, readwrite) NSString *searchQuery;
@property (copy, readwrite) NSArray<TSSettingsSearchResult *> *searchResults;
@property (strong) NSMutableArray<NSView *> *searchHighlights;
@property (strong, nullable) TSSettingsSearchResult *selectedSearchResult;
- (NSArray<TSSettingsCategoryID> *)visibleIdentifiers;
- (void)applySearchHighlight;
- (void)clearSearchHighlights;
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
@property CGFloat lastSidebarWidth;
@property (copy, nullable) TSSettingsCategoryID displayedCategory;
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
@synthesize categoryTextIndex = _categoryTextIndex;
@synthesize settingsSearchField = _settingsSearchField, searchStatus = _searchStatus, searchQuery = _searchQuery, searchResults = _searchResults, searchHighlights = _searchHighlights, commandNamesProvider = _commandNamesProvider, searchBundle = _searchBundle;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
{
    self = [super initWithWindow:nil];
    if (self == nil) return nil;
    _stateStore = [[TSSettingsStateStore alloc] initWithDefaults:defaults];
    _categoryList = [TSSettingsCategoryList standardList];
    self.shouldCascadeWindows = NO;
    _history = [TSSettingsNavigationHistory new];
    _categoryIdentifiers = _categoryList.identifiers;
    _searchBundle = NSBundle.mainBundle; _searchQuery = @""; _searchResults = @[]; _searchHighlights = [NSMutableArray array];
    return self;
}
- (void)setSearchBundle:(NSBundle *)bundle { _searchBundle = bundle; self.categoryTextIndex = nil; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)windowResignedKey:(NSNotification *)notification { if (self.keyboardPane != nil) { [self.keyboardPane stopKeySearch]; } }
- (void)sidebarFrameChanged:(NSNotification *)notification
{
    CGFloat width = self.categoryTable.tableColumns.firstObject.width;
    if (fabs(width - self.lastSidebarWidth) < 0.5) return;
    self.lastSidebarWidth = width;
    [self.categoryTable noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.categoryTable.numberOfRows)]];
}
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
    NSScreen *screen = window.screen ?: NSScreen.mainScreen;
    window.contentMinSize = NSMakeSize(screen != nil ? MIN(900, NSWidth(screen.visibleFrame)) : 900, 560);
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
    self.categoryTable.rowHeight = 30;
    self.categoryTable.intercellSpacing = NSMakeSize(0, 2);
    self.categoryTable.allowsEmptySelection = YES;
    self.categoryTable.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
    self.categoryTable.dataSource = self;
    self.categoryTable.delegate = self;
    [self.categoryTable setAccessibilityLabel:NSLocalizedString(@"Settings Categories", @"")];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"category"];
    column.width = 210;
    [self.categoryTable addTableColumn:column];
    listScroll.documentView = self.categoryTable;
    self.categoryTable.postsFrameChangedNotifications = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sidebarFrameChanged:) name:NSViewFrameDidChangeNotification object:self.categoryTable];
    self.settingsSearchField = [NSSearchField new];
    self.settingsSearchField.translatesAutoresizingMaskIntoConstraints = NO;
    self.settingsSearchField.placeholderString = NSLocalizedString(@"Search Settings", @"");
    self.settingsSearchField.accessibilityLabel = self.settingsSearchField.placeholderString;
    self.settingsSearchField.delegate = self;
    self.settingsSearchField.target = self;
    self.settingsSearchField.action = @selector(settingsSearchChanged:);
    self.settingsSearchField.sendsSearchStringImmediately = YES;
    self.searchStatus = [NSTextField wrappingLabelWithString:@""];
    self.searchStatus.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchStatus.textColor = NSColor.secondaryLabelColor;
    self.emptySearchStatusHeight = [self.searchStatus.heightAnchor constraintEqualToConstant:0];
    self.emptySearchStatusHeight.active = YES; self.searchStatus.hidden = YES;
    [sidebar.view addSubview:self.settingsSearchField];
    [sidebar.view addSubview:self.searchStatus];
    [sidebar.view addSubview:listScroll];
    [NSLayoutConstraint activateConstraints:@[
        [listScroll.leadingAnchor constraintEqualToAnchor:sidebar.view.leadingAnchor],
        [listScroll.trailingAnchor constraintEqualToAnchor:sidebar.view.trailingAnchor],
        [self.settingsSearchField.leadingAnchor constraintEqualToAnchor:sidebar.view.leadingAnchor constant:10],
        [self.settingsSearchField.trailingAnchor constraintEqualToAnchor:sidebar.view.trailingAnchor constant:-10],
        [self.settingsSearchField.topAnchor constraintEqualToAnchor:sidebar.view.safeAreaLayoutGuide.topAnchor constant:6],
        [self.searchStatus.leadingAnchor constraintEqualToAnchor:self.settingsSearchField.leadingAnchor],
        [self.searchStatus.trailingAnchor constraintEqualToAnchor:self.settingsSearchField.trailingAnchor],
        [self.searchStatus.topAnchor constraintEqualToAnchor:self.settingsSearchField.bottomAnchor constant:4],
        [listScroll.topAnchor constraintEqualToAnchor:self.searchStatus.bottomAnchor constant:4],
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
    self.contentScroll.automaticallyAdjustsContentInsets = NO;
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
    toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    window.toolbar = toolbar;
}
- (void)hostPaneControllers:(NSDictionary<TSSettingsCategoryID, NSViewController *> *)panes footer:(NSView *)footer
{
    (void)self.window;
    self.panes = panes;
    NSView *parent = self.contentScroll.superview;
    if (!footer.hidden) {
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [parent addSubview:footer];
    self.contentBottom.active = NO;
    [NSLayoutConstraint activateConstraints:@[
        [footer.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor],
        [footer.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor],
        [footer.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor],
        [self.contentScroll.bottomAnchor constraintEqualToAnchor:footer.topAnchor]]];
    }
    self.synchronizingSelection = YES;
    [self.categoryTable reloadData];
    self.synchronizingSelection = NO;
    NSWindow *window = self.window;
    NSSize wanted = NSMakeSize(1040, 780);
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
        width, [document.widthAnchor constraintGreaterThanOrEqualToConstant:700],
        [pane.leadingAnchor constraintEqualToAnchor:document.leadingAnchor],
        [pane.trailingAnchor constraintEqualToAnchor:document.trailingAnchor],
        [pane.topAnchor constraintEqualToAnchor:document.topAnchor],
        [pane.bottomAnchor constraintEqualToAnchor:document.bottomAnchor]]];
}
- (void)beginSession
{
    [self.changeNotes beginSession];
    self.searchQuery = @""; self.searchResults = @[]; self.selectedSearchResult = nil;
    self.settingsSearchField.stringValue = @""; self.searchStatus.stringValue = @"";
    self.emptySearchStatusHeight.active = YES; self.searchStatus.hidden = YES;
    [self clearSearchHighlights]; [self.categoryTable reloadData];
    TSSettingsCategoryID identifier = [self.stateStore selectedCategoryInIdentifiers:self.categoryIdentifiers];
    [self.history resetWithIdentifier:identifier];
    [self displayCurrentCategory];
    [self.window makeFirstResponder:self.categoryTable];
}
- (void)endSession
{
    [self.changeNotes endSession];
    if (self.keyboardPane != nil) { [self.keyboardPane stopKeySearch]; }
    [self clearSearchHighlights];
    [self.history resetWithIdentifier:self.history.currentIdentifier ?: TSSettingsCategoryGeneral];
    [self updateNavigation];
}
- (BOOL)selectCategoryIdentifier:(NSString *)identifier
{
    if (![self.categoryIdentifiers containsObject:identifier]) return NO;
    if ([identifier isEqual:self.history.currentIdentifier]) { [self applySearchHighlight]; return YES; }
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
    if ([self.settingsDelegate respondsToSelector:@selector(settingsWillDisplayCategory:)])
        [self.settingsDelegate settingsWillDisplayCategory:identifier];
    if (![self.displayedCategory isEqual:identifier]) [self.changeNotes leaveCategory];
    self.displayedCategory = identifier;
    [self clearSearchHighlights];
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
            scroll.automaticallyAdjustsContentInsets = NO;
            scroll.autohidesScrollers = YES;
            self.keyboardScroll = scroll;
            TSSettingsContentView *document = [[TSSettingsContentView alloc] initWithContent:pane];
            document.translatesAutoresizingMaskIntoConstraints = NO;
            pane.translatesAutoresizingMaskIntoConstraints = NO;
            scroll.documentView = document;
            [parent addSubview:scroll];
            NSLayoutConstraint *width = [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor];
            NSLayoutConstraint *height = [document.heightAnchor constraintEqualToAnchor:scroll.contentView.heightAnchor];
            // Keep all input groups and the list's minimum visible without a
            // second vertical scroller. Width wrapping participates in fitting.
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
    CGFloat minimum = keyboard && self.keyboardPane != nil ? MAX(560, self.keyboardPane.view.fittingSize.height + 28) : 560;
    NSSize minSize = self.window.contentMinSize; minSize.height = minimum;
    self.window.contentMinSize = minSize;
    NSSize size = self.window.contentView.bounds.size;
    if (size.height < minimum) [self.window setContentSize:NSMakeSize(size.width, minimum)];
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
    [self applySearchHighlight];
}
- (void)synchronizeSidebarSelection
{
    TSSettingsCategoryID identifier = self.history.currentIdentifier;
    TSSettingsSearchResult *selected = self.selectedSearchResult;
    NSUInteger index = self.searchQuery.length ? (selected != nil && [selected.category isEqual:identifier] ? [self.searchResults indexOfObjectIdenticalTo:selected] : NSNotFound) : (identifier != nil ? [[self visibleIdentifiers] indexOfObject:identifier] : NSNotFound);
    self.synchronizingSelection = YES;
    [self.categoryTable selectRowIndexes:index == NSNotFound ? NSIndexSet.indexSet : [NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
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
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return [self visibleIdentifiers].count; }
- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
    return row >= 0 && row < (NSInteger)[self visibleIdentifiers].count && [self visibleIdentifiers][(NSUInteger)row].length > 0;
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    if (self.synchronizingSelection || self.history.currentIdentifier == nil) { return; }
    NSInteger row = self.categoryTable.selectedRow;
    if (row < 0 || row >= (NSInteger)[self visibleIdentifiers].count) { return; }
    TSSettingsSearchResult *previous = self.selectedSearchResult;
    if (self.searchQuery.length) self.selectedSearchResult = self.searchResults[(NSUInteger)row];
    if (![self selectCategoryIdentifier:[self visibleIdentifiers][(NSUInteger)row]]) { self.selectedSearchResult = previous; [self synchronizeSidebarSelection]; }
}
- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    if (self.searchQuery.length && row>=0 && row<(NSInteger)self.searchResults.count) {
        TSSettingsSearchResult *result=self.searchResults[(NSUInteger)row];
        NSString *category=[result.category isEqual:TSSettingsCategoryKeyboard] ? NSLocalizedString(@"Keyboard", @"") : self.panes[result.category].title ?: @"";
        if (!result.targetIdentifier.length) return [TSSettingsSidebarRow heightForTitle:result.title cellWidth:tableView.tableColumns.firstObject.width];
        return [TSSettingsSidebarRow heightForSearchTitle:result.title categoryTitle:category cellWidth:tableView.tableColumns.firstObject.width];
    }
    if (row < 0 || row >= (NSInteger)[self visibleIdentifiers].count) { return 30; }
    TSSettingsCategoryID identifier = [self visibleIdentifiers][(NSUInteger)row];
    if (!identifier.length) return 8;
    NSString *title = [identifier isEqual:TSSettingsCategoryKeyboard] ? NSLocalizedString(@"Keyboard", @"") : self.panes[identifier].title ?: @"";
    return [TSSettingsSidebarRow heightForTitle:title cellWidth:tableView.tableColumns.firstObject.width];
}
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSArray<TSSettingsCategoryID> *identifiers = [self visibleIdentifiers];
    if (row < 0 || row >= (NSInteger)identifiers.count) return nil;
    if (!identifiers[(NSUInteger)row].length) { NSView *space = [NSView new]; space.accessibilityElement = NO; return space; }
    TSSettingsCategory *category = [self.categoryList categoryForIdentifier:identifiers[(NSUInteger)row]];
    if (category == nil) return nil;
    if (self.searchQuery.length) category = [[TSSettingsCategory alloc] initWithIdentifier:category.identifier symbolName:category.symbolName color:category.color startsGroup:NO];
    NSViewController *pane = self.panes[category.identifier];
    NSString *title = [category.identifier isEqualToString:TSSettingsCategoryKeyboard] ? NSLocalizedString(@"Keyboard", @"") : (pane.title ?: @"");
    if (self.searchQuery.length && self.searchResults[(NSUInteger)row].targetIdentifier.length) return [TSSettingsSidebarRow cellForSearchTitle:self.searchResults[(NSUInteger)row].title categoryTitle:title];
    NSTableCellView *cell = [TSSettingsSidebarRow cellForCategory:category title:title];
    if (self.categoryTextIndex == nil) self.categoryTextIndex = [[TSSettingsSearch alloc] initWithBundle:self.searchBundle categoryOrder:self.categoryIdentifiers commandNames:@[]];
    cell.toolTip = [self.categoryTextIndex categoryDescription:category.identifier];
    cell.accessibilityHelp = cell.toolTip;
    return cell;
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

- (NSArray<TSSettingsCategoryID> *)visibleIdentifiers
{
    if (!self.searchQuery.length) {
        NSMutableArray<NSString *> *rows = [NSMutableArray array];
        for (TSSettingsCategory *category in self.categoryList.categories) {
            if (category.startsGroup) [rows addObject:@""];
            [rows addObject:category.identifier];
        }
        return rows;
    }
    NSMutableArray<TSSettingsCategoryID> *identifiers = [NSMutableArray array];
    for (TSSettingsSearchResult *result in self.searchResults) [identifiers addObject:result.category];
    return [identifiers copy];
}
- (void)settingsSearchChanged:(NSSearchField *)sender
{
    if ([(NSTextView *)sender.currentEditor hasMarkedText]) return;
    if (![self setSettingsSearchQuery:sender.stringValue]) sender.stringValue = self.searchQuery;
}
- (void)controlTextDidChange:(NSNotification *)notification
{
    if (notification.object != self.settingsSearchField) return;
    NSTextView *editor = (NSTextView *)self.settingsSearchField.currentEditor;
    if (editor.hasMarkedText) return;
    [self settingsSearchChanged:self.settingsSearchField];
}
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command
{
    if (control == self.settingsSearchField && command == @selector(cancelOperation:)) {
        if (!textView.hasMarkedText) [self setSettingsSearchQuery:@""];
        return !textView.hasMarkedText;
    }
    return NO;
}
- (BOOL)control:(NSControl *)control textShouldBeginEditing:(NSText *)editor
{
    if (control != self.settingsSearchField) return YES;
    return !([self.keyboardPane respondsToSelector:@selector(searchingByKey)] && self.keyboardPane.searchingByKey);
}
- (BOOL)setSettingsSearchQuery:(NSString *)query
{
    if ([self.keyboardPane respondsToSelector:@selector(searchingByKey)] && self.keyboardPane.searchingByKey) return NO;
    if (self.window.attachedSheet != nil) return NO;
    NSString *effective = TSSettingsQueryTokens(query).count ? query : @"";
    BOOL fieldHadFocus = self.settingsSearchField.currentEditor != nil && self.window.firstResponder == self.settingsSearchField.currentEditor;
    self.selectedSearchResult = nil;
    self.searchQuery = effective;
    // Preserve raw input (including whitespace) independently from effective tokens.
    if (![self.settingsSearchField.stringValue isEqualToString:query]) self.settingsSearchField.stringValue = query;
    NSArray<NSString *> *commands = self.commandNamesProvider != nil ? self.commandNamesProvider() : @[];
    TSSettingsSearch *index = [[TSSettingsSearch alloc] initWithBundle:self.searchBundle categoryOrder:self.categoryIdentifiers commandNames:commands];
    self.searchResults = [index resultsForQuery:effective];
    [self clearSearchHighlights];
    self.emptySearchStatusHeight.active = !effective.length; self.searchStatus.hidden = !effective.length;
    self.searchStatus.stringValue = !effective.length ? @"" : (self.searchResults.count ? [NSString localizedStringWithFormat:NSLocalizedString(@"Settings results: %lu", @""), (unsigned long)self.searchResults.count] : NSLocalizedString(@"No Settings Found", @""));
    self.synchronizingSelection = YES; [self.categoryTable reloadData]; self.synchronizingSelection = NO;
    if (!effective.length) {
        if ([self.keyboardPane respondsToSelector:@selector(applySettingsQuery:targets:filterCommands:)]) [self.keyboardPane applySettingsQuery:@"" targets:@[] filterCommands:NO];
    }
    [self synchronizeSidebarSelection]; [self applySearchHighlight]; [self updateNavigation];
    if (fieldHadFocus && self.settingsSearchField.currentEditor == nil) [self.window makeFirstResponder:self.settingsSearchField];
    NSAccessibilityPostNotification(self.searchStatus, NSAccessibilityValueChangedNotification);
    return YES;
}
- (void)clearSearchHighlights
{
    for (NSView *view in self.searchHighlights) [view removeFromSuperview];
    [self.searchHighlights removeAllObjects];
}
- (void)applySearchHighlight
{
    [self clearSearchHighlights];
    TSSettingsCategoryID category = self.history.currentIdentifier;
    TSSettingsSearchResult *hit = [self.selectedSearchResult.category isEqual:category] ? self.selectedSearchResult : nil;
    if (hit == nil) {
        if ([category isEqualToString:TSSettingsCategoryKeyboard] && [self.keyboardPane respondsToSelector:@selector(applySettingsQuery:targets:filterCommands:)]) [self.keyboardPane applySettingsQuery:self.searchQuery targets:@[] filterCommands:NO];
        return;
    }
    NSMutableArray<NSString *> *targets = [NSMutableArray array]; BOOL commands = NO;
    NSArray<NSString *> *tokens = TSSettingsQueryTokens(self.searchQuery);
    NSString *normalized = TSSettingsNormalizedText(self.searchQuery);
    NSArray<TSSettingsSearchEntry *> *ordered = [hit.entries sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(TSSettingsSearchEntry *a, TSSettingsSearchEntry *b) {
        BOOL exactA = [a.normalizedText isEqualToString:normalized], exactB = [b.normalizedText isEqualToString:normalized];
        if (exactA != exactB) return exactA ? NSOrderedAscending : NSOrderedDescending;
        BOOL allA = TSSettingsTextMatches(a.text, tokens), allB = TSSettingsTextMatches(b.text, tokens);
        if (allA != allB) return allA ? NSOrderedAscending : NSOrderedDescending;
        if (a.weight == b.weight) return NSOrderedSame;
        return a.weight > b.weight ? NSOrderedAscending : NSOrderedDescending;
    }];
    for (TSSettingsSearchEntry *entry in ordered) { if (entry.targetIdentifier.length) [targets addObject:entry.targetIdentifier]; commands |= entry.command; }
    BOOL keyboard = [category isEqualToString:TSSettingsCategoryKeyboard];
    if (keyboard && [self.keyboardPane respondsToSelector:@selector(applySettingsQuery:targets:filterCommands:)]) {
        NSString *functionQuery = self.searchQuery;
        for (TSSettingsSearchEntry *entry in hit.entries) if (entry.command) { functionQuery = entry.text; break; }
        [self.keyboardPane applySettingsQuery:functionQuery targets:targets filterCommands:commands];
    }
    NSView *root = keyboard ? self.keyboardPane.view : self.panes[category].view;
    if (root == nil) return;
    [root layoutSubtreeIfNeeded];
    if (!hit.targetIdentifier.length) {
        CGFloat top = root.isFlipped ? 0 : MAX(0, NSHeight(root.bounds) - 1);
        [root scrollRectToVisible:NSMakeRect(0, top, 1, 1)];
        return;
    }
    NSMutableArray<NSView *> *matches = [NSMutableArray array];
    TSCollectSearchTargets(root, [NSSet setWithArray:targets], matches);
    NSMutableSet<NSString *> *highlightedGridRows = [NSMutableSet set];
    for (NSView *match in matches) {
        NSView *ancestor = match;
        while (ancestor != nil && ![ancestor.identifier isEqual:@"settings.color-table"]) ancestor = ancestor.superview;
        if ([ancestor isKindOfClass:NSGridView.class]) {
            NSGridView *grid = (NSGridView *)ancestor;
            for (NSInteger r = 0; r < grid.numberOfRows; r++) {
                BOOL contains = NO; NSRect bounds = NSZeroRect;
                for (NSInteger c = 0; c < grid.numberOfColumns; c++) {
                    NSView *content = [grid cellAtColumnIndex:c rowIndex:r].contentView;
                    if (content == nil || content == NSGridCell.emptyContentView) continue;
                    contains |= match == content || [match isDescendantOf:content];
                    NSRect rect = [content convertRect:content.bounds toView:grid];
                    bounds = NSIsEmptyRect(bounds) ? rect : NSUnionRect(bounds, rect);
                }
                NSString *key = [NSString stringWithFormat:@"%p:%ld", grid, (long)r];
                if (contains && ![highlightedGridRows containsObject:key]) {
                    [highlightedGridRows addObject:key];
                    bounds.origin.x = 0; bounds.size.width = NSWidth(grid.bounds);
                    TSSettingsSearchHighlight *overlay = [[TSSettingsSearchHighlight alloc] initWithFrame:NSInsetRect(bounds, 0, -2)];
                    overlay.autoresizingMask = NSViewWidthSizable;
                    [grid addSubview:overlay]; [self.searchHighlights addObject:overlay];
                }
            }
            continue;
        }
        NSView *row = match;
        while (row.superview != nil && row.superview != root && ![row.identifier hasPrefix:@"row."] && ![row.identifier hasPrefix:@"heading."] && ![row.identifier hasPrefix:@"shortcut."] && ![row isKindOfClass:NSBox.class]) row = row.superview;
        TSSettingsSearchHighlight *overlay = [[TSSettingsSearchHighlight alloc] initWithFrame:row.bounds];
        overlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [row addSubview:overlay]; [self.searchHighlights addObject:overlay];
    }
    NSView *first = matches.firstObject;
    if (first != nil) [first scrollRectToVisible:first.bounds];
}
@end
