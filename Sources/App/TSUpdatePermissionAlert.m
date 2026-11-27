#import "TSUpdatePermissionAlert.h"

// A value no translation has, to tell a missing text from a text that equals its key.
static NSString *const TSMissingText = @"TSUpdatePermissionAlert.missing";

@interface TSUpdatePermissionAlert ()
@property (nonatomic, strong) id<TSUpdatePermissionTarget> target;
@property (nonatomic, copy, nullable) void (^completion)(void);
@property (nonatomic) BOOL offersDownloads;
@end

@implementation TSUpdatePermissionAlert

+ (BOOL)shouldAskWithDefaults:(id)defaults
{
    id launched = [defaults objectForKey:@"SUHasLaunchedBefore"];
    return [defaults objectForKey:@"SUEnableAutomaticChecks"] == nil && [launched respondsToSelector:@selector(boolValue)] && [launched boolValue];
}

+ (NSString *)textForKey:(NSString *)key sparkleKey:(NSString *)sparkleKey appBundle:(NSBundle *)appBundle sparkleBundle:(NSBundle *)sparkleBundle
{
    NSString *text = [appBundle localizedStringForKey:key value:TSMissingText table:@"UpdatePermission"];
    if ([text isEqualToString:TSMissingText] || [text isEqualToString:key])
        text = [sparkleBundle localizedStringForKey:sparkleKey value:sparkleKey table:@"Sparkle"];
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

+ (NSString *)applicationNameOfBundle:(NSBundle *)bundle
{
    for (NSString *key in @[@"CFBundleDisplayName", @"CFBundleName"]) {
        id name = [bundle objectForInfoDictionaryKey:key];
        if ([name isKindOfClass:NSString.class] && [name length] > 0) return name;
    }
    return bundle.bundleURL.URLByDeletingPathExtension.lastPathComponent ?: @"TeXShop";
}

+ (BOOL)offersAutomaticDownloadsForBundle:(NSBundle *)bundle
{
    id allows = [bundle objectForInfoDictionaryKey:@"SUAllowsAutomaticUpdates"];
    return ![allows respondsToSelector:@selector(boolValue)] || [allows boolValue];
}

- (instancetype)initWithTarget:(id<TSUpdatePermissionTarget>)target appBundle:(NSBundle *)appBundle sparkleBundle:(NSBundle *)sparkleBundle downloadsOn:(BOOL)downloadsOn completion:(void (^)(void))completion
{
    self = [super init];
    if (!self) return nil;
    _target = target;
    _completion = [completion copy];

    NSString *name = [TSUpdatePermissionAlert applicationNameOfBundle:appBundle];
    NSString *(^text)(NSString *, NSString *) = ^(NSString *key, NSString *sparkleKey) {
        return [TSUpdatePermissionAlert textForKey:key sparkleKey:sparkleKey appBundle:appBundle sparkleBundle:sparkleBundle];
    };

    _alert = [[NSAlert alloc] init];
    _alert.messageText = text(@"UpdatePermissionTitle", @"Check for updates automatically?");
    _alert.informativeText = [NSString stringWithFormat:text(@"UpdatePermissionMessage", @"Should %1$@ automatically check for updates? You can always check for updates manually from the %1$@ menu."), name];
    NSButton *check = [_alert addButtonWithTitle:text(@"UpdatePermissionCheck", @"Check Automatically")];
    NSButton *dontCheck = [_alert addButtonWithTitle:text(@"UpdatePermissionDontCheck", @"Don’t Check")];
    dontCheck.keyEquivalent = @"\e";
    check.tag = 1;
    dontCheck.tag = 0;
    for (NSButton *button in @[check, dontCheck]) {
        button.target = self;
        button.action = @selector(answer:);
    }

    _downloadsCheckbox = [NSButton checkboxWithTitle:text(@"UpdatePermissionDownloads", @"Automatically download and install updates") target:nil action:nil];
    _downloadsCheckbox.state = downloadsOn ? NSControlStateValueOn : NSControlStateValueOff;
    [_downloadsCheckbox sizeToFit];
    _offersDownloads = [TSUpdatePermissionAlert offersAutomaticDownloadsForBundle:appBundle];
    if (_offersDownloads) _alert.accessoryView = _downloadsCheckbox;
    [_alert layout];
    return self;
}

- (void)show
{
    NSWindow *window = self.alert.window;
    window.hidesOnDeactivate = NO;
    window.releasedWhenClosed = NO;
    [window center];
    [window makeKeyAndOrderFront:nil];
}

// The same answer as Sparkle's window gives.
- (void)answer:(NSButton *)sender
{
    BOOL checks = sender.tag == 1;
    id<TSUpdatePermissionTarget> target = self.target;
    // Checks first: Sparkle allows automatic downloads only once checks are on.
    target.automaticallyChecksForUpdates = checks;
    if (self.offersDownloads)
        target.automaticallyDownloadsUpdates = checks && self.downloadsCheckbox.state == NSControlStateValueOn;
    [target resetUpdateCycle];
    [self.alert.window orderOut:nil];
    void (^completion)(void) = self.completion;
    self.completion = nil;
    if (completion) completion();
}
@end
