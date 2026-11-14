// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN

/// The bar at the bottom of a list, as in the sidebars of macOS apps: a separator line on top, ＋ and − without
/// borders at the leading edge and a pull-down menu shown as ⊙… at the trailing edge. The Multiple Replace window
/// (under its sets) and the macro editor (under its items) use it.
///
/// The bar takes the list's width and its fitting height (the line, 6 points, a 22-point button and 8 points); its
/// owner places it with Auto Layout or with a frame. Its background is the list's: the bar draws only the line and its buttons.
@interface TSListBottomBar : NSView

/// ＋ and − send their actions to the target; their tool tips are also their accessibility descriptions. The menu of
/// the actions button starts with its ⊙… image; the actions are added to actionsButton.menu after it.
- (instancetype)initWithTarget:(nullable id)target
                     addAction:(nullable SEL)addAction addToolTip:(NSString *)addToolTip
                  removeAction:(nullable SEL)removeAction removeToolTip:(NSString *)removeToolTip
                actionsToolTip:(NSString *)actionsToolTip NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@property (nonatomic, readonly) NSBox *separator;
@property (nonatomic, readonly) NSButton *addButton;
@property (nonatomic, readonly) NSButton *removeButton;
/// A borderless pull-down button; its first item is the ⊙… image, the actions follow it.
@property (nonatomic, readonly) NSPopUpButton *actionsButton;
/// The actions after the image item.
@property (nonatomic, readonly) NSArray<NSMenuItem *> *actionItems;

@end

NS_ASSUME_NONNULL_END
