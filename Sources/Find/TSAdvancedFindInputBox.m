// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSAdvancedFindInputBox.h"

/// The symbol followed by a small chevron, as one template image: it says "this opens a menu".
static NSImage *TSMenuSymbol(NSString *name, NSString *description)
{
    NSImageSymbolConfiguration *large = [NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightRegular];
    NSImageSymbolConfiguration *small = [NSImageSymbolConfiguration configurationWithPointSize:9 weight:NSFontWeightSemibold];
    NSImage *symbol = [[NSImage imageWithSystemSymbolName:name accessibilityDescription:description] imageWithSymbolConfiguration:large] ?: [NSImage new];
    NSImage *chevron = [[NSImage imageWithSystemSymbolName:@"chevron.down" accessibilityDescription:nil] imageWithSymbolConfiguration:small] ?: [NSImage new];
    NSSize size = NSMakeSize(symbol.size.width + 3 + chevron.size.width, MAX(symbol.size.height, chevron.size.height));
    NSImage *image = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [symbol drawInRect:NSMakeRect(0, (size.height - symbol.size.height) / 2, symbol.size.width, symbol.size.height)];
        [chevron drawInRect:NSMakeRect(symbol.size.width + 3, (size.height - chevron.size.height) / 2, chevron.size.width, chevron.size.height)];
        return YES;
    }];
    image.template = YES;
    image.accessibilityDescription = description;
    return image;
}

@implementation TSAdvancedFindInputBox

- (instancetype)initWithTextView:(NSTextView *)textView symbolName:(NSString *)symbolName historyTitle:(NSString *)historyTitle
{
    if (!(self = [super initWithFrame:NSMakeRect(0, 0, 400, 60)]))
        return nil;
    _textView = textView;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;

    _historyButton = [NSButton buttonWithImage:TSMenuSymbol(symbolName, historyTitle) target:nil action:NULL];
    _historyButton.bordered = NO;
    _historyButton.toolTip = historyTitle;
    _historyButton.contentTintColor = NSColor.secondaryLabelColor;

    NSImage *clear = [NSImage imageWithSystemSymbolName:@"xmark.circle.fill" accessibilityDescription:nil] ?: [NSImage new];
    _clearButton = [NSButton buttonWithImage:clear target:self action:@selector(clear:)];
    _clearButton.bordered = NO;
    _clearButton.contentTintColor = NSColor.tertiaryLabelColor;
    _clearButton.hidden = YES;
    [_clearButton setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

    _statusLabel = [NSTextField labelWithString:@""];
    _statusLabel.textColor = NSColor.secondaryLabelColor;
    _statusLabel.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    [_statusLabel setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_statusLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 300, 50)];
    scroll.drawsBackground = NO;
    scroll.borderType = NSNoBorder;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.documentView = textView;
    textView.drawsBackground = NO;

    for (NSView *view in @[scroll, _historyButton, _statusLabel, _clearButton]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:view];
    }
    // The first line of text, the icon, the status and the clear button share one line at the top.
    [NSLayoutConstraint activateConstraints:@[
        [_historyButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [_historyButton.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
        [scroll.leadingAnchor constraintEqualToAnchor:_historyButton.trailingAnchor constant:4],
        [scroll.topAnchor constraintEqualToAnchor:self.topAnchor constant:4],
        [scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4],
        [scroll.trailingAnchor constraintEqualToAnchor:_statusLabel.leadingAnchor constant:-6],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:_clearButton.leadingAnchor constant:-6],
        [_statusLabel.centerYAnchor constraintEqualToAnchor:_historyButton.centerYAnchor],
        [_clearButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [_clearButton.centerYAnchor constraintEqualToAnchor:_historyButton.centerYAnchor],
        [self.heightAnchor constraintGreaterThanOrEqualToConstant:48],
    ]];
    [self setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
    return self;
}

- (BOOL)wantsUpdateLayer
{
    return YES;
}

/// Colors are read again here, so they follow light and dark.
- (void)updateLayer
{
    __block CGColorRef border = NULL, fill = NULL;
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        border = (self.focused ? [NSColor.keyboardFocusIndicatorColor colorWithAlphaComponent:0.6] : NSColor.separatorColor).CGColor;
        fill = NSColor.textBackgroundColor.CGColor;
    }];
    self.layer.cornerRadius = 7;
    self.layer.borderWidth = self.focused ? 3 : 1;
    self.layer.borderColor = border;
    self.layer.backgroundColor = fill;
}

- (void)setFocused:(BOOL)focused
{
    _focused = focused;
    self.needsDisplay = YES;
}

- (void)textDidChange
{
    self.clearButton.hidden = self.textView.string.length == 0;
}

- (void)clear:(id)sender
{
    NSTextView *textView = self.textView;
    if (![textView shouldChangeTextInRange:NSMakeRange(0, textView.string.length) replacementString:@""])
        return;
    [textView replaceCharactersInRange:NSMakeRange(0, textView.string.length) withString:@""];
    [textView didChangeText];
    [self.window makeFirstResponder:textView];
    [self textDidChange];
}

@end
