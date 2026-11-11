// Dock choices appear in General.
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
    for (NSButton *button in self.buttons) {
        button.state = [TSDockIconNames()[button.tag] isEqualToString:self.selection] ? NSControlStateValueOn : NSControlStateValueOff;
        button.layer.borderWidth = button.state == NSControlStateValueOn ? 3 : 0;
        button.layer.borderColor = NSColor.controlAccentColor.CGColor;
    }
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
    TSSettingsGroupView *group = nil;
    for (NSView *candidate in body.arrangedSubviews) if ([candidate.identifier isEqual:@"group.general.6"]) group=(TSSettingsGroupView *)candidate;
    if (group == nil) return;
    NSMutableArray<NSView *> *options = [NSMutableArray array];
    NSArray *titles = @[@"Original", @"Classic Triangle", @"Retina Triangle", @"Classic Circle", @"Current (Default)"];
    NSArray *details = @[@"Before 1.0", @"1.0–3.13", @"3.14–3.38", @"3.39–5.58", @"5.60–"];
    NSArray<NSString *> *years = TSDockIconYears();
    for (NSInteger index = 0; index < 5; index++) {
        NSString *label = [self text:titles[index]];
        NSString *tip = [NSString stringWithFormat:@"%@ — %@", label, [self text:details[index]]];
        NSImage *artwork=[TSDockIconImage(self.bundle,TSDockIconNames()[index]) copy];artwork.size=NSMakeSize(52,52);
        NSButton *button=[NSButton buttonWithImage:artwork target:self action:@selector(chooseIcon:)];
        button.tag=index;button.bordered=NO;button.imageScaling=NSImageScaleNone;
        button.accessibilityLabel=label;button.accessibilityRole=NSAccessibilityRadioButtonRole;button.toolTip=tip;
        button.translatesAutoresizingMaskIntoConstraints=NO;button.wantsLayer=YES;button.layer.cornerRadius=12;
        [button.widthAnchor constraintEqualToConstant:64].active=YES;[button.heightAnchor constraintEqualToConstant:64].active=YES;
        [self.buttons addObject:button];
        NSTextField *caption = [NSTextField labelWithString:years[index]];
        caption.identifier = @"dock.years";
        caption.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
        caption.textColor = NSColor.secondaryLabelColor;
        NSStackView *option = [NSStackView stackViewWithViews:@[button, caption]];
        option.spacing = 4;
        option.orientation = NSUserInterfaceLayoutOrientationVertical;
        option.alignment = NSLayoutAttributeCenterX;
        NSLayoutConstraint *fittingHeight = [option.heightAnchor constraintEqualToConstant:0];
        fittingHeight.priority = 249; fittingHeight.active = YES;
        [options addObject:option];
    }
    NSStackView *choices = [NSStackView stackViewWithViews:options];
    choices.distribution = NSStackViewDistributionFillEqually;
    choices.alignment = NSLayoutAttributeTop;
    choices.spacing = 6;
    NSStackView *stack=[TSPrefPaneLayout stackWithViews:@[choices] orientation:NSUserInterfaceLayoutOrientationVertical];
    [choices.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;
    NSView *row=[TSPrefPaneLayout catalogContent:stack trailing:NO indent:0];row.identifier=@"DockIconChoices";
    [stack.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12].active=YES;
    NSStackView *rows=(NSStackView *)group.contentView.subviews.firstObject;
    [rows addArrangedSubview:row];[row.widthAnchor constraintEqualToAnchor:rows.widthAnchor].active=YES;
    // The backdrop was created while the dock group had only a heading.
    for(NSView *background in group.subviews)if([background.identifier isEqual:@"card.background"])
        for(NSLayoutConstraint *constraint in group.constraints.copy)if(constraint.firstItem==background && constraint.firstAttribute==NSLayoutAttributeTop){constraint.active=NO;[background.topAnchor constraintEqualToAnchor:row.topAnchor].active=YES;}
}
@end
