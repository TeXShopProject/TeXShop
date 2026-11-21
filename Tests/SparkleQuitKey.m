// SPDX-License-Identifier: GPL-2.0-or-later
// Issue #68: the key of Quit closes Sparkle's app-modal alerts (such as "You're up to date")
// and then quits. The probe shows Sparkle's own alerts, so it runs on a test Mac, not here.
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <objc/runtime.h>
#import <Sparkle/Sparkle.h>
#import "TSSparkleController.h"

static int failures;
static NSMutableArray<NSString *> *steps;
static NSInteger terminations;
static BOOL terminatedWhileModal;
static BOOL alertNotKey;
// Before each key: whether the alert had been answered, and whether the window in front was still that alert.
static NSMutableArray<NSArray<NSNumber *> *> *beforeKeys;

static void Check(BOOL ok, NSString *what)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", what.UTF8String);
    if (!ok) failures++;
}

@interface ProbeApplication : NSApplication
@end

@implementation ProbeApplication
- (void)terminate:(id)sender
{
    terminations++;
    if (self.modalWindow != nil) terminatedWhileModal = YES;
    [steps addObject:@"terminate"];
}
@end

static NSMenuItem *quitItem;

static void BuildMenu(void)
{
    NSMenu *main = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *appItem = [main addItemWithTitle:@"TeXShop" action:nil keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"TeXShop"];
    [appMenu addItemWithTitle:@"About TeXShop" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:NSMenuItem.separatorItem];
    quitItem = [appMenu addItemWithTitle:@"Quit TeXShop" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    NSMenuItem *fileItem = [main addItemWithTitle:@"File" action:nil keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
    fileItem.submenu = fileMenu;
    NSApp.mainMenu = main;
}

static NSEvent *Key(unsigned short code, NSString *chars, NSEventModifierFlags flags)
{
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:NSProcessInfo.processInfo.systemUptime
                        windowNumber:NSApp.modalWindow.windowNumber context:nil characters:chars charactersIgnoringModifiers:chars
                           isARepeat:NO keyCode:code];
}

// runMode:beforeDate: returns after the first source it handles, so it is called until the time is up.
static void SpinDefaultMode(NSTimeInterval seconds)
{
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (end.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:end];
}

// Shows a real Sparkle alert and types the given keys into it, one every 0.3 s.
// Returns whether the alert was closed (its acknowledgement ran) before the timeout.
static BOOL RunAlert(id<SPUUserDriver> driver, BOOL error, NSArray *keys)
{
    __block BOOL acknowledged = NO;
    __block NSUInteger next = 0;
    __block BOOL timedOut = NO;
    __block NSWindow *alertWindow = nil;
    NSDate *start = NSDate.date;
    [beforeKeys removeAllObjects];
    NSTimer *typist = [NSTimer timerWithTimeInterval:0.3 repeats:YES block:^(NSTimer *timer) {
        if (NSApp.modalWindow == nil) return;
        // Keys are typed into the alert only while it is the key window, as on the user's screen.
        if (!NSApp.modalWindow.isKeyWindow) { if (-start.timeIntervalSinceNow > 3) { alertNotKey = YES; timedOut = YES; [NSApp abortModal]; [timer invalidate]; } return; }
        if (alertWindow == nil) alertWindow = NSApp.modalWindow;
        if (next < keys.count) { [beforeKeys addObject:@[@(acknowledged), @(NSApp.modalWindow == alertWindow)]]; NSArray *k = keys[next++]; [NSApp postEvent:Key([k[0] unsignedShortValue], k[1], [k[2] unsignedIntegerValue]) atStart:NO]; return; }
        if (-start.timeIntervalSinceNow > 0.3 * keys.count + 3) { timedOut = YES; [NSApp abortModal]; [timer invalidate]; }
    }];
    [NSRunLoop.currentRunLoop addTimer:typist forMode:NSModalPanelRunLoopMode];
    void (^ack)(void) = ^{ acknowledged = YES; [steps addObject:@"acknowledged"]; };
    NSError *problem = [NSError errorWithDomain:SUSparkleErrorDomain code:SUNoUpdateError userInfo:@{NSLocalizedDescriptionKey: @"You're up to date!"}];
    if (error) [driver showUpdaterError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUAppcastError userInfo:@{NSLocalizedDescriptionKey: @"Update Error!"}] acknowledgement:ack];
    else [driver showUpdateNotFoundWithError:problem acknowledgement:ack];
    [typist invalidate];
    // TeXShop quits once the alert is gone and the application is back in its default mode.
    SpinDefaultMode(0.5);
    return acknowledged && !timedOut;
}

