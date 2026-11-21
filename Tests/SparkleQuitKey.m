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
    NSDate *start = NSDate.date;
    NSTimer *typist = [NSTimer timerWithTimeInterval:0.3 repeats:YES block:^(NSTimer *timer) {
        if (NSApp.modalWindow == nil) return;
        // Keys are typed into the alert only while it is the key window, as on the user's screen.
        if (!NSApp.modalWindow.isKeyWindow) { if (-start.timeIntervalSinceNow > 3) { alertNotKey = YES; timedOut = YES; [NSApp abortModal]; [timer invalidate]; } return; }
        if (next < keys.count) { NSArray *k = keys[next++]; [NSApp postEvent:Key([k[0] unsignedShortValue], k[1], [k[2] unsignedIntegerValue]) atStart:NO]; return; }
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
