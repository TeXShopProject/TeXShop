// The question whether updates are checked automatically: when it is asked, its texts and its answer.
// The alert is built but never shown. Run with -AppleLanguages "(xx)" to choose the language.
#import <Cocoa/Cocoa.h>
#import "TSUpdatePermissionAlert.h"

static int failures;

static void Check(BOOL ok, NSString *what)
{
    if (ok) printf("ok: %s\n", what.UTF8String);
    else { failures++; fprintf(stderr, "FAIL: %s\n", what.UTF8String); }
}

// As SPUUpdater: automatic downloads can be turned on only while automatic checks are on.
@interface FakeUpdater : NSObject <TSUpdatePermissionTarget>
@property (nonatomic) BOOL automaticallyChecksForUpdates;
@property (nonatomic) BOOL automaticallyDownloadsUpdates;
@property (nonatomic) int resets;
@end
@implementation FakeUpdater
- (void)setAutomaticallyChecksForUpdates:(BOOL)checks
{
    _automaticallyChecksForUpdates = checks;
    if (!checks) _automaticallyDownloadsUpdates = NO;
}
- (void)setAutomaticallyDownloadsUpdates:(BOOL)downloads
{
    if (self.automaticallyChecksForUpdates) _automaticallyDownloadsUpdates = downloads;
}
- (void)resetUpdateCycle { self.resets++; }
@end

static BOOL Trimmed(NSString *s)
{
    return s.length > 0 && [[s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] isEqualToString:s];
}

int main(int argc, const char **argv)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *language = [NSUserDefaults.standardUserDefaults stringArrayForKey:@"AppleLanguages"].firstObject ?: @"en";
        NSString *expectFile = [NSUserDefaults.standardUserDefaults stringForKey:@"ExpectFile"];
        NSBundle *app = [NSBundle bundleWithPath:[NSUserDefaults.standardUserDefaults stringForKey:@"Interfaces"]];
        NSBundle *appWithoutDownloads = [NSBundle bundleWithPath:[NSUserDefaults.standardUserDefaults stringForKey:@"InterfacesWithoutDownloads"]];
        NSBundle *sparkle = [NSBundle bundleWithPath:[NSUserDefaults.standardUserDefaults stringForKey:@"Sparkle"]];

        // When it is asked.
        NSDictionary *cases = @{@"first launch": @[@{}, @NO],
                                @"second launch": @[@{@"SUHasLaunchedBefore": @YES}, @YES],
                                @"answered yes": @[@{@"SUHasLaunchedBefore": @YES, @"SUEnableAutomaticChecks": @YES}, @NO],
                                @"answered no": @[@{@"SUHasLaunchedBefore": @YES, @"SUEnableAutomaticChecks": @NO}, @NO]};
        for (NSString *name in cases) {
            Check([TSUpdatePermissionAlert shouldAskWithDefaults:cases[name][0]] == [cases[name][1] boolValue], [@"asked: " stringByAppendingString:name]);
        }

        // Texts.
        FakeUpdater *updater = [FakeUpdater new];
        __block int completions = 0;
        TSUpdatePermissionAlert *permission = [[TSUpdatePermissionAlert alloc] initWithTarget:updater appBundle:app sparkleBundle:sparkle downloadsOn:NO completion:^{ completions++; }];
        NSAlert *alert = permission.alert;
        NSArray<NSString *> *texts = @[alert.messageText, alert.informativeText, alert.buttons[0].title, alert.buttons[1].title, permission.downloadsCheckbox.title];
        for (NSString *text in texts)
            Check(Trimmed(text), [NSString stringWithFormat:@"%@: no surrounding spaces in \"%@\"", language, text]);
        Check([alert.informativeText containsString:@"TeXShop"] || [alert.informativeText containsString:@"UpdatePermissionTest"], [language stringByAppendingString:@": the application is named"]);
        // Sparkle's own translations, as in a language TeXShop has no text of its own for.
        NSBundle *none = [NSBundle bundleWithPath:NSTemporaryDirectory()];
        for (NSString *key in @[@"Check for updates automatically?", @"Should %1$@ automatically check for updates? You can always check for updates manually from the %1$@ menu.", @"Check Automatically", @"Don’t Check", @"Automatically download and install updates"])
            Check(Trimmed([TSUpdatePermissionAlert textForKey:@"UpdatePermissionNone" sparkleKey:key appBundle:none sparkleBundle:sparkle]), [NSString stringWithFormat:@"%@: Sparkle's text trimmed: %@", language, key]);
        Check(![alert.informativeText containsString:@"%"], [language stringByAppendingString:@": no format left"]);
        if (expectFile) {
            NSArray *expected = [NSArray arrayWithContentsOfFile:expectFile];
            Check([texts isEqualToArray:expected], [NSString stringWithFormat:@"%@: texts %@", language, [texts componentsJoinedByString:@" | "]]);
        }
        Check([alert.buttons[0].keyEquivalent isEqualToString:@"\r"], @"Return checks automatically");
        Check([alert.buttons[1].keyEquivalent isEqualToString:@"\e"], @"Escape does not check");
        Check(alert.accessoryView == permission.downloadsCheckbox, @"the download checkbox is shown while automatic checks are still off");
        Check(permission.downloadsCheckbox.state == NSControlStateValueOff, @"the box starts off");

        // Answers, as Sparkle's window gives them.
        permission.downloadsCheckbox.state = NSControlStateValueOn;
        [alert.buttons[0] sendAction:alert.buttons[0].action to:alert.buttons[0].target];
        Check(updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates && updater.resets == 1 && completions == 1, @"Check Automatically with the box on");

        updater = [FakeUpdater new];
        permission = [[TSUpdatePermissionAlert alloc] initWithTarget:updater appBundle:app sparkleBundle:sparkle downloadsOn:YES completion:nil];
        Check(permission.downloadsCheckbox.state == NSControlStateValueOn, @"the box starts from SUAutomaticallyUpdate");
        [permission.alert.buttons[1] sendAction:permission.alert.buttons[1].action to:permission.alert.buttons[1].target];
        Check(!updater.automaticallyChecksForUpdates && !updater.automaticallyDownloadsUpdates && updater.resets == 1, @"Don't Check turns both off");

        updater = [FakeUpdater new];
        permission = [[TSUpdatePermissionAlert alloc] initWithTarget:updater appBundle:appWithoutDownloads sparkleBundle:sparkle downloadsOn:NO completion:nil];
        Check(permission.alert.accessoryView == nil, @"no download checkbox when SUAllowsAutomaticUpdates is NO");
        permission.downloadsCheckbox.state = NSControlStateValueOn;
        [permission.alert.buttons[0] sendAction:permission.alert.buttons[0].action to:permission.alert.buttons[0].target];
        Check(updater.automaticallyChecksForUpdates && !updater.automaticallyDownloadsUpdates, @"downloads untouched when automatic updates are not allowed");
    }
    if (failures) { fprintf(stderr, "%d failure(s)\n", failures); return 1; }
    puts("PASS update permission alert");
    return 0;
}
