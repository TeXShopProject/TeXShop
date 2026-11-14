// Added by Terada: use the signed application's feed instead of a cached legacy URL.
#import "TSSparkleController.h"
#import "globals.h"

NSString *const TSSparklePrereleaseChannel = @"prerelease";
NSNotificationName const TSSparkleUpdateCheckDidFinishNotification = @"TSSparkleUpdateCheckDidFinishNotification";

static TSSparkleController *mainUpdaterController;

@implementation TSSparkleController
- (void)awakeFromNib
{
    // The channel must be known before the updater starts its first cycle.
    [TSSparkleController preparePrereleaseDefaultsForVersion:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] defaults:SUD];
    updaterDelegate = self;
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
@end
