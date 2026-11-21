// Added by Terada: use the signed application's feed instead of a cached legacy URL.
#import "TSSparkleController.h"
#import "globals.h"
#import "TSKeyboardShortcuts.h"

NSString *const TSSparklePrereleaseChannel = @"prerelease";
NSNotificationName const TSSparkleUpdateCheckDidFinishNotification = @"TSSparkleUpdateCheckDidFinishNotification";

static TSSparkleController *mainUpdaterController;

@interface TSSparkleController ()
@property (nonatomic, strong, nullable) id quitKeyMonitor;
@property (nonatomic) BOOL quitRequested;
@end

// The Quit item of the main menu, wherever it is and whatever key it has.
static NSMenuItem *TSQuitMenuItem(NSMenu *menu)
{
    for (NSMenuItem *item in menu.itemArray) {
        if (item.action == @selector(terminate:)) return item;
        NSMenuItem *found = item.submenu ? TSQuitMenuItem(item.submenu) : nil;
        if (found) return found;
    }
    return nil;
}

@implementation TSSparkleController
- (void)awakeFromNib
{
    // The channel must be known before the updater starts its first cycle.
    [TSSparkleController preparePrereleaseDefaultsForBundle:[NSBundle mainBundle] defaults:SUD];
    updaterDelegate = self;
    userDriverDelegate = self;
    mainUpdaterController = self;
    [super awakeFromNib];
}

+ (SPUUpdater *)sharedUpdater
{
    return mainUpdaterController.updater;
}

+ (TSSparkleController *)sharedController
{
    return mainUpdaterController;
}

+ (BOOL)isPrereleaseVersion:(NSString *)version
{
    return version != nil && [version rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location != NSNotFound;
}

// The display version (6.00 beta-1) tells a prerelease; CFBundleVersion is a build number that changes with every build.
+ (NSString *)prereleaseVersionOfBundle:(NSBundle *)bundle
{
    id version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return [version isKindOfClass:NSString.class] ? version : nil;
}

+ (void)preparePrereleaseDefaultsForBundle:(NSBundle *)bundle defaults:(NSUserDefaults *)defaults
{
    [self preparePrereleaseDefaultsForVersion:[self prereleaseVersionOfBundle:bundle] defaults:defaults];
}

+ (void)preparePrereleaseDefaultsForVersion:(NSString *)version defaults:(NSUserDefaults *)defaults
{
    [defaults registerDefaults:@{SparklePrereleaseUpdatesKey: @NO}];
    if (![self isPrereleaseVersion:version]) return;
    if ([[defaults stringForKey:SparklePrereleaseForcedVersionKey] isEqualToString:version]) return;
    [defaults setBool:YES forKey:SparklePrereleaseUpdatesKey];
    [defaults setObject:version forKey:SparklePrereleaseForcedVersionKey];
}

+ (NSSet<NSString *> *)allowedChannelsWithDefaults:(NSUserDefaults *)defaults
{
    return [defaults boolForKey:SparklePrereleaseUpdatesKey] ? [NSSet setWithObject:TSSparklePrereleaseChannel] : [NSSet set];
}

- (NSString *)feedURLStringForUpdater:(SPUUpdater *)updater
{
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SUFeedURL"];
}

- (NSSet<NSString *> *)allowedChannelsForUpdater:(SPUUpdater *)updater
{
    return [TSSparkleController allowedChannelsWithDefaults:SUD];
}

- (void)updater:(SPUUpdater *)updater didFinishUpdateCycleForUpdateCheck:(SPUUpdateCheck)updateCheck error:(NSError *)error
{
    [[NSNotificationCenter defaultCenter] postNotificationName:TSSparkleUpdateCheckDidFinishNotification object:self];
}
// Sparkle shows some alerts, such as the one saying that TeXShop is up to date, as app-modal
// alerts, which turn off the menu bar. While one is shown, the key of Quit closes the alert and
// then quits TeXShop, as it does in other applications. Over another modal window, such as a
// panel opened before the update check finished, the key is left alone as in that window.
- (void)standardUserDriverWillShowModalAlert
{
    [self stopQuitKeyMonitor];
    self.quitRequested = NO;
    if (NSApp.modalWindow != nil) return;
    __weak TSSparkleController *weakSelf = self;
    self.quitKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        return [weakSelf quitFromModalAlertWithEvent:event] ? nil : event;
    }];
}

- (void)standardUserDriverDidShowModalAlert
{
    [self stopQuitKeyMonitor];
    BOOL quit = self.quitRequested;
    self.quitRequested = NO;
    // TeXShop quits once the alert is gone, so unsaved documents are asked about as usual.
    if (quit)
        [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0 inModes:@[NSDefaultRunLoopMode]];
}

- (void)stopQuitKeyMonitor
{
    if (self.quitKeyMonitor) [NSEvent removeMonitor:self.quitKeyMonitor];
    self.quitKeyMonitor = nil;
}

- (BOOL)quitFromModalAlertWithEvent:(NSEvent *)event
{
    NSMenuItem *quit = TSQuitMenuItem(NSApp.mainMenu);
    if (NSApp.modalWindow == nil || quit == nil || ![TSShortcutStore event:event matchesItem:quit]) return NO;
    [self stopQuitKeyMonitor];
    // The alert closes as with its default button.
    self.quitRequested = YES;
    [NSApp stopModalWithCode:NSAlertFirstButtonReturn];
    return YES;
}
@end
