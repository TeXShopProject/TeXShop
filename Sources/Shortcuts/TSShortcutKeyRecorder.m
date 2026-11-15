// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSShortcutKeyRecorder.h"
#import "TSPrefPaneLayout.h"

@implementation TSShortcutKeyLabel
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(accessibilityPerformPress)) { return self.press != nil; }
    return [super isAccessibilitySelectorAllowed:selector];
}
- (BOOL)accessibilityPerformPress {
    if (self.press == nil) { return NO; }
    self.press(self);
    return YES;
}
@end

// The field's text 4 points from its leading edge and 2 before the remove button, which is
// 14 points wide, 3 from the trailing edge.
static const CGFloat TSRecorderTextInset = 4, TSRecorderTextGap = 2, TSRecorderRemoveSize = 14, TSRecorderRemoveInset = 3;
@implementation TSShortcutKeyRecorder
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self == nil) { return nil; }
    _shortcut = @"";
    _label = [NSTextField labelWithString:@""];
    _label.alignment = NSTextAlignmentCenter; _label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _label.accessibilityElement = NO; _label.identifier = @"shortcut.recorder-text";
    NSString *remove = NSLocalizedString(@"Remove Shortcut", @"");
    NSImage *minus = [NSImage imageWithSystemSymbolName:@"minus.circle.fill" accessibilityDescription:remove] ?: [NSImage new];
    _removeButton = [NSButton buttonWithImage:minus target:nil action:NULL];
    _removeButton.bordered = NO; _removeButton.imageScaling = NSImageScaleProportionallyDown;
    _removeButton.contentTintColor = NSColor.secondaryLabelColor; _removeButton.refusesFirstResponder = YES;
    _removeButton.toolTip = remove; _removeButton.identifier = @"shortcut.recorder-remove";
    [_label setContentCompressionResistancePriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
    for (NSView *view in @[_label, _removeButton]) { view.translatesAutoresizingMaskIntoConstraints = NO; [self addSubview:view]; }
    [NSLayoutConstraint activateConstraints:@[
        [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:TSRecorderTextInset],
        [_label.trailingAnchor constraintEqualToAnchor:_removeButton.leadingAnchor constant:-TSRecorderTextGap],
        [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_removeButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-TSRecorderRemoveInset],
        [_removeButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_removeButton.widthAnchor constraintEqualToConstant:TSRecorderRemoveSize], [_removeButton.heightAnchor constraintEqualToConstant:TSRecorderRemoveSize]]];
    self.focusRingType = NSFocusRingTypeExterior;
    self.identifier = @"shortcut.recorder";
    return self;
}
- (void)setShortcut:(NSString *)shortcut {
    _shortcut = [shortcut copy] ?: @"";
    NSMutableParagraphStyle *centered = [NSMutableParagraphStyle new];
    centered.alignment = NSTextAlignmentCenter; centered.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:_shortcut attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:NSFont.systemFontSize], NSForegroundColorAttributeName: NSColor.labelColor, NSParagraphStyleAttributeName: centered}];
    // The key is selected, as text in a field that waits for a replacement.
    if (_shortcut.length) { [text addAttribute:NSBackgroundColorAttributeName value:NSColor.selectedTextBackgroundColor range:NSMakeRange(0, text.length)]; }
    self.label.attributedStringValue = text;
    NSAccessibilityPostNotification(self, NSAccessibilityValueChangedNotification);
}
- (void)drawRect:(NSRect)dirtyRect {
    [NSColor.textBackgroundColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:4 yRadius:4] fill];
}
- (NSRect)focusRingMaskBounds { return self.bounds; }
- (void)drawFocusRingMask { [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:4 yRadius:4] fill]; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)resignFirstResponder {
    if (![super resignFirstResponder]) { return NO; }
    if (self.resigned) { self.resigned(); }
    return YES;
}
- (NSView *)hitTest:(NSPoint)point {
    NSView *hit = [super hitTest:point];
    if (hit == nil || hit == self.removeButton) { return hit; }
    return self;
}
- (void)mouseDown:(NSEvent *)event {
    if (self.window.firstResponder != self) { [self.window makeFirstResponder:self]; }
}
- (BOOL)isAccessibilityElement { return YES; }
- (NSString *)accessibilityRole { return NSAccessibilityTextFieldRole; }
- (NSString *)accessibilityLabel { return NSLocalizedString(@"Change Shortcut", @""); }
- (id)accessibilityValue { return self.shortcut.length ? self.shortcut : NSLocalizedString(@"Press a key", @""); }
- (NSString *)accessibilityHelp { return NSLocalizedString(@"Press a key", @""); }
@end

// The field 18 points high in the middle of the cell, 20 points of the cell after it for the
// triangle, 2 points from the cell's trailing edge.
static const CGFloat TSRecordingCellWarningRoom = 20, TSRecordingCellWarningInset = 2, TSRecordingCellFieldHeight = 18;
@implementation TSShortcutRecordingCell
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self == nil) { return nil; }
    _recorder = [[TSShortcutKeyRecorder alloc] initWithFrame:NSMakeRect(0, 0, 120, 20)];
    NSFont *font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _warning = [TSPrefPaneLayout warningSymbolForFont:font];
    _warning.identifier = @"shortcut.recording-warning";
    self.identifier = @"shortcut.recording";
    for (NSView *view in @[_recorder, _warning]) { view.translatesAutoresizingMaskIntoConstraints = NO; [self addSubview:view]; }
    [NSLayoutConstraint activateConstraints:@[
        [_recorder.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_recorder.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-TSRecordingCellWarningRoom],
        [_recorder.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_recorder.heightAnchor constraintEqualToConstant:TSRecordingCellFieldHeight],
        [_warning.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-TSRecordingCellWarningInset],
        [_warning.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]]];
    return self;
}
+ (CGFloat)widthForShortcut:(NSString *)shortcut {
    CGFloat text = ceil([shortcut sizeWithAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:NSFont.systemFontSize]}].width);
    return TSRecorderTextInset + text + TSRecorderTextGap + TSRecorderRemoveSize + TSRecorderRemoveInset + TSRecordingCellWarningRoom;
}
@end

// Between the triangle and the text, as in the other warnings of the Settings window.
static const CGFloat TSShortcutWarningSpacing = 4;
NSStackView *TSShortcutWarningLine(NSString *text)
{
    NSFont *font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = font; label.textColor = NSColor.labelColor; label.identifier = @"shortcut.inactive-reason";
    [label setContentCompressionResistancePriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *warning = [NSStackView stackViewWithViews:@[[TSPrefPaneLayout warningSymbolForFont:font], label]];
    warning.orientation = NSUserInterfaceLayoutOrientationHorizontal; warning.alignment = NSLayoutAttributeFirstBaseline;
    warning.spacing = TSShortcutWarningSpacing; warning.translatesAutoresizingMaskIntoConstraints = NO;
    warning.identifier = @"shortcut.inactive-warning";
    return warning;
}
