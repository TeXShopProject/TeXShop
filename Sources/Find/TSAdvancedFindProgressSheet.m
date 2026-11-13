// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSAdvancedFindProgressSheet.h"
#import "TSAdvancedFindTask.h"
#import "TSAdvancedFindController.h"

#define TSLocalized TSAdvancedFindLocalized

@interface TSAdvancedFindProgressSheet ()
@property (nonatomic, weak) TSAdvancedFindTask *task;
@property (nonatomic, strong, nullable) NSTimer *timer;
@property (nonatomic, weak, nullable) NSWindow *parent;
@end

@implementation TSAdvancedFindProgressSheet

- (instancetype)initWithTask:(TSAdvancedFindTask *)task
{
    if (!(self = [super init]))
        return nil;
    _task = task;
    _window = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 300, 80) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    _window.releasedWhenClosed = NO;

    NSTextField *title = [NSTextField labelWithString:task.title];
    // Every part in the small size, as the panel's options (the user's choice).
    title.font = [NSFont boldSystemFontOfSize:NSFont.smallSystemFontSize];
    _progressBar = [NSProgressIndicator new];
    _progressBar.style = NSProgressIndicatorStyleBar;
    _progressBar.controlSize = NSControlSizeSmall;
    _progressBar.minValue = 0;
    _progressBar.maxValue = 1;
    _messageField = [NSTextField labelWithString:@" "];
    _messageField.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _messageField.textColor = NSColor.secondaryLabelColor;
    _messageField.lineBreakMode = NSLineBreakByTruncatingTail;
    [_messageField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    // Cancel is an × right of the bar, as in CotEditor; Escape presses it.
    NSString *cancelTitle = TSLocalized(@"AdvancedFind.Cancel", @"Cancel");
    NSImageSymbolConfiguration *symbolSize = [NSImageSymbolConfiguration configurationWithPointSize:NSFont.systemFontSize weight:NSFontWeightRegular];
    NSImage *cross = [[NSImage imageWithSystemSymbolName:@"xmark.circle.fill" accessibilityDescription:cancelTitle] imageWithSymbolConfiguration:symbolSize] ?: [NSImage new];
    _cancelButton = [NSButton buttonWithImage:cross target:self action:@selector(cancel:)];
    _cancelButton.bordered = NO;
    _cancelButton.title = @""; // the image only (the symbol's description is for VoiceOver)
    _cancelButton.imagePosition = NSImageOnly;
    _cancelButton.contentTintColor = NSColor.secondaryLabelColor;
    _cancelButton.toolTip = cancelTitle;
    _cancelButton.keyEquivalent = @"\e";
    _cancelButton.controlSize = NSControlSizeSmall;
    [_cancelButton setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *bar = [NSStackView stackViewWithViews:@[_progressBar, _cancelButton]];
    bar.spacing = 10;
    bar.alignment = NSLayoutAttributeCenterY;

    NSStackView *content = [NSStackView stackViewWithViews:@[title, bar, _messageField]];
    content.orientation = NSUserInterfaceLayoutOrientationVertical;
    content.alignment = NSLayoutAttributeLeading;
    content.spacing = 6;
    content.edgeInsets = NSEdgeInsetsMake(16, 20, 16, 20);
    [content setCustomSpacing:8 afterView:title];
    for (NSView *view in @[bar, _messageField])
        [view.widthAnchor constraintEqualToAnchor:content.widthAnchor constant:-40].active = YES;
    [content.widthAnchor constraintEqualToConstant:300].active = YES;
    _window.contentView = content;
    [content layoutSubtreeIfNeeded];
    [_window setContentSize:content.fittingSize];
    [self update];
    return self;
}

- (void)update
{
    TSAdvancedFindTask *task = self.task;
    double progress = task ? task.progress : -1;
    BOOL indeterminate = progress < 0;
    if (self.progressBar.indeterminate != indeterminate) {
        self.progressBar.indeterminate = indeterminate;
        if (indeterminate)
            [self.progressBar startAnimation:nil];
        else
            [self.progressBar stopAnimation:nil];
    }
    if (!indeterminate)
        self.progressBar.doubleValue = progress;
    NSString *message = task.isCancelled ? TSLocalized(@"AdvancedFind.Cancelling", @"Cancelling…") : task.message;
    self.messageField.stringValue = message.length > 0 ? message : @" ";
    self.cancelButton.enabled = !task.isCancelled;
}

- (void)beginOnWindow:(NSWindow *)window
{
    self.parent = window;
    [self update];
    __weak typeof(self) weakSelf = self;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) { [weakSelf update]; }];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSModalPanelRunLoopMode];
    self.timer = timer;
    [window beginSheet:self.window completionHandler:nil];
}

- (void)end
{
    [self.timer invalidate];
    self.timer = nil;
    [self.progressBar stopAnimation:nil];
    if (self.parent)
        [self.parent endSheet:self.window];
    self.parent = nil;
}

- (void)cancel:(id)sender
{
    [self.task cancel];
    [self update];
}

@end
