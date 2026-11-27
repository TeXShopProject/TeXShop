// The question whether TeXShop checks for updates automatically, as a standard alert in place of Sparkle's own window.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// The part of SPUUpdater that the answer changes.
@protocol TSUpdatePermissionTarget <NSObject>
@property (nonatomic) BOOL automaticallyChecksForUpdates;
@property (nonatomic) BOOL automaticallyDownloadsUpdates;
- (void)resetUpdateCycle;
@end

@interface TSUpdatePermissionAlert : NSObject
// Sparkle asks on the second launch, as long as the question has not been answered.
// The values are read with objectForKey: (the user defaults, or a dictionary).
+ (BOOL)shouldAskWithDefaults:(id)defaults;
// The text of TeXShop's table UpdatePermission.strings (Japanese only), or else Sparkle's translation, without surrounding spaces.
+ (NSString *)textForKey:(NSString *)key sparkleKey:(NSString *)sparkleKey appBundle:(NSBundle *)appBundle sparkleBundle:(NSBundle *)sparkleBundle;
// The name of the application, as Sparkle shows it.
+ (NSString *)applicationNameOfBundle:(NSBundle *)bundle;
// Sparkle offers automatic downloads unless SUAllowsAutomaticUpdates is NO in Info.plist.
// (SPUUpdater.allowsAutomaticUpdates stays NO until automatic checks are turned on.)
+ (BOOL)offersAutomaticDownloadsForBundle:(NSBundle *)bundle;

// downloadsOn is the first state of the box, SUAutomaticallyUpdate as Sparkle reads it.
- (instancetype)initWithTarget:(id<TSUpdatePermissionTarget>)target appBundle:(NSBundle *)appBundle sparkleBundle:(NSBundle *)sparkleBundle downloadsOn:(BOOL)downloadsOn completion:(nullable void (^)(void))completion;
@property (nonatomic, readonly) NSAlert *alert;
@property (nonatomic, readonly) NSButton *downloadsCheckbox;
// Shows the alert as an ordinary window, as Sparkle does, so documents can still be opened.
- (void)show;
@end

NS_ASSUME_NONNULL_END
