#import "TSExperimentConsoleController.h"
#import "TSExperimentJob.h"
#import "TSEncodingSupport.h"
#import "globals.h"

@interface TSExperimentConsoleWindow : NSPanel
@property (nonatomic, weak) TSExperimentConsoleController *controller;
@end
@implementation TSExperimentConsoleWindow
- (void)displayConsole:(id)sender { [self.controller toggleFromWindow:self]; }
- (void)associatedWindow:(id)sender { [self.controller toggleFromWindow:self]; }
- (void)doTypeset:(id)sender { if (self.controller.typesetHandler) self.controller.typesetHandler(); }
- (void)abort:(id)sender { [self.controller abort:sender]; }
- (void)resignKeyWindow { [super resignKeyWindow]; self.controller.returnWindow = nil; }
@end

@interface TSExperimentConsoleController ()
@property (nonatomic, strong) TSExperimentJob *job;
@property (nonatomic, strong) NSTextView *outputText;
@property (nonatomic, strong) NSTextField *commandField;
@property (nonatomic, strong) NSButton *stopButton;
@property (nonatomic, strong) NSURL *directory;
@property (nonatomic, strong) NSData *carry;
@property (nonatomic) NSStringEncoding encoding;
@property (nonatomic) NSUInteger generation;
@end

@implementation TSExperimentConsoleController
- (instancetype)init { return [super initWithWindow:nil]; }

- (void)loadWindow
{
    TSExperimentConsoleWindow *window = [[TSExperimentConsoleWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 640, 360)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    window.controller = self;
    window.releasedWhenClosed = NO;
    window.hidesOnDeactivate = YES;
    window.minSize = NSMakeSize(420, 220);
    NSView *content = window.contentView;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(12, 54, 616, 294)];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    NSTextView *text = [[NSTextView alloc] initWithFrame:scroll.contentView.bounds];
    text.editable = NO;
    text.richText = NO;
    text.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    text.textColor = NSColor.textColor;
    text.backgroundColor = NSColor.textBackgroundColor;
    text.verticallyResizable = YES;
    text.autoresizingMask = NSViewWidthSizable;
    text.textContainer.widthTracksTextView = YES;
    text.textContainer.containerSize = NSMakeSize(scroll.contentSize.width, CGFLOAT_MAX);
    scroll.documentView = text;
    [content addSubview:scroll];
    self.outputText = text;
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 15, 506, 24)];
    field.autoresizingMask = NSViewWidthSizable;
    field.target = self;
    field.action = @selector(sendCommand:);
    field.placeholderString = NSLocalizedString(@"Experiment input", @"Experiment console input placeholder");
    field.accessibilityLabel = field.placeholderString;
    [content addSubview:field];
    self.commandField = field;
    NSButton *stop = [NSButton buttonWithTitle:NSLocalizedString(@"Stop Experiment", @"Stop Experiment job")
                                      target:self action:@selector(abort:)];
    [stop sizeToFit];
    CGFloat width = MAX(100, stop.frame.size.width);
    stop.frame = NSMakeRect(628 - width, 12, width, 30);
    field.frame = NSMakeRect(12, 15, 604 - width, 24);
    stop.autoresizingMask = NSViewMinXMargin;
    [content addSubview:stop];
    self.stopButton = stop;
    self.window = window;
    [window center];
}

- (void)appendText:(NSString *)text
{
    if (!text.length) return;
    NSAttributedString *addition = [[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName:self.outputText.font, NSForegroundColorAttributeName:NSColor.textColor}];
    [self.outputText.textStorage appendAttributedString:addition];
    [self.outputText scrollRangeToVisible:NSMakeRange(self.outputText.string.length, 0)];
}

- (void)appendData:(NSData *)data atEnd:(BOOL)atEnd
{
    NSMutableData *joined = [NSMutableData dataWithData:self.carry ?: NSData.data];
    if (data) [joined appendData:data];
    NSUInteger incomplete = atEnd ? 0 : [TSEncodingSupport lengthOfIncompleteCharacterAtEndOfData:joined encoding:self.encoding];
    NSUInteger ready = joined.length - incomplete;
    self.carry = incomplete ? [joined subdataWithRange:NSMakeRange(ready, incomplete)] : nil;
    if (ready) [self appendText:[TSEncodingSupport displayStringForData:[joined subdataWithRange:NSMakeRange(0, ready)] encoding:self.encoding]];
    // Release complete ambiguous bytes at a paused prompt, but retain partial characters.
    if (incomplete) {
        NSUInteger generation = self.generation;
        NSData *carry = self.carry;
        __weak TSExperimentConsoleController *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            TSExperimentConsoleController *controller = weakSelf;
            if (!controller || controller.generation != generation || controller.carry != carry) return;
            NSUInteger unfinished = [TSEncodingSupport lengthOfUnfinishedCharacterAtEndOfData:carry encoding:controller.encoding];
            if (carry.length > unfinished) {
                [controller appendText:[TSEncodingSupport displayStringForData:[carry subdataWithRange:NSMakeRange(0, carry.length - unfinished)] encoding:controller.encoding]];
                controller.carry = unfinished ? [carry subdataWithRange:NSMakeRange(carry.length - unfinished, unfinished)] : nil;
            }
        });
    }
}

