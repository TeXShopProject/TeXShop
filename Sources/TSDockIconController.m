// Dock appearance is independent of editor color themes, so the choices live on Misc2.
// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSDockIconController.h"
#import "TSDockIcon.h"

@interface TSDockIconController ()
@property (strong) NSBundle *bundle;
@property (strong) NSUserDefaults *defaults;
@property (copy) NSString *selection;
@property (strong) NSMutableArray<NSButton *> *buttons;
@property BOOL editing;
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
    NSArray *languages = [NSUserDefaults.standardUserDefaults stringArrayForKey:@"AppleLanguages"] ?: NSLocale.preferredLanguages;
    NSString *language = [NSBundle preferredLocalizationsFromArray:@[@"en", @"ja"] forPreferences:languages].firstObject;
    NSString *path = [self.bundle.resourcePath stringByAppendingPathComponent:[NSString stringWithFormat:@"DockIcons/%@.lproj/DockIcons.strings", language]];
    NSDictionary *strings = [NSDictionary dictionaryWithContentsOfFile:path];
    return strings[key] ?: key;
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
    self.selection = TSDockIconNames()[sender.tag];
    [self updatePreview];
}
- (void)installInPreferences:(NSTabView *)tabs {
    if (self.buttons.count || tabs.numberOfTabViewItems < 2) return;
    // The second-to-last tab is Misc2 in every localization. Its lower-left corner
    // is free below the left column, which leaves room for more choices later.
    NSView *misc = tabs.tabViewItems[tabs.numberOfTabViewItems - 2].view;
    CGFloat middle = NSMidX(misc.bounds);
    NSBox *column = nil;
    for (NSView *view in misc.subviews)
        if ([view isKindOfClass:NSBox.class] && NSMidX(view.frame) < middle && (!column || NSMinY(view.frame) < NSMinY(column.frame)))
            column = (NSBox *)view;
    if (!column) return;
    CGFloat left = NSMinX(column.frame), top = NSMinY(column.frame) - 12, bottom = 4;
    CGFloat right = NSMaxX(column.frame);
    for (NSView *view in misc.subviews)
        if (NSMidX(view.frame) >= middle && NSMinY(view.frame) < top)
            right = MIN(right, NSMinX(view.frame) - 8);
    CGFloat height = MIN(top - bottom, 96);
    if (height < 80 || right - left < 200) return;
    NSBox *group = [[NSBox alloc] initWithFrame:NSMakeRect(left, top - height, right - left, height)];
    group.title = [self text:@"Dock Icon While Running"];
    group.identifier = @"DockIconChoices";
    group.toolTip = [self text:@"Applies while TeXShop is running. The standard icon returns after quitting."];
    group.autoresizingMask = NSViewMinYMargin;
    [misc addSubview:group];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(preferencesClosed:) name:NSWindowWillCloseNotification object:tabs.window];
    NSView *panel = group.contentView;
    NSArray *titles = @[@"Original", @"Classic Triangle", @"Retina Triangle", @"Classic Circle", @"Current (Default)"];
    NSArray *details = @[@"Before 1.0", @"1.0–3.13", @"3.14–3.38", @"3.39–5.58", @"5.59–"];
    CGFloat cellWidth = MIN(panel.bounds.size.width / 5, 72);
    CGFloat iconHeight = MIN(38, NSHeight(panel.bounds) - 32);
    for (NSInteger index = 0; index < 5; index++) {
        CGFloat center = (index + 0.5) * cellWidth;
        NSString *label = [self text:titles[index]];
        NSString *tip = [NSString stringWithFormat:@"%@ — %@\n%@", label, [self text:details[index]], group.toolTip];
        NSButton *button = [NSButton radioButtonWithTitle:@"" target:self action:@selector(chooseIcon:)];
        button.tag = index;
        button.frame = NSMakeRect(center - 10, 3, 20, 22);
        button.accessibilityLabel = label;
        button.toolTip = tip;
        [panel addSubview:button]; [self.buttons addObject:button];
        NSButton *image = [NSButton buttonWithImage:TSDockIconImage(self.bundle, TSDockIconNames()[index]) target:self action:@selector(chooseIcon:)];
        image.tag = index;
        image.frame = NSMakeRect(center - 16, 28, 32, iconHeight);
        image.bordered = NO;
        image.imageScaling = NSImageScaleProportionallyUpOrDown;
        image.accessibilityLabel = label;
        image.toolTip = tip;
        [panel addSubview:image];
    }
}
- (void)beginEditing { self.editing = YES; [self restoreSavedIcon]; }
- (void)acceptEditing {
    if (!self.editing) return;
    [self.defaults setObject:self.selection forKey:TSDockIconKey];
    [self.defaults synchronize];
    self.editing = NO;
}
- (void)cancelEditing { self.editing = NO; [self restoreSavedIcon]; }
- (void)preferencesClosed:(NSNotification *)notification {
    if (self.editing) [self cancelEditing];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end
