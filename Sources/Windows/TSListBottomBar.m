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
