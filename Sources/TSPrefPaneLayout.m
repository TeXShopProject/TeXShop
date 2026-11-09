// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefPaneLayout.h"
#import <QuartzCore/QuartzCore.h>

@interface TSSettingsIconView ()
@property (copy) NSString *symbolName;
@property (strong) NSColor *tileColor;
@end
@implementation TSSettingsIconView

- (instancetype)initWithSymbolName:(NSString *)symbolName color:(NSColor *)tileColor size:(CGFloat)size
{
    self = [super initWithFrame:NSMakeRect(0, 0, size, size)];
    if (self == nil) { return nil; }
    _symbolName = [symbolName copy];
    _tileColor = tileColor;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.widthAnchor constraintEqualToConstant:size],
        [self.heightAnchor constraintEqualToConstant:size],
    ]];
    self.accessibilityElement = NO; // The adjacent label names this decorative icon.
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect bounds = self.bounds;
    CGFloat side = NSWidth(bounds);
    if (side <= 0) { return; }
    NSBezierPath *tile = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:side * 0.24 yRadius:side * 0.24];
    NSColor *top = [self.tileColor blendedColorWithFraction:0.18 ofColor:NSColor.whiteColor] ?: self.tileColor;
    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:top endingColor:self.tileColor];
    if (gradient != nil) {
        [gradient drawInBezierPath:tile angle:90];
    } else {
        [self.tileColor setFill];
        [tile fill];
    }

    NSImage *symbol = [NSImage imageWithSystemSymbolName:self.symbolName accessibilityDescription:nil];
    if (symbol == nil) { return; } // Preserve the tile on an OS without this symbol.
    NSImageSymbolConfiguration *size = [NSImageSymbolConfiguration configurationWithPointSize:side * 0.5 weight:NSFontWeightMedium];
    NSImageSymbolConfiguration *white = [NSImageSymbolConfiguration configurationWithPaletteColors:@[NSColor.whiteColor]];
    NSImage *configured = [symbol imageWithSymbolConfiguration:[size configurationByApplyingConfiguration:white]];
    if (configured == nil) { return; }
    NSSize natural = configured.size;
    if (natural.width <= 0 || natural.height <= 0) { return; }
    CGFloat maxSide = side * 0.66;
    CGFloat scale = MIN(1.0, MIN(maxSide / natural.width, maxSide / natural.height));
    NSSize drawn = NSMakeSize(natural.width * scale, natural.height * scale);
    NSRect target = NSMakeRect(NSMidX(bounds) - drawn.width / 2, NSMidY(bounds) - drawn.height / 2, drawn.width, drawn.height);
    [configured drawInRect:target fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
}
@end

