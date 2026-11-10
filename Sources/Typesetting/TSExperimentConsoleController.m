#import "TSConsoleOutput.h"
#import "TSExperimentConsoleController.h"
#import "TSExperimentJob.h"
#import "TSEncodingSupport.h"
#import "globals.h"
#import "TSColorSupport.h"
#import "TSExperimentTheme.h"

@interface TSExperimentConsoleController (Colors)
- (void)updateConsoleColors:(NSNotification *)notification;
@end

@interface TSExperimentConsoleContentView : NSView
@property (nonatomic, weak) TSExperimentConsoleController *controller;
@end
@implementation TSExperimentConsoleContentView
- (void)drawRect:(NSRect)dirtyRect
{
    [NSColor.windowBackgroundColor setFill];
    NSRectFill(dirtyRect);
}
- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
    [self.controller updateConsoleColors:nil];
}
@end

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
- (instancetype)init
{
    self = [super initWithWindow:nil];
    if (self) {
        // initWithWindow:nil does not lazily invoke loadWindow.
        [self loadWindow];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateConsoleFont:)
            name:ConsoleFontChangedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateConsoleColors:)
            name:SourceColorChangedNotification object:nil];
    }
    return self;
}

- (void)updateConsoleFont:(NSNotification *)notification
{
    NSString *name = [SUD stringForKey:ConsoleFontNameKey];
    CGFloat size = [SUD floatForKey:ConsoleFontSizeKey];
    NSFont *font = name.length ? [NSFont fontWithName:name size:size > 0 ? size : 12] : nil;
    self.outputText.font = font ?: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
}

- (void)updateConsoleColors:(NSNotification *)notification
{
    // The content view receives the appearance change before its child text view.
    BOOL dark = [[self.window.contentView.effectiveAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
    TSColorSupport *colors = [TSColorSupport sharedInstance];
    NSDictionary *theme = notification.userInfo ?: (dark ? darkColors : liteColors);
    self.outputText.backgroundColor = [colors colorForKey:@"ConsoleBackground" fromDictionary:theme isWindowDark:dark];
    self.outputText.textColor = [colors colorForKey:@"ConsoleText" fromDictionary:theme isWindowDark:dark];
    self.window.alphaValue = TSThemeWindowAlpha(theme, TSThemeConsoleAlphaKey);
}

- (void)loadWindow
{
    TSExperimentConsoleWindow *window = [[TSExperimentConsoleWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 504, 430)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    window.controller = self;
    window.releasedWhenClosed = NO;
    window.hidesOnDeactivate = YES;
    window.minSize = NSMakeSize(420, 220);
    TSExperimentConsoleContentView *content = [[TSExperimentConsoleContentView alloc] initWithFrame:window.contentView.bounds];
    window.contentView = content;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 55, 504, 343)];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSNoBorder;
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
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 0, 464, 53)];
    field.autoresizingMask = NSViewWidthSizable;
    field.bezelStyle = NSTextFieldRoundedBezel;
    field.focusRingType = NSFocusRingTypeNone;
    field.font = [NSFont systemFontOfSize:11];
    field.target = self;
    field.action = @selector(sendCommand:);
    field.placeholderString = NSLocalizedString(@"Experiment input", @"Experiment console input placeholder");
    field.accessibilityLabel = field.placeholderString;
    [content addSubview:field];
    TSConfigureConsoleInput(field);
    self.commandField = field;
    field.enabled = NO;
    NSButton *stop = [NSButton buttonWithTitle:NSLocalizedString(@"Stop Experiment", @"Stop Experiment job")
                                      target:self action:@selector(abort:)];
    stop.bezelStyle = NSBezelStyleShadowlessSquare;
    [stop sizeToFit];
    CGFloat width = MAX(100, stop.frame.size.width);
    stop.frame = NSMakeRect(504 - width, 398, width, 33);
    stop.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [content addSubview:stop];
    self.stopButton = stop;
    stop.enabled = NO;
    self.window = window;
    content.controller = self;
    [window center];
    [window setFrameAutosaveName:@"ExperimentConsole"];
    [self updateConsoleFont:nil];
    [self updateConsoleColors:nil];
}

- (void)appendText:(NSString *)text
{
    if (!text.length) return;
    NSAttributedString *addition = [[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName:self.outputText.font, NSForegroundColorAttributeName:self.outputText.textColor ?: NSColor.textColor}];
    // Appending keeps any selection; follow the output only when nothing is selected.
    BOOL selecting = TSConsoleHasSelection(self.outputText);
    [self.outputText.textStorage appendAttributedString:addition];
    if (!selecting)
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
    [self startExecutable:path arguments:arguments environment:environment directory:directory
         workingDirectory:directory encoding:encoding title:title completion:completion];
}

- (void)startExecutable:(NSString *)path arguments:(NSArray<NSString *> *)arguments
           environment:(NSDictionary<NSString *,NSString *> *)environment
             directory:(NSURL *)directory workingDirectory:(NSURL *)workingDirectory
              encoding:(NSStringEncoding)encoding title:(NSString *)title
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
    if (![job startExecutable:path arguments:arguments environment:environment directory:workingDirectory ?: directory error:&error]) {
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
    NSString *displayCommand = g_shouldFilter == kMacJapaneseFilterMode ? filterBackslashToYen(command) : command;
    if (g_shouldFilter == kMacJapaneseFilterMode) command = filterYenToBackslash(command);
    NSData *data = [[TSEncodingSupport sharedInstance] dataForText:command encoding:self.encoding byteOrderMark:TSNoByteOrderMark];
    NSError *error = nil;
    if ([self.job sendData:data error:&error]) {
        [self appendText:displayCommand];
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
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_job cancel];
    if (_directory) [[NSFileManager defaultManager] removeItemAtURL:_directory error:NULL];
}
@end
