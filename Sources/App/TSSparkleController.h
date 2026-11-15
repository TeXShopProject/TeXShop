// Added by Terada: shared access to the Sparkle 2 updater used by the main menu.
#import <Cocoa/Cocoa.h>
#import <Sparkle/Sparkle.h>

NS_ASSUME_NONNULL_BEGIN

// The appcast channel of prerelease builds.
FOUNDATION_EXPORT NSString *const TSSparklePrereleaseChannel;
// Posted on the main thread when an update check of any kind has finished.
FOUNDATION_EXPORT NSNotificationName const TSSparkleUpdateCheckDidFinishNotification;

@interface TSSparkleController : SPUStandardUpdaterController <SPUUpdaterDelegate>
+ (nullable SPUUpdater *)sharedUpdater;
+ (nullable TSSparkleController *)sharedController;
// A display version with a letter, such as 6.00 beta-1, is a prerelease.
+ (BOOL)isPrereleaseVersion:(nullable NSString *)version;
// The display version (CFBundleShortVersionString) of the bundle.
+ (nullable NSString *)prereleaseVersionOfBundle:(NSBundle *)bundle;
// Prereleases are off by default. The first launch of each prerelease version turns them on;
// later builds of the same version do not.
+ (void)preparePrereleaseDefaultsForBundle:(NSBundle *)bundle defaults:(NSUserDefaults *)defaults;
+ (void)preparePrereleaseDefaultsForVersion:(nullable NSString *)version defaults:(NSUserDefaults *)defaults;
+ (NSSet<NSString *> *)allowedChannelsWithDefaults:(NSUserDefaults *)defaults;
@end

NS_ASSUME_NONNULL_END
