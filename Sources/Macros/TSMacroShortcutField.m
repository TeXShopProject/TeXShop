// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSMacroShortcutField.h"

static const CGFloat TSClearSize = 16, TSClearInset = 4;

@interface TSMacroShortcutField ()
@property (nonatomic, readwrite, getter=isRecording) BOOL recording;
@property (nonatomic, copy) NSString *placeholder;
/// While the field waits: keys reach it before the window's buttons (Return, Escape) and the menus.
@property (nonatomic, strong, nullable) id keyMonitor;
@end

@implementation TSMacroShortcutField

- (instancetype)initWithFrame:(NSRect)frame model:(NSTextField *)model placeholder:(NSString *)placeholder clearTitle:(NSString *)clearTitle
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    _placeholder = [placeholder copy];
    _shortcut = @"";
    _enabled = YES;
    _display = [NSTextField textFieldWithString:@""];
    _display.editable = NO;
    _display.selectable = NO;
    _display.refusesFirstResponder = YES;
    _display.alignment = NSTextAlignmentCenter;
    _display.lineBreakMode = NSLineBreakByTruncatingTail;
    _display.accessibilityElement = NO; // the field speaks for it
    if (model) {
        _display.bezeled = model.bezeled;
        _display.bezelStyle = model.bezelStyle;
        _display.font = model.font;
    }
    _display.frame = self.bounds;
    _display.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self addSubview:_display];

    NSImage *cross = [NSImage imageWithSystemSymbolName:@"xmark.circle.fill" accessibilityDescription:clearTitle] ?: [NSImage new];
    _clearButton = [NSButton buttonWithImage:cross target:self action:@selector(clear:)];
    _clearButton.bordered = NO;
    _clearButton.imageScaling = NSImageScaleProportionallyDown;
    _clearButton.contentTintColor = NSColor.tertiaryLabelColor;
    _clearButton.toolTip = clearTitle;
    _clearButton.refusesFirstResponder = YES;
    _clearButton.frame = NSMakeRect(NSWidth(self.bounds) - TSClearInset - TSClearSize, floor((NSHeight(self.bounds) - TSClearSize) / 2), TSClearSize, TSClearSize);
    _clearButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin | NSViewMaxYMargin;
    [self addSubview:_clearButton];
    self.focusRingType = NSFocusRingTypeExterior;
    [self update];
    return self;
}

- (CGFloat)minimumWidth
{
    NSDictionary *attributes = @{NSFontAttributeName: self.display.font ?: [NSFont systemFontOfSize:NSFont.systemFontSize]};
    CGFloat text = ceil([self.placeholder sizeWithAttributes:attributes].width);
    // The text stays centered between ⊗ and the same room on the other side.
    return MAX(120, text + 2 * (TSClearInset + TSClearSize + 6));
}

- (void)update
{
    self.display.enabled = self.enabled;
    self.display.stringValue = self.recording ? @"" : self.shortcut;
    self.display.placeholderString = self.recording ? self.placeholder : @"";
    self.clearButton.hidden = !(self.enabled && self.shortcut.length > 0);
    self.needsDisplay = YES;
    [self noteFocusRingMaskChanged];
}

- (void)setShortcut:(NSString *)shortcut
{
    _shortcut = [shortcut copy] ?: @"";
    [self update];
}

- (void)setEnabled:(BOOL)enabled
{
    _enabled = enabled;
    if (!enabled)
        [self endRecording];
    [self update];
}

- (void)setRecording:(BOOL)recording
{
    _recording = recording;
    if (recording && !self.keyMonitor) {
        __weak typeof(self) weakSelf = self;
        self.keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
            TSMacroShortcutField *field = weakSelf;
            if (field.recording && event.window == field.window && field.window.firstResponder == field) {
                [field handleKey:event];
                return nil;
            }
            return event;
        }];
    } else if (!recording && self.keyMonitor) {
        [NSEvent removeMonitor:self.keyMonitor];
        self.keyMonitor = nil;
    }
    [self update];
}

- (void)dealloc
{
    if (_keyMonitor)
        [NSEvent removeMonitor:_keyMonitor];
}

#pragma mark Recording

- (BOOL)acceptsFirstResponder { return self.enabled; }
- (BOOL)canBecomeKeyView { return self.enabled && !self.isHiddenOrHasHiddenAncestor; }
- (BOOL)becomeFirstResponder
{
    if (![super becomeFirstResponder])
        return NO;
    self.recording = YES;
    return YES;
}
- (BOOL)resignFirstResponder
{
    if (![super resignFirstResponder])
        return NO;
    self.recording = NO;
    return YES;
}

- (void)beginRecording
{
    if (self.enabled)
        [self.window makeFirstResponder:self];
}

- (void)endRecording
{
    if (self.window.firstResponder == self)
        [self.window makeFirstResponder:nil];
    self.recording = NO;
}

- (NSView *)hitTest:(NSPoint)point
{
    NSView *hit = [super hitTest:point];
    if (hit == nil || hit == self.clearButton)
        return hit;
    return self;
}

- (void)mouseDown:(NSEvent *)event
{
    [self beginRecording];
}

- (void)clear:(id)sender
{
    if (self.enabled && self.clearShortcut)
        self.clearShortcut();
    [self endRecording];
}

/// Escape keeps the shortcut, Tab moves on, Delete removes it; any other key may become it.
- (BOOL)handleKey:(NSEvent *)event
{
    NSString *key = event.charactersIgnoringModifiers;
    unichar c = key.length == 1 ? [key characterAtIndex:0] : 0;
    NSEventModifierFlags flags = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift);
    if (c == 27 && !flags) {
        [self endRecording];
        return YES;
    }
    if ((c == '\t' || c == 25) && !(flags & ~NSEventModifierFlagShift)) {
        if (c == 25 || (flags & NSEventModifierFlagShift))
            [self.window selectPreviousKeyView:self];
        else
            [self.window selectNextKeyView:self];
        return YES;
    }
    if ((c == 127 || c == NSDeleteFunctionKey || c == 8) && !flags) {
        [self clear:nil];
        return YES;
    }
    if ((c == '\r' || c == 3) && !flags) {
        [self endRecording];
        return YES;
    }
    if (self.recordEvent && self.recordEvent(event))
        [self endRecording];
    else
        NSBeep();
    return YES;
}

- (void)keyDown:(NSEvent *)event
{
    if (self.recording)
        [self handleKey:event];
    else
        [super keyDown:event];
}

/// Shortcuts with Command reach the window before the menus: the field takes them while it waits.
- (BOOL)performKeyEquivalent:(NSEvent *)event
{
    if (self.recording && self.window.firstResponder == self)
        return [self handleKey:event];
    return [super performKeyEquivalent:event];
}

#pragma mark Focus ring

- (NSRect)focusRingMaskBounds
{
    return self.display.frame;
}

- (void)drawFocusRingMask
{
    NSRect frame = self.display.frame;
    CGFloat radius = MIN(6, NSHeight(frame) / 2);
    [[NSBezierPath bezierPathWithRoundedRect:frame xRadius:radius yRadius:radius] fill];
}

#pragma mark Accessibility

- (BOOL)isAccessibilityElement { return YES; }
- (NSAccessibilityRole)accessibilityRole { return NSAccessibilityButtonRole; }
- (id)accessibilityValue { return self.recording ? self.placeholder : self.shortcut; }
- (BOOL)isAccessibilityEnabled { return self.enabled; }
- (NSString *)accessibilityHelp { return self.placeholder; }
- (BOOL)accessibilityPerformPress
{
    [self beginRecording];
    return self.enabled;
}

@end