static void Reset(void)
{
    [steps removeAllObjects];
    terminations = 0;
    terminatedWhileModal = NO;
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        steps = [NSMutableArray array];
        beforeKeys = [NSMutableArray array];
        [ProbeApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp finishLaunching];
        BuildMenu();

        // The application's controller makes itself the delegate of Sparkle's user driver.
        Method awake = class_getInstanceMethod(SPUStandardUpdaterController.class, @selector(awakeFromNib));
        IMP original = method_setImplementation(awake, imp_implementationWithBlock(^(id me) {}));
        TSSparkleController *fromNib = [TSSparkleController alloc];
        [fromNib awakeFromNib];
        method_setImplementation(awake, original);
        Ivar delegateIvar = class_getInstanceVariable(SPUStandardUpdaterController.class, "userDriverDelegate");
        Check(delegateIvar && object_getIvar(fromNib, delegateIvar) == fromNib, @"awakeFromNib makes the controller the delegate of the user driver");

        TSSparkleController *controller = [[TSSparkleController alloc] initWithStartingUpdater:NO updaterDelegate:nil userDriverDelegate:nil];
        SPUStandardUserDriver *driver = [[SPUStandardUserDriver alloc] initWithHostBundle:NSBundle.mainBundle delegate:controller];
        NSArray *commandQ = @[@(kVK_ANSI_Q), @"q", @(NSEventModifierFlagCommand)];
        NSArray *optionCommandQ = @[@(kVK_ANSI_Q), @"q", @(NSEventModifierFlagCommand | NSEventModifierFlagOption)];
        NSArray *commandW = @[@(kVK_ANSI_W), @"w", @(NSEventModifierFlagCommand)];
        NSArray *plainQ = @[@(kVK_ANSI_Q), @"q", @0];
        NSArray *returnKey = @[@(kVK_Return), @"\r", @0];

        Reset();
        BOOL closed = RunAlert(driver, NO, @[commandQ]);
        Check(closed, @"Command-Q closes the up-to-date alert");
        Check(terminations == 1, [NSString stringWithFormat:@"Command-Q in the up-to-date alert quits once (%ld)", (long)terminations]);
        Check(!terminatedWhileModal && [steps isEqual:@[@"acknowledged", @"terminate"]],
              [NSString stringWithFormat:@"TeXShop quits after the alert is gone (%@)", [steps componentsJoinedByString:@" "]]);
        Check([controller valueForKey:@"quitKeyMonitor"] == nil, @"no key monitor is left after the alert");

        Reset();
        closed = RunAlert(driver, YES, @[commandQ]);
        Check(closed && terminations == 1 && !terminatedWhileModal, @"Command-Q closes an update error alert and quits");

        Reset();
        closed = RunAlert(driver, NO, @[commandW, plainQ, returnKey]);
        Check(closed, @"other keys reach the alert, Return closes it");
        Check(terminations == 0, @"Command-W, Q and Return do not quit");
        Check([controller valueForKey:@"quitKeyMonitor"] == nil, @"no key monitor is left after the alert is closed with Return");

        // The key of Quit is the one the menu item has, as set in Settings > Keyboard.
        quitItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
        Reset();
        closed = RunAlert(driver, NO, @[commandQ, returnKey]);
        Check(closed && terminations == 0, @"Command-Q does not quit when Quit has Option-Command-Q");
        Reset();
        closed = RunAlert(driver, NO, @[optionCommandQ]);
        Check(closed && terminations == 1 && !terminatedWhileModal, @"Option-Command-Q quits when Quit has Option-Command-Q");
        quitItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;

        // Without a key for Quit nothing quits.
        quitItem.keyEquivalent = @"";
        Reset();
        closed = RunAlert(driver, NO, @[commandQ, returnKey]);
        Check(closed && terminations == 0, @"Command-Q does not quit when Quit has no key");
        quitItem.keyEquivalent = @"q";

        // Over another modal window, such as a panel opened before the update check finished, the
        // key is left alone: the alert stays until Return, and nothing quits when the panel closes.
        Reset();
        NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(200, 200, 320, 160) styleMask:NSWindowStyleMaskTitled
                                                      backing:NSBackingStoreBuffered defer:NO];
        __block BOOL nestedClosed = NO;
        __block NSInteger nestedAcks = 0;
        __block NSArray *nestedBeforeReturn = nil;
        NSTimer *inner = [NSTimer timerWithTimeInterval:0.3 repeats:NO block:^(NSTimer *timer) {
            nestedClosed = RunAlert(driver, NO, @[commandQ, returnKey]);
            nestedBeforeReturn = beforeKeys.count > 1 ? beforeKeys[1] : nil;
            nestedAcks = [steps filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF == 'acknowledged'"]].count;
            [NSApp stopModal];
        }];
        [NSRunLoop.currentRunLoop addTimer:inner forMode:NSModalPanelRunLoopMode];
        [NSApp runModalForWindow:panel];
        [panel orderOut:nil];
        SpinDefaultMode(0.5);
        Check([nestedBeforeReturn isEqual:@[@NO, @YES]], [NSString stringWithFormat:@"over a modal panel the alert is still open and unanswered after Command-Q (answered, same alert: %@)", [nestedBeforeReturn componentsJoinedByString:@", "]]);
        Check(nestedClosed && nestedAcks == 1, @"over a modal panel Return then closes the alert, once");
        Check(terminations == 0, [NSString stringWithFormat:@"over a modal panel Command-Q does not quit, also after the panel closes (%ld)", (long)terminations]);
        Check([controller valueForKey:@"quitKeyMonitor"] == nil, @"no key monitor is left after the alert over a modal panel");

        // After the alert, Command-Q is the menu's again.
        Reset();
        NSEvent *after = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand timestamp:0
                                     windowNumber:0 context:nil characters:@"q" charactersIgnoringModifiers:@"q" isARepeat:NO keyCode:kVK_ANSI_Q];
        [NSApp sendEvent:after];
        SpinDefaultMode(0.5);
        Check(terminations == 1, [NSString stringWithFormat:@"Command-Q without an alert quits once through the menu (%ld)", (long)terminations]);
    }
    Check(!alertNotKey, @"every alert became the key window (the probe is started with open)");
    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures ? 1 : 0;
}