- (void)removeDirectory
{
    if (self.directory) [[NSFileManager defaultManager] removeItemAtURL:self.directory error:NULL];
    self.directory = nil;
}

- (void)startExecutable:(NSString *)path arguments:(NSArray<NSString *> *)arguments
           environment:(NSDictionary<NSString *,NSString *> *)environment
             directory:(NSURL *)directory encoding:(NSStringEncoding)encoding title:(NSString *)title
            completion:(void (^)(NSURL *))completion
{
    [self abort:nil];
    self.directory = directory;
    self.encoding = encoding;
    self.carry = nil;
    self.window.title = [NSString stringWithFormat:NSLocalizedString(@"%@ — Experiment Console", @"Experiment console title"), title];
    self.outputText.string = @"";
    self.commandField.stringValue = @"";
    self.commandField.enabled = YES;
    self.stopButton.enabled = YES;
    [self.window makeFirstResponder:self.commandField];
    if (![SUD boolForKey:ConsoleBehaviorKey]) {
        if ([SUD boolForKey:BringPdfFrontOnTypesetKey]) [self.window makeKeyAndOrderFront:nil];
        else [self.window orderFront:nil];
    } else if (!self.window.isVisible) {
        [self.window orderBack:nil];
    }
    NSUInteger generation = self.generation;
    TSExperimentJob *job = [[TSExperimentJob alloc] init];
    self.job = job;
    __weak TSExperimentConsoleController *weakSelf = self;
    job.outputHandler = ^(NSData *data) {
        TSExperimentConsoleController *controller = weakSelf;
        if (controller.generation == generation) [controller appendData:data atEnd:NO];
    };
    job.completionHandler = ^(int status) {
        TSExperimentConsoleController *controller = weakSelf;
        if (!controller || controller.generation != generation) return;
        [controller appendData:nil atEnd:YES];
        controller.commandField.enabled = NO;
        controller.stopButton.enabled = NO;
        if ((status == 0 || status == 1) && completion)
            completion([directory URLByAppendingPathComponent:@"file.pdf"]);
        [controller removeDirectory];
    };
    NSError *error = nil;
    if (![job startExecutable:path arguments:arguments environment:environment directory:directory error:&error]) {
        [self appendText:[NSString stringWithFormat:@"%@\n", error.localizedDescription ?: NSLocalizedString(@"Typesetting engine cannot be found.", nil)]];
        self.commandField.enabled = NO;
        self.stopButton.enabled = NO;
        [self removeDirectory];
        [self.window makeKeyAndOrderFront:nil];
    }
}

- (void)sendCommand:(id)sender
{
    NSString *command = [self.commandField.stringValue stringByAppendingString:@"\n"];
    if (g_shouldFilter == kMacJapaneseFilterMode) command = filterYenToBackslash(command);
    NSData *data = [[TSEncodingSupport sharedInstance] dataForText:command encoding:self.encoding byteOrderMark:TSNoByteOrderMark];
    NSError *error = nil;
    if ([self.job sendData:data error:&error]) {
        [self appendText:command];
        self.commandField.stringValue = @"";
    } else {
        NSBeep();
        if (error) [self appendText:[error.localizedDescription stringByAppendingString:@"\n"]];
    }
}

- (void)toggleFromWindow:(NSWindow *)origin
{
    if (self.window.isKeyWindow) {
        NSWindow *target = self.returnWindow;
        self.returnWindow = nil;
        if (target != self.window && (target.isVisible || target.isMiniaturized)) [target makeKeyAndOrderFront:nil];
        else if (self.returnHandler) self.returnHandler();
    } else {
        self.returnWindow = origin;
        [self.window makeKeyAndOrderFront:nil];
    }
}

- (void)abort:(id)sender
{
    self.generation++;
    BOOL active = self.job.active;
    [self.job cancel];
    self.job = nil;
    if (self.isWindowLoaded) {
        [self appendData:nil atEnd:YES];
        if (active && sender) [self appendText:NSLocalizedString(@"Experiment stopped.\n", @"Experiment stopped message")];
        self.commandField.enabled = NO;
        self.stopButton.enabled = NO;
    }
    [self removeDirectory];
}

- (void)invalidate
{
    [self abort:nil];
    self.typesetHandler = nil;
    self.returnHandler = nil;
    self.returnWindow = nil;
    [self close];
}
- (void)dealloc
{
    [_job cancel];
    if (_directory) [[NSFileManager defaultManager] removeItemAtURL:_directory error:NULL];
}
@end
