// Added by Terada: use the signed application's feed instead of a cached legacy URL.
#import "TSSparkleController.h"

static TSSparkleController *mainUpdaterController;

@implementation TSSparkleController
- (void)awakeFromNib
{
    updaterDelegate = self;
    mainUpdaterController = self;
    [super awakeFromNib];
}

+ (SPUUpdater *)sharedUpdater
{
    return mainUpdaterController.updater;
}

- (NSString *)feedURLStringForUpdater:(SPUUpdater *)updater
{
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SUFeedURL"];
}
@end
