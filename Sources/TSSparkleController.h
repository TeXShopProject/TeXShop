// Added by Terada: shared access to the Sparkle 2 updater used by the main menu.
#import <Cocoa/Cocoa.h>
#import <Sparkle/Sparkle.h>
@interface TSSparkleController : SPUStandardUpdaterController <SPUUpdaterDelegate>
+ (SPUUpdater *)sharedUpdater;
@end
