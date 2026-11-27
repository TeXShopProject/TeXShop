// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSListBottomBar.h"

@implementation TSListBottomBar

/// A button of the bar: a symbol without a border.
static NSButton *TSListBottomBarButton(NSString *symbol, NSString *toolTip, id target, SEL action)
{
    NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:toolTip] ?: [NSImage new];
    NSButton *button = [NSButton buttonWithImage:image target:target action:action];
    button.bordered = NO;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.toolTip = toolTip;
    [button.widthAnchor constraintEqualToConstant:24].active = YES;
    [button.heightAnchor constraintEqualToConstant:22].active = YES;
    return button;
}

- (instancetype)initWithTarget:(id)target
                     addAction:(SEL)addAction addToolTip:(NSString *)addToolTip
                  removeAction:(SEL)removeAction removeToolTip:(NSString *)removeToolTip
                actionsToolTip:(NSString *)actionsToolTip
{
    if (!(self = [super initWithFrame:NSMakeRect(0, 0, 200, 37)]))
        return nil;
    _addButton = TSListBottomBarButton(@"plus", addToolTip, target, addAction);
    _removeButton = TSListBottomBarButton(@"minus", removeToolTip, target, removeAction);
    NSStackView *left = [NSStackView stackViewWithViews:@[_addButton, _removeButton]];
    left.spacing = 4;
    left.alignment = NSLayoutAttributeCenterY;
    left.translatesAutoresizingMaskIntoConstraints = NO;

    _actionsButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
    _actionsButton.bordered = NO;
    _actionsButton.toolTip = actionsToolTip;
    NSMenuItem *icon = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
    icon.image = [NSImage imageWithSystemSymbolName:@"ellipsis.circle" accessibilityDescription:actionsToolTip];
    [_actionsButton.menu addItem:icon];
    _actionsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_actionsButton.heightAnchor constraintEqualToConstant:22].active = YES;

    _separator = [NSBox new];
    _separator.boxType = NSBoxSeparator;
    _separator.translatesAutoresizingMaskIntoConstraints = NO;

    for (NSView *child in @[_separator, left, _actionsButton])
        [self addSubview:child];
    [NSLayoutConstraint activateConstraints:@[
        [_separator.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_separator.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_separator.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_separator.bottomAnchor constraintEqualToAnchor:left.topAnchor constant:-6],
        [left.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [left.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],
        [_actionsButton.centerYAnchor constraintEqualToAnchor:left.centerYAnchor],
        [_actionsButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [_actionsButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:left.trailingAnchor constant:8],
    ]];
    return self;
}

- (NSArray<NSMenuItem *> *)actionItems
{
    NSArray<NSMenuItem *> *items = self.actionsButton.menu.itemArray;
    return items.count > 1 ? [items subarrayWithRange:NSMakeRange(1, items.count - 1)] : @[];
}

@end

@implementation TSListFrameView
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer
{
    self.layer.cornerRadius = 6;
    self.layer.borderWidth = 1;
    self.layer.masksToBounds = YES;
    __block CGColorRef border = NULL, background = NULL;
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        border = NSColor.separatorColor.CGColor;
        background = NSColor.controlBackgroundColor.CGColor;
    }];
    self.layer.borderColor = border;
    self.layer.backgroundColor = background;
}
@end

const CGFloat TSListSidebarMinimumWidth = 160, TSListSidebarMaximumWidth = 320;

NSVisualEffectView *TSListSidebarView(NSScrollView *list, TSListBottomBar *bar)
{
    list.borderType = NSNoBorder;
    list.drawsBackground = NO;
    list.automaticallyAdjustsContentInsets = NO; // it starts below the title bar
    list.hasHorizontalScroller = NO;
    list.horizontalScrollElasticity = NSScrollElasticityNone;
    list.translatesAutoresizingMaskIntoConstraints = NO;
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    NSVisualEffectView *view = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, 200, 400)];
    view.material = NSVisualEffectMaterialSidebar;
    view.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    for (NSView *child in @[list, bar])
        [view addSubview:child];
    [NSLayoutConstraint activateConstraints:@[
        [list.topAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.topAnchor],
        [list.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [list.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [list.bottomAnchor constraintEqualToAnchor:bar.topAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        [view.widthAnchor constraintGreaterThanOrEqualToConstant:TSListSidebarMinimumWidth],
    ]];
    return view;
}

NSSplitViewController *TSInstallListSidebar(NSWindow *window, NSViewController *sidebar, NSViewController *main,
                                            CGFloat width, CGFloat mainMinimumWidth, NSString *autosaveName)
{
    NSRect frame = window.frame;
    // The sidebar runs up to the top, under the title bar, as in CotEditor and the macOS apps with a sidebar.
    if (!(window.styleMask & NSWindowStyleMaskFullSizeContentView))
        window.styleMask |= NSWindowStyleMaskFullSizeContentView;
    NSSplitViewController *split = [NSSplitViewController new];
    NSSplitViewItem *side = [NSSplitViewItem splitViewItemWithViewController:sidebar];
    side.canCollapse = NO;
    side.holdingPriority = NSLayoutPriorityDefaultLow + 10; // a wider window widens the main part
    side.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
    side.minimumThickness = TSListSidebarMinimumWidth;
    side.maximumThickness = TSListSidebarMaximumWidth;
    [split addSplitViewItem:side];
    NSSplitViewItem *rest = [NSSplitViewItem splitViewItemWithViewController:main];
    rest.minimumThickness = mainMinimumWidth;
    rest.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
    [split addSplitViewItem:rest];
    split.splitView.autosaveName = autosaveName;
    frame.size.width = MAX(NSWidth(frame), width + split.splitView.dividerThickness + mainMinimumWidth);
    window.contentViewController = split;
    [window setFrame:frame display:NO];
    [split.splitView setPosition:width ofDividerAtIndex:0];
    return split;
}
