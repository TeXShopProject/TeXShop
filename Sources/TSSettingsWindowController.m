// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsWindowController.h"
static NSString * const TSSettingsSelectedCategory = @"TSSettingsSelectedCategory";
static NSToolbarItemIdentifier const TSSettingsDivider = @"settings.divider";
static NSToolbarItemIdentifier const TSSettingsNavigation = @"settings.navigation";

@interface TSSettingsIconView : NSView
@property (copy) NSString *symbol;
@property (strong) NSColor *tileColor;
@end
@implementation TSSettingsIconView
- (void)drawRect:(NSRect)dirtyRect
{
    NSBezierPath *tile = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:6 yRadius:6];
    NSColor *top = [self.tileColor blendedColorWithFraction:0.18 ofColor:NSColor.whiteColor] ?: self.tileColor;
    [[[NSGradient alloc] initWithStartingColor:top endingColor:self.tileColor] drawInBezierPath:tile angle:90];
    NSImage *symbol = [NSImage imageWithSystemSymbolName:self.symbol accessibilityDescription:nil];
    NSImageSymbolConfiguration *configuration = [[NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightMedium]
        configurationByApplyingConfiguration:[NSImageSymbolConfiguration configurationWithPaletteColors:@[NSColor.whiteColor]]];
    NSImage *image = [symbol imageWithSymbolConfiguration:configuration];
    if (image == nil || image.size.width <= 0 || image.size.height <= 0) return;
    CGFloat scale = MIN(18 / image.size.width, 18 / image.size.height);
    NSSize size = NSMakeSize(image.size.width * scale, image.size.height * scale);
    [image drawInRect:NSMakeRect(NSMidX(self.bounds)-size.width/2,NSMidY(self.bounds)-size.height/2,size.width,size.height)];
}
@end
@interface TSSettingsWindowController () <NSTableViewDataSource, NSTableViewDelegate, NSToolbarDelegate>
@property (strong) NSUserDefaults *defaults;
@property (strong, readwrite) TSSettingsNavigationHistory *history;
@property (copy, readwrite) NSArray<NSString *> *categoryIdentifiers;
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
    if (self.isKeyWindow && (event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagControl | NSEventModifierFlagOption)) == NSEventModifierFlagCommand) {
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
    self = [super initWithWindowNibName:@"SettingsWindow"];
    if (self == nil) return nil;
    _defaults = defaults;
    _history = [TSSettingsNavigationHistory new];
    _categoryIdentifiers = @[@"source", @"editor", @"preview", @"console", @"typesetting", @"engines", @"misc-1", @"misc-2", @"themes"];
    return self;
}
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
    [window setFrameAutosaveName:@"SettingsSidebarWindow"];
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
    self.navigationControl = [NSSegmentedControl segmentedControlWithImages:@[
        [NSImage imageWithSystemSymbolName:@"chevron.left" accessibilityDescription:NSLocalizedString(@"Back", @"")],
        [NSImage imageWithSystemSymbolName:@"chevron.right" accessibilityDescription:NSLocalizedString(@"Forward", @"")]]
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
        NSMutableArray<NSView *> *pending = [NSMutableArray arrayWithArray:item.view.subviews];
        while (pending.count > 0) {
            NSView *view = pending.firstObject; [pending removeObjectAtIndex:0];
            [views addObject:view]; [frames addObject:[NSValue valueWithRect:view.frame]];
            [pending addObjectsFromArray:view.subviews];
        }
    }
    tabs.tabViewType = NSNoTabsNoBorder;
    tabs.translatesAutoresizingMaskIntoConstraints = YES;
    tabs.autoresizingMask = NSViewNotSizable;
    tabs.frame = paneFrame;
    for (NSUInteger index = 0; index < views.count; index++) views[index].frame = frames[index].rectValue;
    self.contentScroll.documentView = content;
    [self.categoryTable reloadData];
    self.window.initialFirstResponder = self.categoryTable;
    [self.window recalculateKeyViewLoop];
}
- (NSView *)legacyViewForCategoryIdentifier:(NSString *)identifier
{
    NSUInteger index = [self.categoryIdentifiers indexOfObject:identifier];
    if (index == NSNotFound || index >= (NSUInteger)self.legacyTabs.numberOfTabViewItems) return nil;
    return [self.legacyTabs tabViewItemAtIndex:index].view;
}
- (void)beginSession
{
    NSString *identifier = [self.defaults stringForKey:TSSettingsSelectedCategory];
    if (![self.categoryIdentifiers containsObject:identifier]) identifier = self.categoryIdentifiers.firstObject;
    [self.history resetWithIdentifier:identifier];
    [self displayCurrentCategory];
}
- (void)endSession
{
    [self.history resetWithIdentifier:self.history.currentIdentifier ?: self.categoryIdentifiers.firstObject];
    [self updateNavigation];
}
- (BOOL)selectCategoryIdentifier:(NSString *)identifier
{
    if (![self.categoryIdentifiers containsObject:identifier]) return NO;
    if ([identifier isEqualToString:self.history.currentIdentifier]) return YES;
    if (self.window.attachedSheet != nil || ![self.settingsDelegate settingsMayChangeCategory]) return NO;
    [self.history visitIdentifier:identifier];
    [self displayCurrentCategory];
    return YES;
}
- (void)goBack:(id)sender
{
    if (self.history.backIdentifier == nil || self.window.attachedSheet != nil || ![self.settingsDelegate settingsMayChangeCategory]) return;
    [self.history goBack]; [self displayCurrentCategory];
}
- (void)goForward:(id)sender
{
    if (self.history.forwardIdentifier == nil || self.window.attachedSheet != nil || ![self.settingsDelegate settingsMayChangeCategory]) return;
    [self.history goForward]; [self displayCurrentCategory];
}
- (void)navigate:(NSSegmentedControl *)sender
{
    if (sender.selectedSegment == 0) [self goBack:sender]; else [self goForward:sender];
}
- (void)displayCurrentCategory
{
    NSUInteger index = [self.categoryIdentifiers indexOfObject:self.history.currentIdentifier];
    if (index == NSNotFound || index >= (NSUInteger)self.legacyTabs.numberOfTabViewItems) return;
    // Input has already been validated. Avoid repeating the legacy delegate path.
    id<NSTabViewDelegate> delegate = self.legacyTabs.delegate;
    self.legacyTabs.delegate = nil;
    [self.legacyTabs selectTabViewItemAtIndex:index];
    self.legacyTabs.delegate = delegate;
    self.synchronizingSelection = YES;
    [self.categoryTable selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
    self.synchronizingSelection = NO;
    self.window.title = [self.legacyTabs tabViewItemAtIndex:index].label;
    [self.legacyContent setAccessibilityLabel:self.window.title];
    [self.defaults setObject:self.history.currentIdentifier forKey:TSSettingsSelectedCategory];
    [self.contentScroll.contentView scrollToPoint:NSMakePoint(0, MAX(0, NSHeight(self.legacyContent.frame)-NSHeight(self.contentScroll.contentView.bounds)))];
    [self.contentScroll reflectScrolledClipView:self.contentScroll.contentView];
    [self.window recalculateKeyViewLoop];
    [self updateNavigation];
}
- (void)updateNavigation
{
    [self.navigationControl setEnabled:self.history.backIdentifier != nil forSegment:0];
    [self.navigationControl setEnabled:self.history.forwardIdentifier != nil forSegment:1];
}
- (void)changeFont:(id)sender { [self.settingsDelegate settingsChangeFont:sender]; }
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.legacyTabs.numberOfTabViewItems; }
- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
    if (self.synchronizingSelection) return YES;
    if (row < 0 || row >= (NSInteger)self.categoryIdentifiers.count) return NO;
    [self selectCategoryIdentifier:self.categoryIdentifiers[(NSUInteger)row]];
    return NO; // displayCurrentCategory owns the selection after successful validation.
}
- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    return (row == 2 || row == 4 || row == 6) ? 62 : 50;
}
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    if (row < 0 || row >= (NSInteger)self.legacyTabs.numberOfTabViewItems) return nil;
    NSTableCellView *cell = [[NSTableCellView alloc] init];
    NSTextField *label = [NSTextField wrappingLabelWithString:[self.legacyTabs tabViewItemAtIndex:row].label];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.maximumNumberOfLines = 2;
    label.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
    label.lineBreakMode = NSLineBreakByWordWrapping;
    cell.textField = label;
    NSArray<NSString *> *symbols = @[@"doc.text", @"text.cursor", @"doc.richtext", @"terminal", @"textformat", @"gearshape.2", @"slider.horizontal.3", @"switch.2", @"paintpalette"];
    NSArray<NSColor *> *colors = @[NSColor.systemBlueColor,NSColor.systemOrangeColor,NSColor.systemCyanColor,NSColor.darkGrayColor,NSColor.systemPurpleColor,NSColor.systemGrayColor,NSColor.systemIndigoColor,NSColor.systemTealColor,NSColor.systemPinkColor];
    TSSettingsIconView *icon = [TSSettingsIconView new]; icon.symbol = symbols[row]; icon.tileColor = colors[row];
    icon.translatesAutoresizingMaskIntoConstraints = NO; icon.accessibilityElement = NO;
    BOOL startsGroup = row == 2 || row == 4 || row == 6;
    if (startsGroup) {
        NSBox *separator = [NSBox new]; separator.boxType = NSBoxSeparator;
        separator.translatesAutoresizingMaskIntoConstraints = NO; [cell addSubview:separator];
        [NSLayoutConstraint activateConstraints:@[[separator.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:6],
            [separator.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-6],
            [separator.topAnchor constraintEqualToAnchor:cell.topAnchor constant:3]]];
    }
    [cell addSubview:icon]; [cell addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:6], [icon.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor constant:startsGroup ? 6 : 0],
        [icon.widthAnchor constraintEqualToConstant:28], [icon.heightAnchor constraintEqualToConstant:28],
        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:8],
        [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4], [label.centerYAnchor constraintEqualToAnchor:icon.centerYAnchor]]];
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
@end