typedef NS_ENUM(NSInteger, TSSettingsRowKind) {
    TSSettingsRowControls, TSSettingsRowField, TSSettingsRowSection
};
@interface TSSettingsLayoutRow : NSObject
@property (copy, readonly) NSArray<NSString *> *identifiers;
@property (readonly) TSSettingsRowKind kind;
@property (readonly) NSUInteger indentation;
- (instancetype)initWithControls:(NSArray<NSString *> *)identifiers kind:(TSSettingsRowKind)kind indentation:(NSUInteger)indentation NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
+ (instancetype)controls:(NSArray<NSString *> *)identifiers kind:(TSSettingsRowKind)kind indentation:(NSUInteger)indentation;
@end
@implementation TSSettingsLayoutRow
+ (instancetype)controls:(NSArray<NSString *> *)identifiers kind:(TSSettingsRowKind)kind indentation:(NSUInteger)indentation
{
    return [[self alloc] initWithControls:identifiers kind:kind indentation:indentation];
}
- (instancetype)initWithControls:(NSArray<NSString *> *)identifiers kind:(TSSettingsRowKind)kind indentation:(NSUInteger)indentation
{
    self = [super init];
    if (self == nil) return nil;
    _identifiers = [identifiers copy]; _kind = kind; _indentation = indentation;
    return self;
}
@end
@interface TSSettingsLayoutGroup : NSObject
@property (copy, readonly) NSArray<TSSettingsLayoutRow *> *rows;
@property (copy, readonly) NSArray<NSArray<NSString *> *> *cells;
- (instancetype)initWithRows:(NSArray<TSSettingsLayoutRow *> *)rows cells:(NSArray<NSArray<NSString *> *> *)cells NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
+ (instancetype)rows:(NSArray<TSSettingsLayoutRow *> *)rows;
+ (instancetype)grid:(NSArray<NSArray<NSString *> *> *)cells;
@end
@implementation TSSettingsLayoutGroup
- (instancetype)initWithRows:(NSArray<TSSettingsLayoutRow *> *)rows cells:(NSArray<NSArray<NSString *> *> *)cells
{
    self = [super init];
    if (self == nil) return nil;
    _rows = [rows copy]; _cells = [cells copy]; return self;
}
+ (instancetype)rows:(NSArray<TSSettingsLayoutRow *> *)rows
{
    return [[self alloc] initWithRows:rows cells:@[]];
}
+ (instancetype)grid:(NSArray<NSArray<NSString *> *> *)cells
{
    return [[self alloc] initWithRows:@[] cells:cells];
}
@end
// The original button/cell remains the persistence endpoint and retains its outlets.
// Only its visible presentation changes; programmatic updates also reach the switch.
@interface TSSettingsSwitchPresentation : NSView
@property (strong) NSButton *source;
@property (strong) NSSwitch *toggle;
@property (strong) NSTextField *label;
- (instancetype)initWithButton:(NSButton *)button;
- (instancetype)initWithButton:(NSButton *)button labelled:(BOOL)labelled;
@property BOOL labelled;
@end
@implementation TSSettingsSwitchPresentation
- (instancetype)initWithButton:(NSButton *)button { return [self initWithButton:button labelled:YES]; }
- (instancetype)initWithButton:(NSButton *)button labelled:(BOOL)labelled
{
    self = [super initWithFrame:NSZeroRect];
    if (self == nil) return nil;
    _source = button; _labelled = labelled;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.identifier = [@"presentation." stringByAppendingString:button.identifier ?: @""];
    _label = [NSTextField wrappingLabelWithString:button.title];
    _label.translatesAutoresizingMaskIntoConstraints = NO;
    _label.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
    [_label setContentCompressionResistancePriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
    _toggle = [NSSwitch new]; _toggle.controlSize = NSControlSizeSmall; _toggle.translatesAutoresizingMaskIntoConstraints = NO;
    _toggle.target = self; _toggle.action = @selector(changed:);
    _toggle.identifier = [@"toggle." stringByAppendingString:button.identifier ?: @""];
    button.hidden = YES; button.accessibilityElement = NO;
    [self addSubview:button]; [self addSubview:_label]; [self addSubview:_toggle];
    [self setContentHuggingPriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
    if (labelled) {
    [NSLayoutConstraint activateConstraints:@[
        [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_label.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:5],
        [_label.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-5],
        [_toggle.leadingAnchor constraintGreaterThanOrEqualToAnchor:_label.trailingAnchor constant:16],
        [_toggle.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_toggle.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.heightAnchor constraintGreaterThanOrEqualToAnchor:_toggle.heightAnchor constant:4],
        [button.leadingAnchor constraintEqualToAnchor:_label.leadingAnchor],
        [button.trailingAnchor constraintEqualToAnchor:_label.trailingAnchor],
        [button.topAnchor constraintEqualToAnchor:_label.topAnchor],
        [button.bottomAnchor constraintEqualToAnchor:_label.bottomAnchor]]];
    } else {
        _label.hidden = YES;
        [NSLayoutConstraint activateConstraints:@[[_toggle.leadingAnchor constraintEqualToAnchor:self.leadingAnchor], [_toggle.trailingAnchor constraintEqualToAnchor:self.trailingAnchor], [_toggle.topAnchor constraintEqualToAnchor:self.topAnchor], [_toggle.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]]];
        for (NSView *hidden in @[button,_label]) {
            [hidden setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
            [hidden setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
            [NSLayoutConstraint activateConstraints:@[[hidden.leadingAnchor constraintEqualToAnchor:self.leadingAnchor], [hidden.widthAnchor constraintEqualToConstant:0], [hidden.topAnchor constraintEqualToAnchor:self.topAnchor], [hidden.heightAnchor constraintEqualToConstant:0]]];
        }
    }
    for (NSString *key in @[@"state", @"enabled", @"title"]) [button.cell addObserver:self forKeyPath:key options:0 context:NULL];
    [button addObserver:self forKeyPath:@"toolTip" options:0 context:NULL];
    [self synchronize];
    return self;
}
- (NSSize)intrinsicContentSize
{
    NSSize label = self.label.intrinsicContentSize, toggle = self.toggle.intrinsicContentSize;
    return self.labelled ? NSMakeSize(label.width + toggle.width + 16, MAX(label.height + 10, toggle.height + 4)) : toggle;
}
- (void)dealloc
{
    for (NSString *key in @[@"state", @"enabled", @"title"]) [self.source.cell removeObserver:self forKeyPath:key];
    [self.source removeObserver:self forKeyPath:@"toolTip"];
}
- (void)synchronize
{
    self.toggle.state = self.source.state; self.toggle.enabled = self.source.enabled;
    self.label.stringValue = self.source.title;
    self.label.textColor = self.source.enabled ? NSColor.labelColor : NSColor.disabledControlTextColor;
    self.toggle.accessibilityLabel = self.source.title;
    self.toggle.toolTip = self.source.toolTip; self.label.toolTip = self.source.toolTip;
    [self invalidateIntrinsicContentSize];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context { [self synchronize]; }
- (void)changed:(NSSwitch *)sender
{
    if (!self.source.enabled) { [self synchronize]; return; }
    self.source.state = sender.state;
    [self.source sendAction:self.source.action to:self.source.target];
    [self synchronize];
}
@end

// Radio matrices remain the action/value endpoints. The visible choice is compact.
@interface TSSettingsChoicePresentation : NSView
@property (strong) NSMatrix *source;
@property (strong) NSPopUpButton *popup;
- (instancetype)initWithMatrix:(NSMatrix *)matrix;
@end
@implementation TSSettingsChoicePresentation
- (instancetype)initWithMatrix:(NSMatrix *)matrix
{
    self = [super initWithFrame:NSZeroRect]; if (!self) return nil;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.identifier = [@"presentation." stringByAppendingString:matrix.identifier ?: @""];
    _source = matrix; matrix.hidden = YES; matrix.accessibilityElement = NO;
    matrix.translatesAutoresizingMaskIntoConstraints = NO;
    [matrix removeConstraints:matrix.constraints];
    _popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _popup.translatesAutoresizingMaskIntoConstraints = NO;
    _popup.identifier = [@"choice." stringByAppendingString:matrix.identifier ?: @""];
    _popup.target = self; _popup.action = @selector(changed:); _popup.autoenablesItems = NO;
    for (NSCell *cell in matrix.cells) {
        [_popup addItemWithTitle:cell.title]; _popup.lastItem.tag = cell.tag;
        for (NSString *key in @[@"state", @"enabled", @"title"]) [cell addObserver:self forKeyPath:key options:0 context:NULL];
    }
    [matrix addObserver:self forKeyPath:@"enabled" options:0 context:NULL];
    [self addSubview:matrix]; [self addSubview:_popup];
    for (NSView *view in self.subviews) {
        [NSLayoutConstraint activateConstraints:@[[view.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],[view.topAnchor constraintEqualToAnchor:self.topAnchor]]];
        if (view == _popup) [NSLayoutConstraint activateConstraints:@[[view.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],[view.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]]];
        else {
            [view setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
            [view setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
            [NSLayoutConstraint activateConstraints:@[[view.widthAnchor constraintEqualToConstant:0],[view.heightAnchor constraintEqualToConstant:0]]];
        }
    }
    [self setContentHuggingPriority:251 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self synchronize]; return self;
}
- (void)dealloc
{
    for (NSCell *cell in self.source.cells) for (NSString *key in @[@"state", @"enabled", @"title"]) [cell removeObserver:self forKeyPath:key];
    [self.source removeObserver:self forKeyPath:@"enabled"];
}
- (NSSize)intrinsicContentSize { return self.popup.intrinsicContentSize; }
- (void)synchronize
{
    NSArray<NSCell *> *cells = self.source.cells;
    for (NSUInteger i = 0; i < cells.count; i++) {
        NSMenuItem *item = [self.popup itemAtIndex:i]; item.title = cells[i].title; item.enabled = cells[i].enabled;
        if (cells[i].state == NSControlStateValueOn) [self.popup selectItemAtIndex:i];
    }
    self.popup.enabled = self.source.enabled;
    self.popup.toolTip = self.source.toolTip;
    [self invalidateIntrinsicContentSize];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context { [self synchronize]; }
- (void)changed:(NSPopUpButton *)sender
{
    NSInteger index = sender.indexOfSelectedItem;
    NSArray<NSCell *> *cells = self.source.cells;
    if (!self.source.enabled || index < 0 || index >= (NSInteger)cells.count || !cells[index].enabled) { [self synchronize]; return; }
    NSInteger row = 0, column = 0;
    [self.source getRow:&row column:&column ofCell:cells[index]];
    [self.source selectCellAtRow:row column:column];
    [self.source sendAction:self.source.action to:self.source.target];
    [self synchronize];
}
@end

@interface TSSettingsRadioPresentation : NSView
@property (copy) NSArray<NSButton *> *buttons;
@property (strong) NSPopUpButton *popup;
- (instancetype)initWithButtons:(NSArray<NSButton *> *)buttons;
@end
@implementation TSSettingsRadioPresentation
- (instancetype)initWithButtons:(NSArray<NSButton *> *)buttons
{
    self = [super initWithFrame:NSZeroRect]; if (!self) return nil;
    _buttons = [buttons copy]; self.translatesAutoresizingMaskIntoConstraints = NO;
    _popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; _popup.translatesAutoresizingMaskIntoConstraints = NO;
    _popup.identifier = [@"choice." stringByAppendingString:buttons.firstObject.identifier ?: @""];
    _popup.target = self; _popup.action = @selector(changed:); _popup.autoenablesItems = NO;
    for (NSButton *button in buttons) {
        [_popup addItemWithTitle:button.title]; button.hidden = YES; button.accessibilityElement = NO;
        [button removeConstraints:button.constraints]; button.translatesAutoresizingMaskIntoConstraints = NO;
        for (NSString *key in @[@"state", @"enabled", @"title"]) [button.cell addObserver:self forKeyPath:key options:0 context:NULL];
        [self addSubview:button];
    }
    [self addSubview:_popup];
    for (NSView *view in self.subviews) {
        [NSLayoutConstraint activateConstraints:@[[view.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],[view.topAnchor constraintEqualToAnchor:self.topAnchor]]];
        if (view == _popup) [NSLayoutConstraint activateConstraints:@[[view.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],[view.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]]];
        else {
            [view setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
            [view setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
            [NSLayoutConstraint activateConstraints:@[[view.widthAnchor constraintEqualToConstant:0],[view.heightAnchor constraintEqualToConstant:0]]];
        }
    }
    [self setContentHuggingPriority:251 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self synchronize]; return self;
}
- (void)dealloc { for(NSButton *button in self.buttons) for(NSString *key in @[@"state",@"enabled",@"title"]) [button.cell removeObserver:self forKeyPath:key]; }
- (NSSize)intrinsicContentSize { return self.popup.intrinsicContentSize; }
- (void)synchronize
{
    BOOL enabled = NO;
    for(NSUInteger i=0;i<self.buttons.count;i++) {
        NSButton *button=self.buttons[i]; NSMenuItem *item=[self.popup itemAtIndex:i]; item.title=button.title; item.enabled=button.enabled;
        enabled |= button.enabled; if(button.state==NSControlStateValueOn)[self.popup selectItemAtIndex:i];
    }
    self.popup.enabled=enabled; [self invalidateIntrinsicContentSize];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context { [self synchronize]; }
- (void)changed:(NSPopUpButton *)sender
{
    NSInteger index=sender.indexOfSelectedItem; if(index<0 || index>=(NSInteger)self.buttons.count || !self.buttons[index].enabled){[self synchronize];return;}
    NSButton *selected=self.buttons[index]; for(NSButton *button in self.buttons)button.state=button==selected?NSControlStateValueOn:NSControlStateValueOff;
    [selected sendAction:selected.action to:selected.target]; [self synchronize];
}
@end

static NSColor *TSSettingsCardColor(void)
{
    return [NSColor colorWithName:@"SettingsCardFill" dynamicProvider:^NSColor *(NSAppearance *appearance) {
        BOOL dark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqual:NSAppearanceNameDarkAqua];
        return [NSColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.055 : 0.04];
    }];
}
@interface TSSettingsCardBackdrop : NSView
@property (weak) NSStackView *stack;
@end
@implementation TSSettingsCardBackdrop
- (BOOL)isAccessibilityElement { return NO; }
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (instancetype)initWithFrame:(NSRect)frame
{
    self=[super initWithFrame:frame];if(self){self.wantsLayer=YES;self.layer.cornerCurve=@"continuous";}return self;
}
- (void)viewWillDraw
{
    [super viewWillDraw];
    self.layer.backgroundColor=TSSettingsCardColor().CGColor;
    self.layer.cornerRadius=[TSSettingsGroupStyle cornerRadiusForMajorVersion:NSProcessInfo.processInfo.operatingSystemVersion.majorVersion];
}
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance];self.needsDisplay=YES; }
- (void)drawRect:(NSRect)dirtyRect
{
    [NSColor.separatorColor setStroke];
    NSArray<NSView *> *rows = self.stack.arrangedSubviews;
    for (NSUInteger i = 1; i < rows.count; i++) {
        NSView *row = rows[i];
        if (![row.identifier hasPrefix:@"row."] || ![rows[i-1].identifier hasPrefix:@"row."]) continue;
        NSRect rect = [row convertRect:row.bounds toView:self];
        CGFloat y = NSMaxY(rect);
        if (y <= 1 || y >= NSHeight(self.bounds)-1) continue;
        NSBezierPath *line = [NSBezierPath bezierPath]; line.lineWidth = 0.5;
        [line moveToPoint:NSMakePoint(12, y)]; [line lineToPoint:NSMakePoint(NSWidth(self.bounds)-12, y)]; [line stroke];
    }
}
@end

@implementation TSSettingsGroupView
- (instancetype)initWithFrame:(NSRect)frame
{
    self=[super initWithFrame:frame]; if(!self)return nil;
    _title=@""; _contentView=[NSView new]; _contentView.translatesAutoresizingMaskIntoConstraints=NO;
    self.translatesAutoresizingMaskIntoConstraints=NO;
    [self addSubview:_contentView];self.accessibilityRole=NSAccessibilityGroupRole;
    return self;
}
@end

@implementation TSSettingsGroupStyle
+ (CGFloat)cornerRadiusForMajorVersion:(NSInteger)version { return version >= 26 ? 12 : 10; }
+ (void)applyToBox:(NSBox *)box
{
    box.titlePosition = NSNoTitle;
    box.boxType = NSBoxCustom;
    box.borderWidth = 0;
    box.transparent = NO;
    box.fillColor = TSSettingsCardColor();
    box.cornerRadius = [self cornerRadiusForMajorVersion:NSProcessInfo.processInfo.operatingSystemVersion.majorVersion];
    box.translatesAutoresizingMaskIntoConstraints = NO;
}
@end
@implementation TSSettingsControlRow
@synthesize controls = _controls, indentation = _indentation;
- (instancetype)initWithControls:(NSArray<NSView *> *)controls indentation:(NSUInteger)indentation
{
    self = [super init];
    if (self != nil) { _controls = [controls copy]; _indentation = indentation; }
    return self;
}
@end
@implementation TSPrefPaneLayout
#include "TSSettingsPaneComposition.inc"
+ (NSView *)switchForButton:(NSButton *)button
{
    return [[TSSettingsSwitchPresentation alloc] initWithButton:button labelled:NO];
}
+ (NSView *)choiceForControls:(NSArray<NSView *> *)controls
{
    if (controls.count > 1) return [[TSSettingsRadioPresentation alloc] initWithButtons:(NSArray<NSButton *> *)controls];
    NSView *control = controls.firstObject;
    if ([control isKindOfClass:NSMatrix.class]) return [[TSSettingsChoicePresentation alloc] initWithMatrix:(NSMatrix *)control];
    return control;
}
+ (NSTextField *)catalogLabel:(NSString *)text secondary:(BOOL)secondary
{
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [NSFont systemFontOfSize:secondary ? NSFont.smallSystemFontSize : NSFont.systemFontSize];
    label.textColor = secondary ? NSColor.secondaryLabelColor : NSColor.labelColor;
    [label setContentCompressionResistancePriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}
// The title and control share the first line. Explanatory and change notes
// use the complete row width below them, including beside wide popups.
+ (NSView *)catalogRowWithTitle:(NSString *)title note:(NSString *)note accessory:(NSView *)accessory expands:(BOOL)expands indent:(NSUInteger)indent
{
    NSView *view = [NSView new]; view.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *firstLine = [NSView new]; firstLine.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *name = [self catalogLabel:title secondary:NO]; name.identifier = @"label.catalog-row";
    [name setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [firstLine addSubview:name]; [firstLine addSubview:accessory]; accessory.translatesAutoresizingMaskIntoConstraints = NO;
    NSStackView *label = [self stackWithViews:@[firstLine] orientation:NSUserInterfaceLayoutOrientationVertical];
    label.identifier = @"label.catalog-stack"; label.spacing = 2;
    if (note.length) {
        NSTextField *detail = [self catalogLabel:note secondary:YES]; detail.identifier = @"note.catalog-row";
        [label addArrangedSubview:detail];
    }
    for (NSView *child in label.arrangedSubviews) [child.widthAnchor constraintEqualToAnchor:label.widthAnchor].active = YES;
    [view addSubview:label];
    [accessory setContentCompressionResistancePriority:751 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:12+24*indent],
        [label.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-12],
        [label.topAnchor constraintEqualToAnchor:view.topAnchor constant:9],
        [label.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-9],
        [name.leadingAnchor constraintEqualToAnchor:firstLine.leadingAnchor],
        [name.centerYAnchor constraintEqualToAnchor:firstLine.centerYAnchor],
        [name.topAnchor constraintGreaterThanOrEqualToAnchor:firstLine.topAnchor],
        [name.bottomAnchor constraintLessThanOrEqualToAnchor:firstLine.bottomAnchor],
        [accessory.trailingAnchor constraintEqualToAnchor:firstLine.trailingAnchor],
        [accessory.centerYAnchor constraintEqualToAnchor:firstLine.centerYAnchor],
        [accessory.topAnchor constraintGreaterThanOrEqualToAnchor:firstLine.topAnchor],
        [accessory.bottomAnchor constraintLessThanOrEqualToAnchor:firstLine.bottomAnchor],
        [firstLine.heightAnchor constraintGreaterThanOrEqualToConstant:20],
        [view.heightAnchor constraintGreaterThanOrEqualToConstant:38]]];
    if (expands) {
        [name.widthAnchor constraintEqualToConstant:170].active = YES;
        [accessory.leadingAnchor constraintEqualToAnchor:name.trailingAnchor constant:16].active = YES;
        [accessory setContentCompressionResistancePriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
    } else {
        [accessory setContentHuggingPriority:752 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [accessory.leadingAnchor constraintEqualToAnchor:name.trailingAnchor constant:16].active = YES;
    }
    NSLayoutConstraint *fit = [view.heightAnchor constraintEqualToConstant:38]; fit.priority=249; fit.active=YES;
    return view;
}
+ (NSView *)catalogContent:(NSView *)content trailing:(BOOL)trailing indent:(NSUInteger)indent
{
    NSView *view = [NSView new]; view.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:content]; content.translatesAutoresizingMaskIntoConstraints = NO;
    CGFloat pad = trailing ? 7 : 10;
    BOOL fills = [content.identifier isEqual:@"label.catalog-stack"];
    [NSLayoutConstraint activateConstraints:@[
        trailing ? [content.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-12] : [content.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:12+24*indent],
        fills ? [content.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-12] : (trailing ? [content.leadingAnchor constraintGreaterThanOrEqualToAnchor:view.leadingAnchor constant:12] : [content.trailingAnchor constraintLessThanOrEqualToAnchor:view.trailingAnchor constant:-12]),
        [content.topAnchor constraintEqualToAnchor:view.topAnchor constant:pad],
        [content.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-pad],
        [view.heightAnchor constraintGreaterThanOrEqualToConstant:38]]];
    return view;
}
+ (NSStackView *)stackWithViews:(NSArray<NSView *> *)views orientation:(NSUserInterfaceLayoutOrientation)orientation
{
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = orientation;
    stack.alignment = orientation == NSUserInterfaceLayoutOrientationVertical ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY;
    stack.spacing = orientation == NSUserInterfaceLayoutOrientationVertical ? 0 : 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.detachesHiddenViews = YES;
    return stack;
}
+ (void)prepareControl:(NSView *)view
{
    view.translatesAutoresizingMaskIntoConstraints = NO;
    if ([view isKindOfClass:NSTextField.class] && ((NSTextField *)view).editable)
        view.accessibilityIdentifier = @"settings.user-data";
    if ([view isKindOfClass:NSTextField.class]) {
        NSTextField *field = (NSTextField *)view;
        if (!field.editable) {
            field.cell.wraps = YES;
            field.cell.scrollable = NO;
            field.maximumNumberOfLines = 0;
            [field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        } else {
            [field.widthAnchor constraintGreaterThanOrEqualToConstant:100].active = YES;
            [field setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        }
    } else if ([view isKindOfClass:NSMatrix.class]) {
        NSMatrix *matrix = (NSMatrix *)view;
        CGFloat height = matrix.numberOfRows * matrix.cellSize.height + MAX(0, matrix.numberOfRows - 1) * matrix.intercellSpacing.height;
        [matrix.heightAnchor constraintEqualToConstant:height].active = YES;
        matrix.autosizesCells = YES;
        CGFloat width = MAX(0, matrix.numberOfColumns - 1) * matrix.intercellSpacing.width;
        for (NSInteger column = 0; column < matrix.numberOfColumns; column++) {
            CGFloat ideal = 0;
            for (NSInteger row = 0; row < matrix.numberOfRows; row++) ideal = MAX(ideal, [matrix cellAtRow:row column:column].cellSize.width);
            width += ceil(ideal);
        }
        [matrix.widthAnchor constraintGreaterThanOrEqualToConstant:width].active = YES;
        NSLayoutConstraint *fittingWidth = [matrix.widthAnchor constraintEqualToConstant:width];
        fittingWidth.priority = 249; fittingWidth.active = YES;
    } else if ([view isKindOfClass:NSColorWell.class]) {
        [view.widthAnchor constraintEqualToConstant:60].active = YES;
        [view.heightAnchor constraintEqualToConstant:24].active = YES;
    }
}
+ (NSTextField *)heading:(NSString *)title identifier:(NSString *)identifier
{
    NSTextField *heading = [NSTextField wrappingLabelWithString:title];
    heading.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    heading.identifier = identifier;
    heading.translatesAutoresizingMaskIntoConstraints = NO;
    return heading;
}
+ (void)attachRows:(NSArray<NSView *> *)rows toView:(NSView *)view
{
    NSStackView *stack = [self stackWithViews:rows orientation:NSUserInterfaceLayoutOrientationVertical];
    [view addSubview:stack]; view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:view.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:view.bottomAnchor]]];
    for (NSView *row in rows) [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
}
+ (NSSet<NSString *> *)switchIdentifiers
{
    return [NSSet setWithArray:@[@"settings.1035", @"settings.1043", @"settings.225", @"settings.230", @"settings.238", @"settings.272", @"settings.316", @"settings.325", @"settings.3gb-2l-vK7", @"settings.437", @"settings.4J7-3F-0ja", @"settings.557", @"settings.5xa-en-KkV", @"settings.8pA-l1-G9L", @"settings.936", @"settings.937", @"settings.938", @"settings.939", @"settings.946", @"settings.947", @"settings.948", @"settings.949", @"settings.958", @"settings.959", @"settings.960", @"settings.961", @"settings.9oZ-Jg-MfD", @"settings.Ot0-Z2-OiZ", @"settings.RVR-YO-Xhy", @"settings.RtB-ZN-uCk", @"settings.Tu2-Zu-ut5", @"settings.UtV-tr-Xnu", @"settings.cell.3eF-XA-ahc", @"settings.cell.839", @"settings.cell.840", @"settings.cell.841", @"settings.cell.842", @"settings.cell.843", @"settings.cell.844", @"settings.cell.845", @"settings.cell.846", @"settings.cell.8Wq-gx-FqO", @"settings.cell.CPb-hk-Gqb", @"settings.cell.PhR-Vr-jce", @"settings.cell.XoX-gZ-pO3", @"settings.cell.cgA-o7-Bdw", @"settings.cell.f1k-jx-ley", @"settings.cell.teg-0p-Q8J", @"settings.fjQ-he-GFL", @"settings.jhC-up-cya", @"settings.odf-Ny-S9G", @"settings.preview-cover-button", @"settings.sPQ-5E-qId", @"settings.spX-dz-ROL"]];
}
+ (NSView *)viewForRow:(TSSettingsControlRow *)row
{
    for (NSView *child in row.controls) {
        if ([child isKindOfClass:NSMatrix.class] && ((NSMatrix *)child).mode == NSRadioModeMatrix) child.translatesAutoresizingMaskIntoConstraints = NO;
        else [self prepareControl:child];
    }
    NSMutableArray<NSView *> *presentations = [NSMutableArray array];
    NSUInteger switchCount = 0;
    for (NSView *control in row.controls) if ([[self switchIdentifiers] containsObject:control.identifier ?: @""]) switchCount++;
    BOOL radioPair = row.controls.count >= 2 && [@[@"settings.G6V-Sw-jFT", @"settings.iRm-g2-CpD"] containsObject:row.controls[row.controls.count-2].identifier ?: @""];
    for (NSView *control in row.controls) {
        if (radioPair && [row.controls indexOfObjectIdenticalTo:control] >= row.controls.count-2) {
            if (control == row.controls[row.controls.count-2]) [presentations addObject:[[TSSettingsRadioPresentation alloc] initWithButtons:(NSArray<NSButton *> *)[row.controls subarrayWithRange:NSMakeRange(row.controls.count-2,2)]]];
            continue;
        }
        NSButton *button = [control isKindOfClass:NSButton.class] ? (NSButton *)control : nil;
        if (switchCount == 1 && button != nil && ![button isKindOfClass:NSPopUpButton.class] && [[self switchIdentifiers] containsObject:button.identifier ?: @""]) {
            [presentations addObject:[[TSSettingsSwitchPresentation alloc] initWithButton:button]];
        } else if ([control isKindOfClass:NSMatrix.class] && ((NSMatrix *)control).mode == NSRadioModeMatrix) {
            [presentations addObject:[[TSSettingsChoicePresentation alloc] initWithMatrix:(NSMatrix *)control]];
        } else [presentations addObject:control];
    }
    // Keep labels at the leading edge and accessories at the trailing edge.
    // Flexible text fields (paths and numbers) and switch rows already consume the width.
    if (presentations.count > 1 && [presentations.firstObject isKindOfClass:NSTextField.class] && !((NSTextField *)presentations.firstObject).editable && ([presentations.lastObject isKindOfClass:NSPopUpButton.class] || [presentations.lastObject isKindOfClass:TSSettingsChoicePresentation.class] || [presentations.lastObject isKindOfClass:TSSettingsRadioPresentation.class])) {
        NSView *space = [NSView new]; space.translatesAutoresizingMaskIntoConstraints = NO;
        [space setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [presentations insertObject:space atIndex:1];
    }
    NSStackView *body = [self stackWithViews:presentations orientation:NSUserInterfaceLayoutOrientationHorizontal];
    NSView *container = [NSView new]; container.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:body];
    [NSLayoutConstraint activateConstraints:@[
        [body.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:12 + 24 * row.indentation],
        [body.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-12],
        [body.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [container.heightAnchor constraintGreaterThanOrEqualToAnchor:body.heightAnchor constant:8],
        [container.heightAnchor constraintGreaterThanOrEqualToConstant:38]]];
    NSLayoutConstraint *fittingHeight = [container.heightAnchor constraintEqualToConstant:0];
    fittingHeight.priority = 249; fittingHeight.active = YES;
    container.identifier = [@"row." stringByAppendingString:row.controls.firstObject.identifier ?: @""];
    return container;
}
 + (NSView *)categoryHeaderWithTitle:(NSString *)title summary:(NSString *)summary symbol:(NSString *)symbol color:(NSColor *)color
{
    TSSettingsCardBackdrop *header = [TSSettingsCardBackdrop new]; header.translatesAutoresizingMaskIntoConstraints=NO;
    header.identifier = @"category.header";
    TSSettingsIconView *tile = [[TSSettingsIconView alloc] initWithSymbolName:symbol color:color size:44];
    NSTextField *name = [self heading:title identifier:@"category.title"];
    name.font = [NSFont boldSystemFontOfSize:15];
    NSTextField *description = [NSTextField wrappingLabelWithString:summary];
    description.identifier = @"category.description"; description.translatesAutoresizingMaskIntoConstraints = NO;
    description.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize]; description.textColor = NSColor.secondaryLabelColor;
    for (NSView *child in @[tile,name,description]) [header addSubview:child];
    [NSLayoutConstraint activateConstraints:@[
        [tile.widthAnchor constraintEqualToConstant:44], [tile.heightAnchor constraintEqualToConstant:44],
        [tile.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:14],
        [tile.topAnchor constraintEqualToAnchor:header.topAnchor constant:14],
        [tile.bottomAnchor constraintLessThanOrEqualToAnchor:header.bottomAnchor constant:-14],
        [name.leadingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:12],
        [name.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-14],
        [name.topAnchor constraintEqualToAnchor:tile.topAnchor constant:3],
        [description.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
        [description.trailingAnchor constraintEqualToAnchor:name.trailingAnchor],
        [description.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:3],
        [description.bottomAnchor constraintLessThanOrEqualToAnchor:header.bottomAnchor constant:-14]]];
    NSLayoutConstraint *height = [header.heightAnchor constraintEqualToConstant:74]; height.priority = 249; height.active = YES;
    return header;
}
 + (void)decorateGroupsInView:(NSView *)view
{
    for (NSView *child in [view.subviews copy]) [self decorateGroupsInView:child];
    if (![view isKindOfClass:NSBox.class] && ![view isKindOfClass:TSSettingsGroupView.class]) return;
    id box = view;
    NSView *contentView=[box contentView];
    NSStackView *stack = [contentView.subviews.firstObject isKindOfClass:NSStackView.class] ? (NSStackView *)contentView.subviews.firstObject : nil;
    if (stack == nil || stack.arrangedSubviews.count == 0) return;
    NSView *heading = stack.arrangedSubviews.firstObject;
    BOOL hasHeading = [heading.identifier hasPrefix:@"heading."];
    if (hasHeading) [stack setCustomSpacing:6 afterView:heading];
    // A single choice is one labelled row, as in the reference panel.
    if (hasHeading && ![view.identifier hasPrefix:@"group."] && stack.arrangedSubviews.count == 2) {
        NSView *row = stack.arrangedSubviews[1];
        NSStackView *body = [row.subviews.firstObject isKindOfClass:NSStackView.class] ? (NSStackView *)row.subviews.firstObject : nil;
        if (body.arrangedSubviews.count == 1 && ([body.arrangedSubviews.firstObject isKindOfClass:NSPopUpButton.class] || [body.arrangedSubviews.firstObject isKindOfClass:TSSettingsChoicePresentation.class])) {
            NSTextField *label = [NSTextField wrappingLabelWithString:((NSTextField *)heading).stringValue];
            label.translatesAutoresizingMaskIntoConstraints = NO;
            [label setContentHuggingPriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
            [label setContentCompressionResistancePriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
            [body insertArrangedSubview:label atIndex:0];
            heading.hidden = YES;
        }
    }
    if ([box isKindOfClass:NSBox.class]) ((NSBox *)box).transparent = YES;
    TSSettingsCardBackdrop *backdrop = [TSSettingsCardBackdrop new];
    backdrop.identifier = @"card.background"; backdrop.stack = stack;
    backdrop.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:backdrop positioned:NSWindowBelow relativeTo:contentView];
    [NSLayoutConstraint activateConstraints:@[
        [backdrop.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [backdrop.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [backdrop.topAnchor constraintEqualToAnchor:hasHeading && stack.arrangedSubviews.count > 1 ? stack.arrangedSubviews[1].topAnchor : view.topAnchor],
        [backdrop.bottomAnchor constraintEqualToAnchor:view.bottomAnchor]]];
}
+ (void)arrangeView:(NSView *)view
{
    NSString *identifier = view.identifier;
    TSSettingsLayoutGroup *model = identifier ? [self groups][identifier] : nil;
    if (model == nil) [NSException raise:NSInternalInconsistencyException format:@"Missing settings composition for %@", identifier];
    NSMutableDictionary<NSString *, NSView *> *controls = [NSMutableDictionary dictionary];
    for (NSView *child in [view.subviews copy]) {
        NSString *key = child.identifier;
        if (key == nil || controls[key] != nil) [NSException raise:NSInternalInconsistencyException format:@"Duplicate or missing settings control identifier %@", key];
        controls[key] = child;
    }
    NSMutableSet<NSString *> *used = [NSMutableSet set];
    NSView *(^take)(NSString *) = ^NSView *(NSString *key) {
        NSView *control = controls[key];
        if (control == nil || [used containsObject:key]) [NSException raise:NSInternalInconsistencyException format:@"Missing or repeated settings control %@", key];
        [used addObject:key]; [control removeFromSuperview]; return control;
    };
    NSMutableArray<NSView *> *rows = [NSMutableArray array];
    if (model.cells.count) {
        NSMutableArray<NSArray<NSView *> *> *cells = [NSMutableArray array];
        for (NSArray<NSString *> *row in model.cells) {
            NSMutableArray<NSView *> *items = [NSMutableArray array];
            for (NSString *key in row) {
                if (!key.length) { [items addObject:NSGridCell.emptyContentView]; continue; }
                NSView *child = take(key); [self prepareControl:child];
                if ([child isKindOfClass:NSTextField.class]) {
                    [child.widthAnchor constraintEqualToConstant:120].active = YES;
                    ((NSTextField *)child).preferredMaxLayoutWidth = 120;
                }
                [items addObject:child];
            }
            [cells addObject:items];
        }
        NSGridView *grid = [NSGridView gridViewWithViews:cells];
        grid.translatesAutoresizingMaskIntoConstraints = NO;
        grid.columnSpacing = 8; grid.rowSpacing = 8;
        grid.xPlacement = NSGridCellPlacementLeading; grid.yPlacement = NSGridCellPlacementCenter;
        for (NSInteger index = 0; index < grid.numberOfColumns; index++) [grid columnAtIndex:index].width = 120;
        [rows addObject:grid];
    }
    for (TSSettingsLayoutRow *row in model.rows) {
        NSMutableArray<NSView *> *items = [NSMutableArray array];
        for (NSString *key in row.identifiers) [items addObject:take(key)];
        NSView *first = items.firstObject;
        if (row.kind == TSSettingsRowSection) {
            if ([first isKindOfClass:NSBox.class]) {
                NSBox *box = (NSBox *)first;
                NSView *content = box.contentView;
                if (content == nil) [NSException raise:NSInternalInconsistencyException format:@"Missing settings group content %@", row.identifiers.firstObject];
                [self arrangeView:content]; [TSSettingsGroupStyle applyToBox:box];
                box.contentViewMargins = NSZeroSize;
                box.accessibilityLabel = box.title;
                [NSLayoutConstraint activateConstraints:@[
                    [content.leadingAnchor constraintEqualToAnchor:box.leadingAnchor],
                    [content.trailingAnchor constraintEqualToAnchor:box.trailingAnchor],
                    [content.topAnchor constraintEqualToAnchor:box.topAnchor],
                    [content.bottomAnchor constraintEqualToAnchor:box.bottomAnchor]]];
                NSStackView *body = (NSStackView *)content.subviews.firstObject;
                if (box.title.length) {
                    NSTextField *heading = [self heading:box.title identifier:[@"heading." stringByAppendingString:box.identifier ?: @""]];
                    [body insertArrangedSubview:heading atIndex:0];
                    [heading.widthAnchor constraintEqualToAnchor:body.widthAnchor].active = YES;
                }
                [rows addObject:box];
            } else if ([first isKindOfClass:NSTabView.class]) {
                for (NSTabViewItem *item in ((NSTabView *)first).tabViewItems) {
                    NSView *content = item.view;
                    if (content == nil) continue;
                    [content removeFromSuperview]; [self arrangeView:content];
                    if (item.label.length) [rows addObject:[self heading:item.label identifier:[@"heading." stringByAppendingString:content.identifier ?: @""]]];
                    [rows addObject:content];
                }
            } else [NSException raise:NSInternalInconsistencyException format:@"Invalid settings section %@", first];
            continue;
        }
        NSView *container = [self viewForRow:[[TSSettingsControlRow alloc] initWithControls:items indentation:row.indentation]];
        if (row.kind == TSSettingsRowField) [first.widthAnchor constraintEqualToConstant:170].active = YES;
        [rows addObject:container];
    }
    if (used.count != controls.count) [NSException raise:NSInternalInconsistencyException format:@"Unplaced settings controls in %@", identifier];
    [self attachRows:rows toView:view];
}
@end
