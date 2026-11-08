// Dock choices appear with fonts and color themes in Appearance.
// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSDockIconController.h"
#import "TSPrefPaneLayout.h"
#import "TSDockIcon.h"

@interface TSDockIconController ()
@property (strong) NSBundle *bundle;
@property (strong) NSUserDefaults *defaults;
@property (copy) NSString *selection;
@property (strong) NSMutableArray<NSButton *> *buttons;
@end
@implementation TSDockIconController
+ (instancetype)sharedController {
    static TSDockIconController *controller;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ controller = [[self alloc] initWithBundle:NSBundle.mainBundle defaults:NSUserDefaults.standardUserDefaults]; });
    return controller;
}
- (instancetype)initWithBundle:(NSBundle *)bundle defaults:(NSUserDefaults *)defaults {
    if ((self = [super init])) { _bundle = bundle; _defaults = defaults; _buttons = [NSMutableArray array]; }
    return self;
}
- (NSString *)text:(NSString *)key {
    return [self.bundle localizedStringForKey:key value:key table:@"SettingsDock"];
}
- (void)restoreSavedIcon {
    self.selection = TSDockIconName([self.defaults stringForKey:TSDockIconKey]);
    [self updatePreview];
}
- (void)updatePreview {
    for (NSButton *button in self.buttons)
        button.state = [TSDockIconNames()[button.tag] isEqualToString:self.selection] ? NSControlStateValueOn : NSControlStateValueOff;
    TSApplyDockIcon(NSApp.dockTile, self.bundle, self.selection);
}
- (void)chooseIcon:(NSButton *)sender {
    if (sender.tag < 0 || (NSUInteger)sender.tag >= TSDockIconNames().count) return;
    self.selection = TSDockIconNames()[sender.tag];
    [self.defaults setObject:self.selection forKey:TSDockIconKey];
    [self updatePreview];
}
- (void)installInPreferencesPane:(NSView *)pane {
    if (pane == nil || self.buttons.count != 0) return;
    NSStackView *body = [pane.subviews.firstObject isKindOfClass:NSStackView.class] ? (NSStackView *)pane.subviews.firstObject : nil;
    if (body == nil) return;
    NSBox *group = [NSBox new];
    [TSSettingsGroupStyle applyToBox:group];
    group.identifier = @"DockIconChoices";
    group.accessibilityLabel = [self text:@"Dock Icon While Running"];
    group.toolTip = [self text:@"Applies while TeXShop is running. The standard icon returns after quitting."];
    group.translatesAutoresizingMaskIntoConstraints = NO;
    NSMutableArray<NSView *> *options = [NSMutableArray array];
    NSArray *titles = @[@"Original", @"Classic Triangle", @"Retina Triangle", @"Classic Circle", @"Current (Default)"];
    NSArray *details = @[@"Before 1.0", @"1.0–3.13", @"3.14–3.38", @"3.39–5.58", @"5.60–"];
    for (NSInteger index = 0; index < 5; index++) {
        NSString *label = [self text:titles[index]];
        NSString *tip = [NSString stringWithFormat:@"%@ — %@\n%@", label, [self text:details[index]], group.toolTip];
        NSButton *button = [NSButton radioButtonWithTitle:@"" target:self action:@selector(chooseIcon:)];
        button.tag = index;
        button.accessibilityLabel = label;
        button.toolTip = tip;
        [self.buttons addObject:button];
        NSButton *image = [NSButton buttonWithImage:TSDockIconImage(self.bundle, TSDockIconNames()[index]) target:self action:@selector(chooseIcon:)];
        image.tag = index;
        image.bordered = NO;
        image.imageScaling = NSImageScaleProportionallyUpOrDown;
        image.accessibilityLabel = label;
        image.toolTip = tip;
        image.translatesAutoresizingMaskIntoConstraints = NO;
        [image.widthAnchor constraintEqualToConstant:40].active = YES;
        [image.heightAnchor constraintEqualToConstant:40].active = YES;
        NSTextField *caption = [NSTextField wrappingLabelWithString:label];
        caption.alignment = NSTextAlignmentCenter;
        NSStackView *option = [NSStackView stackViewWithViews:@[image,button,caption]];
        option.orientation = NSUserInterfaceLayoutOrientationVertical;
        option.alignment = NSLayoutAttributeCenterX;
        option.spacing = 6;
        // Give wrapping captions a definite width in each equally sized column.
        caption.translatesAutoresizingMaskIntoConstraints = NO;
        [caption.widthAnchor constraintEqualToAnchor:option.widthAnchor].active = YES;
        [caption setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSLayoutConstraint *fittingHeight = [option.heightAnchor constraintEqualToConstant:0];
        fittingHeight.priority = 249; fittingHeight.active = YES;
        [options addObject:option];
    }
    NSStackView *choices = [NSStackView stackViewWithViews:options];
    choices.distribution = NSStackViewDistributionFillEqually;
    choices.alignment = NSLayoutAttributeTop;
    choices.spacing = 12;
    NSTextField *heading = [NSTextField wrappingLabelWithString:[self text:@"Dock Icon While Running"]];
    heading.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    NSTextField *explanation = [NSTextField wrappingLabelWithString:group.toolTip ?: @""];
    NSStackView *stack = [NSStackView stackViewWithViews:@[heading,choices,explanation]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [group addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:group.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:group.trailingAnchor constant:-24],
        [stack.topAnchor constraintEqualToAnchor:group.topAnchor constant:24],
        [stack.bottomAnchor constraintEqualToAnchor:group.bottomAnchor constant:-24],
        [choices.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [heading.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [explanation.widthAnchor constraintEqualToAnchor:stack.widthAnchor]]];
    [body addArrangedSubview:group];
    [group.widthAnchor constraintEqualToAnchor:body.widthAnchor].active = YES;
}
@end
