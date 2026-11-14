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
// A build version with a letter, such as 5.60b10, is a prerelease.
+ (BOOL)isPrereleaseVersion:(nullable NSString *)version;
// Prereleases are off by default. The first launch of each prerelease build turns them on.
+ (void)preparePrereleaseDefaultsForVersion:(nullable NSString *)version defaults:(NSUserDefaults *)defaults;
+ (NSSet<NSString *> *)allowedChannelsWithDefaults:(NSUserDefaults *)defaults;
@end

NS_ASSUME_NONNULL_END
