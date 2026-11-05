// Dock appearance is independent of editor color themes.
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
    if (self.buttons.count) return;
    NSView *themes = tabs.tabViewItems.lastObject.view;
    NSMutableArray<NSBox *> *boxes = [NSMutableArray array];
    for (NSView *view in themes.subviews) if ([view isKindOfClass:NSBox.class]) [boxes addObject:(NSBox *)view];
    if (boxes.count < 2) return;
    [boxes sortUsingComparator:^NSComparisonResult(NSBox *a, NSBox *b) {
        return NSMinY(a.frame) < NSMinY(b.frame) ? NSOrderedAscending : NSOrderedDescending;
    }];
    NSRect lower = boxes[0].frame, upper = boxes[1].frame;
    CGFloat bottom = NSMaxY(lower) + 4, height = NSMinY(upper) - bottom - 4;
    if (height < 98) return;
    // Use the existing gap between the Themes and Actions groups in every nib.
    CGFloat width = NSWidth(lower);
    for (NSView *view in themes.subviews)
        if ([view isKindOfClass:NSTabView.class]) width = MIN(width, NSMinX(view.frame) - NSMinX(lower) - 4);
    NSBox *group = [[NSBox alloc] initWithFrame:NSMakeRect(NSMinX(lower), bottom, width, height)];
    group.title = [self text:@"Dock Icon"];
    group.identifier = @"DockIconChoices";
    group.toolTip = [self text:@"Applies while TeXShop is running. The standard icon returns after quitting."];
    group.autoresizingMask = NSViewMinYMargin;
    [themes addSubview:group];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(preferencesClosed:) name:NSWindowWillCloseNotification object:tabs.window];
    NSView *panel = group.contentView;
    NSArray *titles = @[@"Original", @"Classic Triangle", @"Retina Triangle", @"Classic Circle", @"Current (Default)"];
    NSArray *details = @[@"High-resolution reconstruction", @"High-resolution reconstruction", @"3.14–3.38", @"3.39–5.58", @"5.59–"];
    CGFloat cellWidth = panel.bounds.size.width / 5;
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
        image.frame = NSMakeRect(center - 16, 28, 32, 38);
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
